#!/usr/bin/env bash
# install.sh - install or update powerwatch without cloning the repo:
#
#   curl -fsSL https://raw.githubusercontent.com/mjfwebb/powerwatch/main/install.sh | bash
#
# Re-running the same line updates the installed copy in place. On Intel it
# can also install the udev rule that makes the CPU power sensor readable
# (uses sudo; see README.md):
#
#   curl -fsSL https://raw.githubusercontent.com/mjfwebb/powerwatch/main/install.sh | bash -s -- --with-udev
#
# Overrides: POWERWATCH_BIN_DIR for the install dir (default ~/.local/bin),
# POWERWATCH_RAW_URL to fetch from a fork or branch.
set -euo pipefail

raw_url=${POWERWATCH_RAW_URL:-https://raw.githubusercontent.com/mjfwebb/powerwatch/main}
bin_dir=${POWERWATCH_BIN_DIR:-$HOME/.local/bin}
rules=99-powercap-readable.rules

with_udev=0
for arg in "$@"; do
  case $arg in
    --with-udev) with_udev=1 ;;
    *) echo "install.sh: unknown option: $arg (only --with-udev is supported)" >&2; exit 2 ;;
  esac
done

command -v curl >/dev/null || { echo "install.sh: curl is required" >&2; exit 1; }

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# Fetch to a temp file and move into place only after the download succeeded
# and looks sane, so a failed fetch never clobbers a working install.
curl -fsSL "$raw_url/powerwatch" -o "$tmp_dir/powerwatch"
head -n1 "$tmp_dir/powerwatch" | grep -q '^#!' ||
  { echo "install.sh: $raw_url/powerwatch does not look like a script, not installing" >&2; exit 1; }

# The script carries its version as a VERSION= line; read it from a file
# rather than executing it. Empty for pre-versioning installs.
script_version() { sed -n 's/^VERSION=//p' "$1" 2>/dev/null | head -n1; }

target=$bin_dir/powerwatch
new_ver=$(script_version "$tmp_dir/powerwatch")
if [[ -e $target ]] && cmp -s "$tmp_dir/powerwatch" "$target"; then
  echo "powerwatch already up to date: $target${new_ver:+ ($new_ver)}"
else
  verb=installed; old_ver=""
  [[ -e $target ]] && { verb=updated; old_ver=$(script_version "$target"); }
  install -Dm755 "$tmp_dir/powerwatch" "$target"
  case $verb in
    updated)   echo "updated $target (${old_ver:-unversioned} -> ${new_ver:-unversioned})";;
    installed) echo "installed $target${new_ver:+ ($new_ver)}";;
  esac
fi

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "note: $bin_dir is not on your PATH" >&2 ;;
esac

# --- Intel udev rule (one-time; the sensor is root-only by default) ----------
rapl_unreadable=0
for d in /sys/class/powercap/intel-rapl:[0-9]*; do
  [[ -e $d/energy_uj && ! -r $d/energy_uj ]] && rapl_unreadable=1
done

if (( with_udev )); then
  curl -fsSL "$raw_url/$rules" -o "$tmp_dir/$rules"
  sudo cp "$tmp_dir/$rules" /etc/udev/rules.d/
  sudo udevadm control --reload
  sudo udevadm trigger --subsystem-match=powercap
  sudo chmod -R a+r /sys/devices/virtual/powercap/   # apply now, without a reboot
  echo "installed /etc/udev/rules.d/$rules"
elif (( rapl_unreadable )); then
  cat >&2 <<EOF
note: the Intel CPU power sensor is not readable by your user, so on AC
powerwatch will only see the GPU. One-time fix (re-run with --with-udev,
or see README.md):

  curl -fsSL $raw_url/install.sh | bash -s -- --with-udev
EOF
fi
