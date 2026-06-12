# powerwatch

A live terminal monitor that turns a Linux laptop's power sensors into
cumulative energy (Wh/kWh), a running electricity cost, and a projected
daily/monthly run rate. It reads CPU/SoC power from Intel RAPL or, on AMD APUs
(e.g. the Steam Deck), the `amdgpu` sensor, adds an NVIDIA dGPU if present, and
uses the battery's own draw when unplugged.

![powerwatch output: a pinned reverse-video header bar above scrolling rows of timestamped watts (green when low, yellow when higher), the cpu+gpu split, session Wh and cost, the live rate, a run-rate projection, and a sparkline](example.svg)

Each refresh shows current watts, session energy and cost, a projected
`~kWh/day` and `~cost/month`, and a sparkline of recent power, tagged `[AC]` or
`[BAT]` for the live measurement path.

The header is pinned to the top while the rows scroll beneath it. Press
**Shift+Tab** to switch to a scrolling layout that keeps history in your
terminal's scrollback (or start with `POWERWATCH_STICKY=0`).

## Install

```bash
install -Dm755 powerwatch ~/.local/bin/powerwatch   # ~/.local/bin must be on PATH
```

The installed copy is a snapshot; re-run that line after editing the script to
update it.

## Setup: read the CPU power sensor (Intel, one-time)

Linux restricts the Intel CPU power sensor to root. Let your user read it:

```bash
sudo cp 99-powercap-readable.rules /etc/udev/rules.d/
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=powercap
sudo chmod -R a+r /sys/devices/virtual/powercap/   # apply now, without a reboot
```

Without it powerwatch still runs, but on AC it sees only the GPU and reads low
(it says so in the header); on battery it is accurate either way. **AMD APUs
need no setup**: their `amdgpu` sensor is readable already.

## Usage

```bash
powerwatch        # refresh every 5 s (default)
powerwatch 2      # every 2 s
```

### Pricing

By default powerwatch costs energy at a flat rate per kWh:

```bash
POWERWATCH_RATE=1.80 POWERWATCH_CURR=USD powerwatch
```

Set `POWERWATCH_LIVE=1` to fetch live spot prices and build an all-in rate of
`(spot + markup + grid + tax) × VAT`, priced per slot and cached under
`~/.cache/powerwatch/`. It needs `curl` and `jq`, and falls back to
`POWERWATCH_RATE` on any fetch failure.

| Var | Meaning | Default |
|-----|---------|---------|
| `POWERWATCH_LIVE` | enable live spot pricing | `0` |
| `POWERWATCH_ZONE` | bidding zone for the price URL | _(none)_ |
| `POWERWATCH_RATE` | fixed price per kWh | `2.50` |
| `POWERWATCH_CURR` | currency label | _(none)_ |
| `POWERWATCH_MARKUP` / `_GRID` / `_TAX` | fees added to the spot price, per kWh | `0` |
| `POWERWATCH_VAT` | VAT / sales-tax multiplier | `1` |

Live pricing defaults to the free
[elprisetjustnu.se](https://www.elprisetjustnu.se/) (Nord Pool) API; just set
your `POWERWATCH_ZONE`:

```bash
POWERWATCH_LIVE=1 POWERWATCH_ZONE=<zone> \
  POWERWATCH_MARKUP=0.08 POWERWATCH_GRID=0.30 POWERWATCH_VAT=1.25 powerwatch
```

Any JSON provider works via `POWERWATCH_PRICE_URL` and `POWERWATCH_PRICE_JQ`
(URL placeholders and jq args are documented in the script header). This also
covers static time-of-use tariffs; see
[`examples/arizona-phoenix`](examples/arizona-phoenix) for a worked setup. Price
data: © [elprisetjustnu.se](https://www.elprisetjustnu.se/).

## Accuracy

On AC this is a compute estimate: RAPL plus dGPU leaves out the display
backlight, AC-adapter conversion loss (~10-15%), USB peripherals and battery
charging, so it undercounts what your wall meter sees. For bill-accurate
numbers, measure at the socket with a smart plug. On battery, the battery's own
power reading covers the whole machine and is genuinely accurate.

## Contributing

Tests live in `tests/` and run with
[bats](https://github.com/bats-core/bats-core) (`bats tests`); CI also runs
`shellcheck`. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and conventions.
