# What powerwatch measures

How each power source is read, what it covers, and what it misses. Part of the
[powerwatch README](../README.md).

## Sources

| Source | What it covers | Notes |
|--------|----------------|-------|
| Intel RAPL `psys` (`/sys/class/powercap/intel-rapl:*`) | CPU package, iGPU, DRAM, VRMs | Read as a monotonic µJ energy counter, so interval energy is exact. Root-only by default (see the udev setup in the README). |
| NVIDIA dGPU (`nvidia-smi`) | The discrete GPU | On its own rail, not in RAPL. It runtime-suspends in hybrid/Optimus mode and reports no data, which powerwatch counts as ~0 W. |
| AMD APU `slowPPT` (`amdgpu` hwmon `power1_input`) | The SoC package (CPU + iGPU) | Fallback used on Ryzen APUs (e.g. the Steam Deck) where RAPL is root-only and excludes the iGPU. Read without root as instantaneous watts and integrated over the interval. |
| Battery `power_now` | The whole laptop (CPU, GPU, screen, everything) | Only valid on battery. When unplugged it supersedes the estimate above and is genuinely accurate. Machines without `power_now` (e.g. the Steam Deck) are read from `current_now × voltage_now` instead. |

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
| AMD APU power | `amdgpu` hwmon `power1_input` (label `slowPPT`), when the RAPL counter is unreadable |
| dGPU power | `nvidia-smi -q -d POWER` ("Power Draw"); absent means 0 W (suspended) |
| on-battery total | the discovered battery's `power_now` (µW), or `current_now × voltage_now` where absent |
| AC vs battery | the AC adapter's `online` flag |

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
