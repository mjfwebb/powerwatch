# What powerwatch measures

How each power source is read, what it covers, and what it misses. Part of the
[powerwatch README](../README.md).

## Sources

| Source | What it covers | Notes |
|--------|----------------|-------|
| Intel RAPL `psys` (`/sys/class/powercap/intel-rapl:*`) | CPU package, iGPU, DRAM, VRMs | Read as a monotonic µJ energy counter, so interval energy is exact. Root-only by default (see the udev setup in the README). Linux only. |
| Discrete GPU: NVIDIA (`nvidia-smi`) or AMD (`amdgpu` hwmon `power1_input`) | The discrete GPU | On its own rail, not in RAPL, so it is added to the platform power on AC. NVIDIA is read from `nvidia-smi` (Linux and Windows) and runtime-suspends in hybrid/Optimus mode, reporting no data, counted as ~0 W; an AMD discrete Radeon is read from its `amdgpu` hwmon `power1_input` (Linux). An **Intel iGPU is not added here**: it is already inside RAPL's package/psys domain, so counting it again would double-count. Intel Arc discrete GPUs are not yet supported (see below). |
| AMD APU `slowPPT` (`amdgpu` hwmon `power1_input`) | The SoC package (CPU + iGPU) | Fallback used on Ryzen APUs (e.g. the Steam Deck) where RAPL is root-only and excludes the iGPU. Read without root as instantaneous watts and integrated over the interval. Linux only. |
| Raspberry Pi PMIC (`vcgencmd pmic_read_adc`) | The whole board (SoC, RAM, USB, I/O rails) | Used on a Pi (5 and up), which has neither RAPL nor an `amdgpu` sensor. The PMIC reports every supply rail's current and voltage; powerwatch sums current×voltage across the rails. Read without root as instantaneous watts and integrated over the interval. Linux only. |
| Battery `power_now` | The whole laptop (CPU, GPU, screen, everything) | Only valid on battery. When unplugged it supersedes the estimate above and is genuinely accurate. Machines without `power_now` (e.g. the Steam Deck) are read from `current_now × voltage_now` instead. Linux only. |
| Windows WMI `BatteryStatus.DischargeRate` | The whole laptop (same coverage as `power_now`) | Used on Windows 11 (MSYS2/Git Bash, Cygwin, WSL). Queried via PowerShell `Get-CimInstance`, at most once every `POWERWATCH_WIN_POLL` seconds (default 5) since each spawn is costly; the value is reused between polls. Reports instantaneous discharge in mW, which powerwatch multiplies to µW for the same integration path as Linux. |
| macOS `AppleSmartBattery` (`ioreg`) | The whole laptop (same coverage as `power_now`) | Used on macOS on battery. `Amperage × Voltage` from IOKit, accurate and needing no root. Amperage is a signed mA value IOKit stores unsigned; powerwatch decodes it in 64-bit signed bash arithmetic (awk's floats would corrupt it). One `ioreg` read per tick also yields the AC-online flag. |
| macOS `powermetrics` (CPU+GPU+ANE) | The SoC package (CPU + GPU + Neural Engine) | Used on macOS on AC, where no unprivileged power sensor exists on Apple Silicon. Needs root, so it runs under passwordless `sudo` (see the README); without that grant powerwatch is battery-only on macOS. Read as instantaneous watts and integrated over the interval, polled at most every `POWERWATCH_MAC_POLL` seconds (default 5). |

> **On AC this is a compute estimate, not wall draw.** RAPL plus dGPU leaves out
> the display backlight, the AC adapter's roughly 10-15% conversion loss, USB
> peripherals and battery charging, so it undercounts what your meter sees. For
> bill-accurate numbers, measure at the socket with a smart plug (Kasa, Shelly,
> Tasmota, Zigbee). On battery, `power_now` is accurate for the laptop itself.

## How it reads things

### Linux

| Value | Source |
|-------|--------|
| CPU platform energy | `/sys/class/powercap/intel-rapl:*/energy_uj` (psys, falling back to `package-0`) |
| counter wrap point | `…/max_energy_range_uj` |
| AMD APU power | `amdgpu` hwmon `power1_input` (label `slowPPT`), when the RAPL counter is unreadable |
| Raspberry Pi power | `vcgencmd pmic_read_adc`, summing each rail's current×voltage, when there is no RAPL or `amdgpu` sensor |
| dGPU power | NVIDIA: `nvidia-smi -q -d POWER` ("Power Draw"), absent means 0 W (suspended). AMD discrete: `amdgpu` hwmon `power1_input` (µW), the node without a `slowPPT` label. No discrete card means 0 W. |
| on-battery total | the discovered battery's `power_now` (µW), or `current_now × voltage_now` where absent |
| AC vs battery | the AC adapter's `online` flag |

### Windows 11 (MSYS2/Git Bash, Cygwin, WSL)

| Value | Source |
|-------|--------|
| CPU platform power | not available (no RAPL access); shown as 0 W on AC |
| dGPU power | `nvidia-smi -q -d POWER` ("Power Draw"), same as Linux |
| on-battery total | `root\WMI\BatteryStatus.DischargeRate` (mW) via `Get-CimInstance` |
| AC vs battery | `root\WMI\BatteryStatus.PowerOnline` |

### macOS

| Value | Source |
|-------|--------|
| SoC package power | `sudo powermetrics --samplers cpu_power` ("Combined Power", CPU+GPU+ANE); needs passwordless sudo, else unavailable |
| dGPU power | folded into the powermetrics figure, so counted as 0 W separately |
| on-battery total | `ioreg -rn AppleSmartBattery`: `\|Amperage\| × Voltage` (mA × mV = µW) |
| AC vs battery | `AppleSmartBattery` `ExternalConnected` |

Interval timing uses bash 5's `EPOCHREALTIME`, and the script forces `LC_ALL=C`
so a locale comma decimal separator does not corrupt the arithmetic.

## Why the Intel sensor is root-only

By default Linux only lets root read the CPU's built-in power sensor. The
README's setup steps add a udev rule that lets your normal user read it too.

> The sensor was locked down to block a hardware side-channel attack
> (CVE-2020-8694, "PLATYPUS"). The readings are just energy counters, so
> re-enabling them for yourself on a personal machine is low risk.

## AMD APUs (e.g. the Steam Deck)

On Ryzen APUs the RAPL counter is root-only, and it leaves out the iGPU, so the
udev rule doesn't help. powerwatch reads the `amdgpu` SoC power sensor instead
(`slowPPT`, the whole CPU and iGPU draw). It needs no setup: just run
`powerwatch` and the header will read `source: AMD APU SoC power`. On battery,
machines without `power_now` (including the Steam Deck) are read from
`current_now × voltage_now`, so the unplugged reading works too.

## Discrete GPUs and the iGPU

On AC, powerwatch adds a discrete GPU's power to the CPU-platform (RAPL) figure.
The key rule is that the GPU term only covers a card on its **own power rail**,
which RAPL does not already measure:

- **NVIDIA** discrete cards are read from `nvidia-smi`. In hybrid/Optimus laptops
  the card runtime-suspends when idle and reports no draw, counted as ~0 W.
- **AMD** discrete Radeons are read from the card's `amdgpu` hwmon
  `power1_input`. powerwatch picks the node that is *not* the APU package sensor
  (no `slowPPT` label), so on a Ryzen APU the iGPU is not mistaken for a dGPU.

An **Intel iGPU is deliberately not added.** Intel's RAPL `package`/`psys` domain
already includes the iGPU, so adding a separate iGPU reading would double-count
it. On an Intel laptop with no discrete card the GPU term is simply 0, and the
header reads `source: RAPL <domain> (iGPU included)`.

**Intel Arc discrete GPUs are not yet supported.** An Arc card and the Intel
iGPU both use the `i915`/`xe` driver and expose similar hwmon power nodes, so
reliably telling "this is the discrete card, add it" from "this is the iGPU,
already in RAPL" is not yet solved here, and getting it wrong would silently
double-count. If you have an Arc system to test on, that is the missing piece.

## Raspberry Pi

A Raspberry Pi (5 and up) has no RAPL or `amdgpu` sensor, so powerwatch reads
its on-board PMIC instead. `vcgencmd pmic_read_adc` lists every supply rail's
current and voltage. Powerwatch sums current×voltage across the rails to get the
board's total draw, which needs no root. Just run `powerwatch`; the header reads
`source: Raspberry Pi whole-board power` and each row is tagged `[PI]`.

This covers the whole board: the SoC, RAM, USB, and I/O rails, measured after
the 5 V input. Unlike the laptop AC estimate, it is not a compute-only
undercount. It still leaves out the input regulator's conversion loss, so a wall
meter on the USB-C supply reads a little higher.

**Pi 4 and earlier have no readable power sensor.** `pmic_read_adc` is a Pi 5
addition, and these boards have neither RAPL nor a battery, so there is nothing
for powerwatch to integrate. It still runs, but the header says no sensor was
found rather than pointing you at the Intel udev rule. To meter a Pi 4, measure
at the wall with a smart plug. The Intel `chmod` step in the README does not
apply: `/sys/devices/virtual/powercap/` exists only on Intel hardware, so that
command reports the path does not exist.

## macOS

macOS ships bash 3.2, but powerwatch needs bash 5.0+ (for `EPOCHREALTIME`;
`printf '%(...)T'` needs 4.2). Install a newer one with `brew install bash`; it
goes on PATH ahead of the system bash, so the `env bash` shebang picks it up.
powerwatch checks the version at startup and exits with a pointer if it runs
under 5.0.

On battery, powerwatch reads the battery itself — IOKit's `AppleSmartBattery`,
via `ioreg` — and multiplies `Amperage × Voltage` for whole-machine draw. This
is the macOS counterpart of Linux `power_now`: accurate, covers the whole
laptop, and needs no setup. (Amperage is a signed milliamp reading that IOKit
stores in an unsigned 64-bit field; powerwatch lets 64-bit signed bash
arithmetic wrap it back to the real negative, which floating-point awk could
not do precisely.) Each row is tagged `[BAT]`.

On AC there is no unprivileged instantaneous power sensor on Apple Silicon — the
same situation as Intel RAPL being root-only on Linux. powerwatch reads
CPU+GPU+ANE package power from `powermetrics`, which requires root, so it runs
the sampler under `sudo`. To use it, grant your user passwordless sudo for that
one command (see the [README](../README.md#macos)); powerwatch probes this once
at startup with `sudo -n` and, when it succeeds, the header reads `source: macOS
SoC power (powermetrics …)` and AC rows show real watts. Without the grant
powerwatch runs fine and stays battery-accurate, and the header says plug-in
power needs `powermetrics`. Like the AMD APU and Windows sensors, the value is
instantaneous watts integrated over the interval; the `powermetrics` spawn is
throttled to once per `POWERWATCH_MAC_POLL` seconds (default 5).

The SoC figure is a compute estimate in the same sense as the Linux AC path: it
covers the chip but not the display backlight, the adapter's conversion loss, or
USB peripherals, so it undercounts the wall meter. On battery the reading is the
genuine whole-machine draw.
