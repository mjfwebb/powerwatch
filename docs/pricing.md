# Pricing

Full pricing reference: live spot pricing, every variable, and custom JSON
providers. Part of the [powerwatch README](../README.md).

By default powerwatch costs energy at a flat `POWERWATCH_RATE` per kWh, with no
currency label:

```bash
POWERWATCH_RATE=1.80 POWERWATCH_CURR=USD powerwatch
```

## Live spot pricing (opt-in)

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

## Variables

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

## Default provider: Nord Pool via elprisetjustnu.se

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

## Bring your own provider

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
[`examples/arizona-phoenix`](../examples/arizona-phoenix) for a complete worked
setup (APS Time-of-Use, Phoenix).
