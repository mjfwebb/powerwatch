# powerwatch

A live terminal monitor that turns a Linux laptop's power sensors into
cumulative energy (Wh/kWh) and a running electricity cost, plus a projected
daily and monthly run rate. It works on any Intel machine (for the RAPL energy
counters) and uses an NVIDIA discrete GPU if one is present, falling back
gracefully when either is missing.

Refreshing on an interval, it shows:

- Current power in watts, split into CPU platform and dGPU on AC.
- Session energy (`Σ … Wh`) since launch, and its cost at your tariff.
- A run rate projection, `~kWh/day` and `~cost/month`, extrapolated from the
  running average power, so you can see what your current workload costs over time.
- A sparkline of recent total power (last 40 samples, scaled 0-100 W).
- An `[AC]` or `[BAT]` tag showing which measurement path is live.

## Install

It lives on `PATH` at `~/.local/bin/powerwatch`, so you can run it from any
directory as `powerwatch`:

```bash
install -Dm755 powerwatch ~/.local/bin/powerwatch   # ~/.local/bin must be on PATH
```

### Updating

The installed copy is a snapshot. Edits to `powerwatch` in this project dir do
not take effect until you re-install, so re-run the same line after changing the
script:

```bash
install -Dm755 powerwatch ~/.local/bin/powerwatch
```

`install -m755` overwrites in place and keeps it executable. To check which copy
is live, run `which powerwatch`; to uninstall, `rm ~/.local/bin/powerwatch`.

## Setup: let powerwatch read the CPU power sensor (one-time)

By default Linux only lets the root user read the CPU's built-in power sensor.
Run these commands once to let your normal user read it too:

```bash
sudo cp 99-powercap-readable.rules /etc/udev/rules.d/
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=powercap
# apply right away, without a reboot:
sudo chmod -R a+r /sys/devices/virtual/powercap/
```

That's it, and it sticks across reboots. If you skip this, powerwatch still runs,
but on AC power it can only see the GPU, so the wattage reads low (it says so in
the header). On battery it works either way.

> Why is it root-only? The sensor was locked down to block a hardware
> side-channel attack (CVE-2020-8694, "PLATYPUS"). The readings are just energy
> counters, so re-enabling them for yourself on a personal machine is low risk.

## Usage

```bash
powerwatch        # refresh every 5 s (default)
powerwatch 2      # refresh every 2 s
```

### Pricing

By default powerwatch costs energy at a flat `POWERWATCH_RATE` per kWh, with no
currency label. Set the rate, currency, and (optionally) a VAT/sales-tax
multiplier to match your tariff:

```bash
POWERWATCH_RATE=1.80 POWERWATCH_CURR=USD powerwatch
```

#### Live spot pricing (opt-in)

Set `POWERWATCH_LIVE=1` and powerwatch fetches the spot price for the current
slot from a JSON provider, then builds an all-in price per kWh:

```
rate = (spot + markup + grid + tax) × VAT
```

The day's prices are fetched once and cached under `~/.cache/powerwatch/`. Each
refresh prices the interval at the slot that was actually in force, and session
cost accumulates accordingly. The live rate shows per line as `@<rate>L` (`F`
means the fixed fallback). On any fetch failure it falls back to
`POWERWATCH_RATE`.

> The spot price excludes VAT, taxes and surcharges. To match your own bill, set
> the markup and grid fees from your invoice and the tax/VAT for your country.

| Var | Meaning | Default |
|-----|---------|---------|
| `POWERWATCH_LIVE` | enable live spot pricing | `0` |
| `POWERWATCH_ZONE` | bidding zone, substituted into the URL template | _(none)_ |
| `POWERWATCH_PRICE_URL` | price-endpoint URL template (see below) | elprisetjustnu.se |
| `POWERWATCH_PRICE_JQ` | jq filter that prints the price for now | elprisetjustnu filter |
| `POWERWATCH_MARKUP` | supplier markup, price/kWh ex tax | `0` |
| `POWERWATCH_GRID` | grid transfer fee, price/kWh ex tax | `0` |
| `POWERWATCH_TAX` | energy tax, price/kWh ex VAT | `0` |
| `POWERWATCH_VAT` | VAT / sales-tax multiplier | `1` |
| `POWERWATCH_RATE` | fixed price per kWh | `2.50` |
| `POWERWATCH_CURR` | currency label | _(none)_ |

Live pricing needs `curl` and `jq` on `PATH`; without them it auto-disables and
uses the fixed rate.

##### Default provider: Nord Pool via elprisetjustnu.se

Out of the box it targets the free
[`elprisetjustnu.se`](https://www.elprisetjustnu.se/elpris-api) API (no key
needed), which serves the Nordic bidding zones. Pick yours with
`POWERWATCH_ZONE`:

```bash
# live spot for your zone, with your contract's fees and tax (example numbers):
POWERWATCH_LIVE=1 POWERWATCH_ZONE=<zone> \
  POWERWATCH_MARKUP=0.08 POWERWATCH_GRID=0.30 POWERWATCH_VAT=1.25 powerwatch
```

Price data: © [elprisetjustnu.se](https://www.elprisetjustnu.se/).

##### Bring your own provider

Any API that returns JSON works. Point `POWERWATCH_PRICE_URL` at the endpoint
that serves the current day's prices and give `POWERWATCH_PRICE_JQ` a jq program
that extracts the price for "now".

The URL template is expanded per request with these placeholders:
`{year}` `{month}` `{day}` (zero-padded), `{date}` (`YYYY-MM-DD`), and `{zone}`.
The jq program receives the fetched JSON on stdin plus, for the current local
time, `--arg t` (`HH:MM`), `--arg hour` (`HH`), `--arg date` (`YYYY-MM-DD`) and
`--arg dow` (ISO weekday, `1`=Mon .. `7`=Sun). It should print the spot price per
kWh, or nothing to fall back to the fixed rate. For example, an API returning
`{"slots": [{"start": "14:00", "price": 0.42}, ...]}`:

```bash
POWERWATCH_LIVE=1 \
  POWERWATCH_PRICE_URL='https://example.com/prices/{date}.json' \
  POWERWATCH_PRICE_JQ='[ .slots[] | select(.start <= $t) ] | last | .price' \
  POWERWATCH_CURR=EUR powerwatch
```

The cache key is derived from the resolved URL, so switching providers or zones
never reuses a stale file. Include a date placeholder (`{date}` or
`{year}`/`{month}`/`{day}`) in the URL so the cache rotates day to day; without
one, the first fetch is reused until the cache is cleared.

This also works for a regulated time-of-use tariff with no live API: serve a
static rate schedule (even a local `file://` JSON) and let the jq program pick
the rate by `$t`/`$dow`/`$date`. See
[`examples/arizona-phoenix`](examples/arizona-phoenix) for a complete worked
setup (APS Time-of-Use, Phoenix).

Press `Ctrl+C` to quit. It needs no root at runtime once the udev rule is in
place, since it only reads `/sys`.

## Why these numbers (and what they miss)

| Source | What it covers | Notes |
|--------|----------------|-------|
| Intel RAPL `psys` (`/sys/class/powercap/intel-rapl:*`) | CPU package, iGPU, DRAM, VRMs | Read as a monotonic µJ energy counter, so interval energy is exact. Root-only by default (see the udev rule above). |
| NVIDIA dGPU (`nvidia-smi`) | The discrete GPU | On its own rail, not in RAPL. It runtime-suspends in hybrid/Optimus mode and reports no data, which powerwatch counts as ~0 W. |
| Battery `power_now` | The whole laptop (CPU, GPU, screen, everything) | Only valid on battery. When unplugged it supersedes the estimate above and is genuinely accurate. |

> **On AC this is a compute estimate, not wall draw.** RAPL plus dGPU leaves out
> the display backlight, the AC adapter's roughly 10-15% conversion loss, USB
> peripherals and battery charging, so it undercounts what your meter sees. For
> bill-accurate numbers, measure at the socket with a smart plug (Kasa, Shelly,
> Tasmota, Zigbee). On battery, `power_now` is accurate for the laptop itself.

## How it reads things

| Value | Source |
|-------|--------|
| CPU platform energy | `/sys/class/powercap/intel-rapl:*/energy_uj` (psys, falling back to `package-0`) |
| counter wrap point | `…/max_energy_range_uj` |
| dGPU power | `nvidia-smi -q -d POWER` ("Power Draw"); absent means 0 W (suspended) |
| on-battery total | the discovered battery's `power_now` (µW) |
| AC vs battery | the AC adapter's `online` flag |

Interval timing uses bash 5's `EPOCHREALTIME`, and the script forces `LC_ALL=C`
so a locale comma decimal separator does not corrupt the arithmetic.
