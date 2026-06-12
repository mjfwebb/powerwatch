# powerwatch in Phoenix, Arizona (APS Time-of-Use)

Phoenix has no real-time spot market: APS customers pay a regulated time-of-use
(TOU) tariff with fixed on-peak / off-peak / super-off-peak rates that change
only by hour and season. So instead of fetching a live price, this example
serves a small static rate schedule and lets powerwatch's jq filter pick the
right rate for the current time, weekday and season.

The numbers here are the APS **"Time-of-Use 4pm-7pm Weekdays"** plan:

| Period | Hours | Summer (May-Oct) | Winter (Nov-Apr) |
|--------|-------|------------------|------------------|
| On-peak | 4pm-7pm, weekdays | $0.34396 | $0.32543 |
| Super off-peak | 10am-3pm, **winter** weekdays | n/a | $0.03495 |
| Off-peak | all other times, weekends, holidays | $0.12345 | $0.12351 |

## Setup

1. **Install powerwatch and make RAPL readable.** Follow the
   [main README](../../README.md) (the `install` line plus the one-time udev
   rule). Confirm it runs: `powerwatch` should print a live `[AC]` line.

2. **Check the rates.** Open [`aps-time-of-use.json`](aps-time-of-use.json) and
   compare against your latest APS bill (rates change, and your plan may differ).
   The values are USD/kWh and exclude the basic service charge, adjustors and
   taxes. If you want those folded in, bump the rates or use the
   `POWERWATCH_MARKUP` / `POWERWATCH_VAT` knobs (see the main README).

3. **Run it.**

   ```bash
   ./run.sh        # refresh every 5 s
   ./run.sh 2      # pass through a 2 s interval
   ```

   The header shows `LIVE spot → <rate> USD/kWh`, and the rate switches as you
   cross 4pm / 7pm and between seasons.

That's it. To make it your default, add an alias:

```bash
alias powerwatch-az='/path/to/powerwatch/examples/arizona-phoenix/run.sh'
```

## How it works

`run.sh` sets three environment variables and execs `powerwatch`:

- `POWERWATCH_PRICE_URL` points at the local schedule via a `file://` URL.
- `POWERWATCH_PRICE_JQ` is a jq program that reads that JSON and returns the
  rate for now, using the `$t` (HH:MM), `$dow` (1=Mon..7=Sun) and `$date`
  arguments powerwatch provides.
- `POWERWATCH_CURR=USD` labels the output.

powerwatch fetches the schedule once and caches it, but re-runs the jq filter
every refresh, so on/off-peak transitions show up live.

## Notes and limits

- **Editing rates:** powerwatch caches the fetched schedule under
  `~/.cache/powerwatch/`. After editing `aps-time-of-use.json`, clear it so the
  change is picked up: `rm -rf ~/.cache/powerwatch`.
- **Holidays** are not modeled: a weekday holiday is treated as a normal
  on-peak weekday. The ~12 APS holidays are actually billed off-peak, so the
  estimate runs slightly high on those days.
- **SRP or another APS plan:** edit the hours and rates in the JSON (and the
  on/super-off windows in `run.sh` if they differ). SRP's demand charges can't
  be modeled from an energy rate alone, so treat SRP as energy-only here.
- This is a **cost estimate** for your compute draw, with the same caveats as
  the main tool: on AC it undercounts wall draw (see the main README).
