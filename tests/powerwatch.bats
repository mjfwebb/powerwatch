#!/usr/bin/env bats
# Unit tests for powerwatch's pure logic. The script returns early when
# sourced, so each test sources it fresh (bats isolates tests in subshells)
# with the env vars under test exported beforehand, since the script reads
# them at source time.

setup() {
  PW="$BATS_TEST_DIRNAME/../powerwatch"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  STUB_DIR="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_DIR"
}

# Put a fake curl on PATH. With an argument, it "serves" that fixture file to
# curl's -o target; without one, it fails like a network error. Every
# invocation is logged so tests can count fetches.
stub_curl() {
  local fixture=${1:-}
  cat >"$STUB_DIR/curl" <<EOF
#!/usr/bin/env bash
echo called >>"$STUB_DIR/curl.log"
out=""
while (( \$# )); do [[ \$1 == -o ]] && out=\$2; shift; done
[[ -n "$fixture" ]] || exit 1
cp "$fixture" "\$out"
EOF
  chmod +x "$STUB_DIR/curl"
  export PATH="$STUB_DIR:$PATH"
}

curl_calls() { wc -l <"$STUB_DIR/curl.log" 2>/dev/null || echo 0; }

# Day-price fixture in the default provider's (elprisetjustnu.se) shape.
write_price_fixture() {
  cat >"$BATS_TEST_TMPDIR/prices.json" <<'EOF'
[
  {"SEK_per_kWh": 0.10, "time_start": "2026-06-12T00:00:00+02:00"},
  {"SEK_per_kWh": 0.42, "time_start": "2026-06-12T13:00:00+02:00"},
  {"SEK_per_kWh": 0.99, "time_start": "2026-06-12T14:00:00+02:00"}
]
EOF
}

# --- price_url: URL template expansion ---------------------------------------

@test "price_url expands all placeholders" {
  export POWERWATCH_PRICE_URL='https://x/{year}/{month}/{day}/{date}_{zone}.json'
  export POWERWATCH_ZONE=SE3
  source "$PW"
  run price_url "2026-06-12"
  [ "$output" = "https://x/2026/06/12/2026-06-12_SE3.json" ]
}

@test "price_url default template targets elprisetjustnu.se" {
  export POWERWATCH_ZONE=SE3
  source "$PW"
  run price_url "2026-01-05"
  [ "$output" = "https://www.elprisetjustnu.se/api/v1/prices/2026/01-05_SE3.json" ]
}

# --- live-pricing enablement guards ------------------------------------------

@test "LIVE auto-disables when the URL needs a zone and none is set" {
  export POWERWATCH_LIVE=1
  source "$PW"
  [ "$LIVE" -eq 0 ]
}

@test "LIVE stays on with a zone-free custom URL" {
  export POWERWATCH_LIVE=1 POWERWATCH_PRICE_URL='https://x/{date}.json'
  stub_curl
  source "$PW"
  [ "$LIVE" -eq 1 ]
}

@test "LIVE auto-disables without curl on PATH" {
  export POWERWATCH_LIVE=1 POWERWATCH_ZONE=SE3
  # a PATH with jq but no curl
  ln -s "$(command -v jq)" "$STUB_DIR/jq"
  ln -s "$(command -v bash)" "$STUB_DIR/bash"
  PATH="$STUB_DIR" source "$PW"
  [ "$LIVE" -eq 0 ]
}

# --- fetch_day: fetching and caching -----------------------------------------

@test "fetch_day fetches once, then serves from cache" {
  export POWERWATCH_LIVE=1 POWERWATCH_PRICE_URL='https://x/{date}.json'
  write_price_fixture
  stub_curl "$BATS_TEST_TMPDIR/prices.json"
  source "$PW"
  f1=$(fetch_day "2026-06-12")
  f2=$(fetch_day "2026-06-12")
  [ "$f1" = "$f2" ]
  [ -s "$f1" ]
  [ "$(curl_calls)" -eq 1 ]
}

@test "fetch_day uses distinct cache files per day" {
  export POWERWATCH_LIVE=1 POWERWATCH_PRICE_URL='https://x/{date}.json'
  write_price_fixture
  stub_curl "$BATS_TEST_TMPDIR/prices.json"
  source "$PW"
  f1=$(fetch_day "2026-06-12")
  f2=$(fetch_day "2026-06-13")
  [ "$f1" != "$f2" ]
  [ "$(curl_calls)" -eq 2 ]
}

@test "fetch_day fails cleanly on fetch error, leaving no cache file" {
  export POWERWATCH_LIVE=1 POWERWATCH_PRICE_URL='https://x/{date}.json'
  stub_curl   # no fixture: curl exits 1
  source "$PW"
  run fetch_day "2026-06-12"
  [ "$status" -ne 0 ]
  run find "$XDG_CACHE_HOME/powerwatch" -type f
  [ -z "$output" ]
}

# --- eff_rate: all-in price construction -------------------------------------

@test "eff_rate returns the fixed rate when live pricing is off" {
  export POWERWATCH_RATE=1.75
  source "$PW"
  run eff_rate
  [ "$status" -eq 1 ]
  [ "$output" = "1.75" ]
}

@test "eff_rate builds (spot+markup+grid+tax)*VAT from the live spot" {
  export POWERWATCH_LIVE=1 POWERWATCH_PRICE_URL='https://x/{date}.json'
  export POWERWATCH_MARKUP=0.08 POWERWATCH_GRID=0.30 POWERWATCH_TAX=0.02 POWERWATCH_VAT=1.25
  stub_curl
  source "$PW"
  spot_now() { echo "0.40"; }
  run eff_rate
  [ "$status" -eq 0 ]
  # (0.40 + 0.08 + 0.30 + 0.02) * 1.25 = 1.0000
  [ "$output" = "1.0000" ]
}

@test "eff_rate falls back to the fixed rate on a non-numeric spot" {
  export POWERWATCH_LIVE=1 POWERWATCH_PRICE_URL='https://x/{date}.json'
  export POWERWATCH_RATE=2.50
  stub_curl
  source "$PW"
  for bad in "" "null" "1,5" "abc"; do
    eval "spot_now() { echo '$bad'; }"
    run eff_rate
    [ "$status" -eq 1 ]
    [ "$output" = "2.50" ]
  done
}

# --- default jq filter against the provider's document shape ------------------

@test "default jq filter picks the slot in force at the given time" {
  source "$PW"
  write_price_fixture
  run jq -r --arg t "13:30" "$DEFAULT_PRICE_JQ" "$BATS_TEST_TMPDIR/prices.json"
  [ "$output" = "0.42" ]
}

@test "default jq filter prints nothing before the first slot" {
  source "$PW"
  echo '[{"SEK_per_kWh": 0.10, "time_start": "2026-06-12T05:00:00+02:00"}]' \
    >"$BATS_TEST_TMPDIR/prices.json"
  run jq -r --arg t "01:00" "$DEFAULT_PRICE_JQ" "$BATS_TEST_TMPDIR/prices.json"
  [ -z "$output" ]
}

# --- gpu_w: nvidia-smi parsing -----------------------------------------------

@test "gpu_w extracts the Power Draw wattage" {
  cat >"$STUB_DIR/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
printf '    Power Draw                        : 12.34 W\n'
EOF
  chmod +x "$STUB_DIR/nvidia-smi"
  export PATH="$STUB_DIR:$PATH"
  source "$PW"
  run gpu_w
  [ "$output" = "12.34" ]
}

@test "gpu_w reports 0 when the GPU is runtime-suspended (N/A)" {
  cat >"$STUB_DIR/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
printf '    Power Draw                        : N/A\n'
EOF
  chmod +x "$STUB_DIR/nvidia-smi"
  export PATH="$STUB_DIR:$PATH"
  source "$PW"
  run gpu_w
  [ "$output" = "0" ]
}

@test "gpu_w reports 0 without nvidia-smi" {
  source "$PW"
  have_nvidia=0
  run gpu_w
  [ "$output" = "0" ]
}

# --- sparkline ----------------------------------------------------------------

@test "sparkline maps 0/50/100 W to bottom/middle/top glyphs" {
  source "$PW"
  hist=(0 50 100)
  sparkline 10
  [ "$REPLY" = "▁▄█" ]
}

@test "sparkline clamps out-of-range samples" {
  source "$PW"
  hist=(-5 200)
  sparkline 10
  [ "$REPLY" = "▁█" ]
}

@test "sparkline keeps only the most recent max samples" {
  source "$PW"
  hist=(0 0 0 100 100)
  sparkline 2
  [ "$REPLY" = "██" ]
}

@test "sparkline is empty for a zero or negative width" {
  source "$PW"
  hist=(50 50)
  sparkline 0
  [ -z "$REPLY" ]
  sparkline -3
  [ -z "$REPLY" ]
}

# --- vis: visible column width ------------------------------------------------

@test "vis counts plain ASCII" {
  source "$PW"
  vis "hello"
  [ "$REPLY" -eq 5 ]
}

@test "vis ignores color escape sequences" {
  source "$PW"
  vis $'\e[1m\e[31mab\e[0m'
  [ "$REPLY" -eq 2 ]
}

@test "vis counts multibyte glyphs as one column" {
  source "$PW"
  vis "Σ 5 Wh €"
  [ "$REPLY" -eq 8 ]
}

# --- pcolor thresholds ----------------------------------------------------------

@test "pcolor picks green <20W, yellow <60W, red above" {
  source "$PW"
  G=GREEN Y=YELLOW R=RED
  pcolor 19;  [ "$REPLY" = GREEN ]
  pcolor 20;  [ "$REPLY" = YELLOW ]
  pcolor 59;  [ "$REPLY" = YELLOW ]
  pcolor 60;  [ "$REPLY" = RED ]
}

# --- script smoke test ----------------------------------------------------------

@test "script starts, prints the header, and exits cleanly on SIGTERM" {
  out="$BATS_TEST_TMPDIR/out"
  bash "$PW" 60 >"$out" 2>&1 &
  pid=$!
  sleep 1
  kill "$pid"
  wait "$pid" || true
  grep -q "powerwatch  every 60s" "$out"
  grep -q "price: fixed 2.50" "$out"
}
