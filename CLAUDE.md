# Project guidance

powerwatch is a single bash 5 script (`powerwatch`) that reads laptop/desktop
power sensors and shows live energy use, cost, and projected burn rate. The
installer is `install.sh`. User-facing reference lives in `docs/`.

CONTRIBUTING.md is the source of truth for dev setup, style, CI, and the
release process. Read it before non-trivial changes. The notes below are the
points worth keeping in front of mind.

## Commands

- Tests: `bats tests`
- Lint: `shellcheck powerwatch install.sh`

Both must pass; CI runs exactly these. Install the tooling with
`sudo apt install bats jq shellcheck`. Run both before pushing.

## How the tests work

`powerwatch` returns early when sourced (the `[[ ${BASH_SOURCE[0]} != "$0" ]]
&& return 0` guard partway down the file). Everything above the guard is
definitions and read-only sensor discovery; the main loop is below it. Tests in
`tests/powerwatch.bats` source the script and call its pure functions directly,
so keep new pure logic above the guard and side effects below it.

Tests read configuration from `POWERWATCH_*` env vars at source time (export
them before sourcing), stub external commands (`curl`, `nvidia-smi`) by putting
fakes on `PATH`, and isolate the cache via `XDG_CACHE_HOME`. Don't make tests
hit the network or real hardware.

## Invariants

- **Never edit the `VERSION=` line in a feature/fix PR.** It is bumped once per
  release by the `release` job on `main`. The `no-version-change` CI check
  rejects PRs that touch it.
- **Every PR needs exactly one `bump:*` label** (`bump:major`, `bump:minor`,
  `bump:patch`, or `bump:none`); the `bump label` check (its own
  `pull_request_target` workflow) enforces and re-evaluates it on label change.
- Missing sensors, commands, or network must degrade gracefully (with a note in
  the header where it matters), never crash.

## Style

Match the surrounding code (full list in CONTRIBUTING.md, Style):

- bash 5, `printf` over `echo`. The script forces `LC_ALL=C` so `.` is always
  the decimal separator; awk relies on this.
- No subshells in the hot loop: return values via `REPLY` (see `pcolor`, `vis`,
  `sparkline`). Decimal arithmetic goes through a single `awk` pass per tick.
- Comments explain why (sensor quirks, locale traps, ordering), not what.
- Keep it shellcheck-clean. For an intentional finding, add a line-level
  `# shellcheck disable=SCxxxx` with a short reason, not a global ignore.
- No em dashes (the U+2014 character) anywhere: code, comments, docs, commit
  messages, or PR text. Rewrite with a comma, colon, semicolon, or parentheses.

## When changing things

- Power reading is per-platform (Intel RAPL, AMD APU, Raspberry Pi PMIC, NVIDIA
  dGPU, Windows via WMI/LibreHardwareMonitor, battery `power_now`), chosen once
  at startup. CI can't exercise real sensors, so if you touch a sensor path say
  how you tested it on that hardware.
- Update `docs/` and the README when flags, env vars, or output change
  (`docs/configuration.md`, `docs/pricing.md`, `docs/display.md`,
  `docs/sensors.md`).
- Keep PRs focused; separate refactors from behavior changes.
