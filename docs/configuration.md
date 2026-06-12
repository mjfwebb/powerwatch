# Configuration

Complete reference for every powerwatch setting. Part of the
[powerwatch README](../README.md).

Every setting can be given two ways — a `POWERWATCH_*` environment variable or a
command-line flag — and they are exactly equivalent. When both are present the
flag wins, so the order of precedence is:

```
command-line flag  >  environment variable  >  built-in default
```

Run `powerwatch --help` for the same list at the terminal.

## The refresh interval

The refresh interval (seconds between updates) is the one positional argument,
and also has a flag. It defaults to 5 and must be a positive number.

```bash
powerwatch 2              # positional
powerwatch --interval 2   # flag (-n 2)
```

## All settings

| Env var | Flag (long, short) | Meaning | Default |
|---|---|---|---|
| _(positional)_ | `--interval N` · `-n` | refresh interval, seconds | `5` |
| `POWERWATCH_RATE` | `--rate N` · `-r` | fixed price per kWh | `2.50` |
| `POWERWATCH_CURR` | `--curr LABEL` · `-c` | currency label shown after costs | _(none)_ |
| `POWERWATCH_STICKY` | `--sticky` / `--no-sticky` / `--scroll` | pin the header (`1`) or scroll naturally (`0`) | `1` |
| `POWERWATCH_LIVE` | `--live` / `--no-live` · `-L` | enable live spot pricing | `0` |
| `POWERWATCH_ZONE` | `--zone ZONE` · `-z` | bidding zone, substituted into the price URL | _(none)_ |
| `POWERWATCH_MARKUP` | `--markup N` · `-m` | supplier markup, price/kWh ex tax | `0` |
| `POWERWATCH_GRID` | `--grid N` · `-g` | grid transfer fee, price/kWh ex tax | `0` |
| `POWERWATCH_TAX` | `--tax N` · `-t` | energy tax, price/kWh ex VAT | `0` |
| `POWERWATCH_VAT` | `--vat N` · `-V` | VAT / sales-tax multiplier | `1` |
| `POWERWATCH_PRICE_URL` | `--price-url U` · `-u` | price-endpoint URL template | elprisetjustnu.se |
| `POWERWATCH_PRICE_JQ` | `--price-jq P` · `-j` | jq program that prints the price for now | Nord Pool filter |

Boolean flags take no value: `--live` enables live pricing, `--no-live` disables
it; `--no-sticky` (or `--scroll`) turns off the pinned header. Value flags accept
either `--rate 1.80` or `--rate=1.80`, and short forms `-r 1.80`.

### Display

`POWERWATCH_STICKY` / `--sticky` / `--no-sticky` controls whether the header is
pinned to the top of the terminal or scrolls naturally (keeping rows in your
scrollback). You can also toggle it live with **Shift+Tab**. See the
[output and layout reference](display.md) for the full details, including the
column set and width adaptation.

### Pricing

`RATE` and `CURR` set the flat fallback tariff. The remaining pricing settings
(`LIVE`, `ZONE`, `MARKUP`, `GRID`, `TAX`, `VAT`, `PRICE_URL`, `PRICE_JQ`) drive
live spot pricing, which builds an all-in rate of
`(spot + markup + grid + tax) × VAT`. Live pricing needs `curl` and `jq`; without
them, or on any fetch failure, it falls back to the fixed `RATE`. For the pricing
math, the default Nord Pool provider, bringing your own JSON provider, and static
time-of-use tariffs, see the [pricing guide](pricing.md).

## Examples

Each pair below is equivalent — environment variables on the left, flags on the
right:

```bash
# flat rate, every 2 seconds
POWERWATCH_RATE=1.80 POWERWATCH_CURR=USD powerwatch 2
powerwatch 2 --rate 1.80 --curr USD

# live spot pricing for a Nord Pool zone, with your contract's fees
POWERWATCH_LIVE=1 POWERWATCH_ZONE=SE3 \
  POWERWATCH_MARKUP=0.08 POWERWATCH_GRID=0.30 POWERWATCH_VAT=1.25 powerwatch
powerwatch --live --zone SE3 --markup 0.08 --grid 0.30 --vat 1.25

# scroll naturally instead of pinning the header
POWERWATCH_STICKY=0 powerwatch
powerwatch --no-sticky
```

Flags and env vars can be mixed freely; a flag just overrides the matching env
var for that run.
