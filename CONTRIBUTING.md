# Contributing

powerwatch is a single bash 5 script (`powerwatch`) plus a udev rule and docs.
Bug reports, fixes, and provider configs for other electricity markets are all
welcome.

## Dev setup

There is nothing to build. Clone, edit `powerwatch`, and run it straight from
the working tree:

```bash
./powerwatch 2
```

The installed copy under `~/.local/bin` is a snapshot; re-run
`install -Dm755 powerwatch ~/.local/bin/powerwatch` to update it (see the
README).

Tools needed:

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
sourced (the guard sits just above the header section), so the tests source it
and call its functions directly. This puts a constraint on new code: above the
guard, only definitions and read-only discovery; anything that prints or loops
goes below it.

Conventions in the suite:

- No network: external commands (`curl`, `nvidia-smi`) are stubbed with small
  scripts placed on `PATH` under `$BATS_TEST_TMPDIR`.
- The cache is redirected via `XDG_CACHE_HOME` into the test tmpdir, so tests
  never touch `~/.cache/powerwatch`.
- Env vars are read at source time, so export them before `source "$PW"`.

Add a test for new behavior where you can. Code below the guard (the header
and main loop) is only covered by the smoke test, and that's fine.

## Linting

```bash
shellcheck powerwatch
```

The script is shellcheck-clean and CI enforces that. If shellcheck flags
something intentional, add a `# shellcheck disable=SCxxxx` directive on the
line above it with a short reason. Don't add global ignore lists.

## CI

`.github/workflows/ci.yml` runs bats and shellcheck on every push to `main`
and on every pull request. Both jobs must pass.

## Style

Match the existing code:

- bash 5, `printf` over `echo`, no subshells in the hot loop (results go in
  `REPLY`, see `pcolor`/`vis`/`sparkline`).
- Arithmetic that needs decimals goes through a single `awk` pass; the script
  forces `LC_ALL=C` so `.` is always the decimal separator.
- Missing sensors, commands, or network must reduce functionality (with a
  note in the header where it matters), never crash.
- Comments explain why (sensor quirks, locale traps, ordering constraints),
  not what the next line does.

## Pull requests

- Keep PRs focused; separate refactors from behavior changes.
- Update the README when flags, env vars, or output change.
- **Don't touch the `VERSION=` line in a feature or fix PR.** It is bumped
  once per release in its own commit on `main` (see Releases). Two open PRs
  that both edit it would otherwise conflict on the version, and merge order
  would silently decide the number.
- If the change touches the sensor paths (RAPL, battery, nvidia-smi), say how
  you tested it on real hardware, since CI can't.

## Releases

The version lives in one place: the `VERSION=` line in `powerwatch` (read, not
executed, by `install.sh` to report what an update did). It is owned by `main`,
not by PRs, so that parallel PRs never contend over the number. CI enforces this
from both sides:

- The `no-version-change` job fails any PR whose diff touches the `VERSION=`
  line.
- The `release` job runs on every push to `main` (after tests and lint pass).
  When `powerwatch` changed since the last tag, it cuts a release.

Patch releases are automatic: merging a fix to `main` makes the `release` job
bump the patch level, commit it, and tag `vX.Y.Z`.

For a **minor or major** release, edit the `VERSION=` line directly on `main`
(a maintainer push, not a PR) to the intended `X.Y.0`. The `release` job sees
the version already ahead of the last tag and just tags it, rather than
auto-bumping the patch.
