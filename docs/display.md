# Output and layout

Reference for what powerwatch prints and how it uses the terminal. Part of the
[powerwatch README](../README.md).

## Columns

Each refresh shows:

- Current power in watts, split into CPU/SoC platform and dGPU on AC.
- Session energy (`Σ … Wh`) since launch, and its cost at your tariff.
- A run rate projection, `~kWh/day` and `~cost/month`, extrapolated from the
  running average power: what your current workload costs over time.
- A sparkline of recent total power (up to 40 samples, scaled 0-100 W).
- An `[AC]` or `[BAT]` tag showing which measurement path is live.

## Width adaptation

The row adapts to your terminal width: the sparkline grows or shrinks to fill
the space left, and on a narrow terminal the run-rate projection (and then the
sparkline) drop off to keep the line from wrapping. The core columns (time
through rate) are always shown, so a terminal narrower than they need (about
70 columns) will still wrap.

## Pinned header and scrollback

On an interactive terminal the banner and column headers are pinned to the top
by default: the data rows scroll beneath them (via a scroll region) so the
headers stay visible no matter how long it runs. The trade-off is that rows
which scroll past the top are not kept in the terminal's scrollback. Set
`POWERWATCH_STICKY=0` to scroll naturally instead: the header is reprinted
every screenful rather than frozen, which keeps old rows in your scrollback. (A
fixed header and scrollback are mutually exclusive: a terminal only feeds a line
to scrollback when it scrolls off the real top of the screen, which a pinned
header prevents.) When output is piped or redirected, the header is printed once
inline regardless.

Press **Shift+Tab** at any time to toggle between the two layouts live, so you
can leave it pinned while watching and flip to scrolling when you want to scroll
back through history.
