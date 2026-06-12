# Contributing

powerwatch is a single bash 5 script (`powerwatch`) plus a udev rule and docs.
Changes of any size are welcome — bug reports and provider configs for other
electricity markets especially so.

## Dev setup

There is nothing to build. Clone, edit `powerwatch`, and run it straight from
the working tree:

```bash
./powerwatch 2
```

Note that the installed copy under `~/.local/bin` is a snapshot; re-run
`install -Dm755 powerwatch ~/.local/bin/powerwatch` to update it (see the
README).

You'll want these on `PATH`:

| Tool | Used for |
|------|----------|
| `bash` ≥ 5 | the script itself (`EPOCHREALTIME`) |
| [`bats`](https://github.com/bats-core/bats-core) | running the tests |
| `jq` | the pricing tests (and live pricing at runtime) |
| [`shellcheck`](https://www.shellcheck.net/) | linting |

On Debian/Ubuntu: `sudo apt install bats jq shellcheck`.

## Tests

```bash
bats tests
```

The suite lives in `tests/powerwatch.bats`. The script returns early when
*sourced* (the guard sits just above the header section), so tests source it
and call its functions directly — everything above the guard must stay
side-effect-free beyond read-only discovery, and everything that prints or
loops must stay below it. Keep it that way when adding code.

Conventions in the suite:

- No network: external commands (`curl`, `nvidia-smi`) are stubbed with small
  scripts placed on `PATH` under `$BATS_TEST_TMPDIR`.
- The cache is redirected via `XDG_CACHE_HOME` into the test tmpdir, so tests
  never touch `~/.cache/powerwatch`.
- Env vars are read at source time, so export them *before* `source "$PW"`.

New behavior should come with a test when it's testable in isolation (anything
below the source guard — header layout, the main loop — is exercised only by
the smoke test, which is fine).

## Linting

```bash
shellcheck powerwatch
```

The script is shellcheck-clean and CI enforces that. If shellcheck flags a
pattern that is genuinely intentional, add a targeted
`# shellcheck disable=SCxxxx` directive on the line above it with a brief
justification — don't widen the CI invocation's scope or ignore lists.

## CI

`.github/workflows/ci.yml` runs both of the above (bats + shellcheck) on every
push to `main` and on every pull request. Both jobs must pass.

## Style

Match the existing code:

- bash 5, `printf` over `echo`, no subshells in the hot loop (results go in
  `REPLY`, see `pcolor`/`vis`/`sparkline`).
- Arithmetic that needs decimals goes through a single `awk` pass; the script
  forces `LC_ALL=C` so `.` is always the decimal separator.
- Degrade gracefully: missing sensors, commands, or network must reduce
  functionality (with a note in the header where it matters), never crash.
- Comments explain *why* — sensor quirks, locale traps, ordering constraints —
  not what the next line does.

## Pull requests

- Keep PRs focused; separate refactors from behavior changes.
- Update the README when flags, env vars, or output change.
- Describe how you tested on real hardware when the change touches the sensor
  paths (RAPL, battery, nvidia-smi) — CI can't see those.
