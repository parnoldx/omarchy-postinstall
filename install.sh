#!/usr/bin/env bash
# Apply Omarchy customizations on a fresh install.
#
# Usage:
#   ./install.sh
#   ./install.sh --yes
#   HA_URL=http://homeassistant.local:8123 HA_TOKEN=... ./install.sh --yes
#
# Copies this tree onto ~/.config and ~/.local, installs packages, then
# reloads Hyprland / the Omarchy shell. Existing files are backed up first.
#
# Included: Hyprland overlays, NeoQwertz keymap, bar plugins, Handy, Home
# Assistant menu + weather, screensaver/about branding, Plymouth/SDDM Om
# unlock logo, default agent pi, Grok usage + Thunderbird calendar
# automation, extra packages.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$ROOT/files"
STAMP="$(date +%s)"
YES=0
SKIP_PACKAGES=0
SKIP_AUR=0
SKIP_PLYMOUTH=0

REPO_PACKAGES=(thunderbird bitwarden bitwarden-cli git-lfs libqalculate)
AUR_PACKAGES=(handy-bin microsoft-edge-stable-bin visual-studio-code-bin)

usage() {
  cat <<'EOF'
Usage: install.sh [options]

  --yes              Do not ask for confirmation
  --skip-packages    Skip pacman and AUR installs
  --skip-aur         Install official packages only
  --skip-plymouth    Skip LUKS unlock / SDDM Om logo (needs sudo)
  -h, --help         Show this help

Home Assistant credentials (optional, prompted if missing):
  HA_URL       e.g. http://homeassistant.local:8123
  HA_TOKEN     long-lived access token

Weather (optional, prompted if missing):
  WEATHER_PLZ  German 5-digit postal code; resolved to a wetter.de location id
EOF
}

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
trim() { python3 -c 'import sys; print(sys.stdin.read().strip())'; }

run() {
  log "$*"
  "$@"
}

backup_path() {
  local dest="$1"
  [[ -e $dest || -L $dest ]] || return 0
  local bak="${dest}.bak.${STAMP}"
  mkdir -p "$(dirname "$bak")"
  cp -a "$dest" "$bak"
}

install_file() {
  local src="$1" dest="$2" mode="${3:-}"
  mkdir -p "$(dirname "$dest")"
  if [[ -e $dest || -L $dest ]] && cmp -s "$src" "$dest"; then
    return 0
  fi
  backup_path "$dest"
  cp -a "$src" "$dest"
  [[ -z $mode ]] || chmod "$mode" "$dest"
}

install_tree() {
  local src="$1" dest="$2"
  mkdir -p "$dest"
  local file rel
  while IFS= read -r -d '' file; do
    rel="${file#"$src"/}"
    install_file "$file" "$dest/$rel"
  done < <(find "$src" -type f -print0)
}

confirm() {
  (( YES )) && return 0
  [[ -t 0 ]] || die "refusing to run without a TTY; pass --yes"
  printf '\nProceed with the Omarchy post-install? [y/N] '
  local answer
  read -r answer
  [[ $answer == [yY] || $answer == yes ]]
}

ask() {
  local prompt="$1" default="${2:-}"
  local value
  if [[ -n $default ]]; then
    printf '%s [%s]: ' "$prompt" "$default"
  else
    printf '%s: ' "$prompt"
  fi
  read -r value
  printf '%s' "${value:-$default}"
}

ask_secret() {
  local prompt="$1"
  local value
  printf '%s: ' "$prompt"
  read -r -s value
  printf '\n' >&2
  printf '%s' "$value"
}

while (($#)); do
  case "$1" in
    --yes) YES=1 ;;
    --skip-packages) SKIP_PACKAGES=1 ;;
    --skip-aur) SKIP_AUR=1 ;;
    --skip-plymouth) SKIP_PLYMOUTH=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
  shift
done

[[ -d $FILES ]] || die "missing $FILES (run this from the omarchy-setup tree)"
command -v omarchy >/dev/null || die "omarchy is not on PATH; this script is for an Omarchy install"

cat <<EOF
This will customize the current Omarchy user ($USER) to match the existing
desktop:

  Hyprland    scale 1.25, gaps 2/4, rounding 4, NeoQwertz keymap,
              Thunderbird/Herdr overlays, Handy, Super+J layout toggle
  Bar         transparent; pa.menu / pa.clock / pa.weather / pa.tray / Handy
  HA          launcher Licht/Leselicht/Abdunkeln + room temp / dusk
  Weather     asks for a German PLZ, stores the wetter.de location URL locally;
              popup shows rain radar only while rain is falling or forecast today
  Branding    screensaver + about
  Plymouth    black/white Om on LUKS unlock and SDDM (sudo, initramfs rebuild)
  Agent       pi (mise global, no agent launch)
  Automation  Grok usage collector + Thunderbird calendar sync
  Packages    ${REPO_PACKAGES[*]}
              AUR: ${AUR_PACKAGES[*]}

Existing files are copied to *.bak.$STAMP before overwrite.
EOF

confirm || exit 1

# --- packages ----------------------------------------------------------------

if (( SKIP_PACKAGES == 0 )); then
  log "Installing official packages"
  run omarchy pkg add "${REPO_PACKAGES[@]}"

  if (( SKIP_AUR == 0 )); then
    if omarchy pkg aur accessible; then
      log "Installing AUR packages"
      run omarchy pkg aur add "${AUR_PACKAGES[@]}"
    else
      warn "AUR is not reachable; skipped ${AUR_PACKAGES[*]}"
      warn "Re-run later: omarchy pkg aur add ${AUR_PACKAGES[*]}"
    fi
  fi
else
  log "Skipping package installs"
fi

# --- hyprland ----------------------------------------------------------------

log "Installing Hyprland overlays"
for f in bindings.lua autostart.lua input.lua looknfeel.lua monitors.lua; do
  install_file "$FILES/hypr/$f" "$HOME/.config/hypr/$f"
done

log "Building NeoQwertz keymap (NumLock does not lock layer 4)"
install_file "$FILES/xkb/build-neoqwertz.sh" "$HOME/.config/xkb/build-neoqwertz.sh" 755
mkdir -p "$HOME/.config/xkb/keymap"
if command -v xkbcli >/dev/null && command -v python3 >/dev/null; then
  run "$HOME/.config/xkb/build-neoqwertz.sh" "$HOME/.config/xkb/keymap/neoqwertz.xkb"
else
  warn "xkbcli or python3 missing; keymap not compiled. Run ~/.config/xkb/build-neoqwertz.sh later."
fi

# --- bar / plugins / menu / branding -----------------------------------------

log "Installing shell plugins and bar module"
install_tree "$FILES/omarchy/plugins" "$HOME/.config/omarchy/plugins"
install_tree "$FILES/omarchy/bar" "$HOME/.config/omarchy/bar"
chmod 755 \
  "$HOME/.config/omarchy/plugins/pa.clock/sync-thunderbird-calendar" \
  "$HOME/.config/omarchy/plugins/pa.clock/focus-thunderbird-calendar" \
  "$HOME/.config/omarchy/plugins/pa.weather/ha-room-temp"

if command -v omarchy-shell >/dev/null; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

log "Installing shell.json, menu, and branding"
install_file "$FILES/omarchy/shell.json" "$HOME/.config/omarchy/shell.json"
install_file "$FILES/omarchy/extensions/omarchy-menu.jsonc" \
  "$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
install_file "$FILES/omarchy/branding/screensaver.txt" \
  "$HOME/.config/omarchy/branding/screensaver.txt"
install_file "$FILES/omarchy/branding/about.txt" \
  "$HOME/.config/omarchy/branding/about.txt"

log "Installing Plymouth Om unlock assets"
install_tree "$FILES/omarchy/plymouth" "$HOME/.config/omarchy/plymouth"
chmod 755 "$HOME/.config/omarchy/plymouth/apply-om-unlock.sh"

if (( SKIP_PLYMOUTH == 0 )); then
  log "Applying Plymouth/SDDM Om logo (sudo; rebuilds initramfs)"
  if omarchy plymouth set '#000000' '#ffffff' "$HOME/.config/omarchy/plymouth/om-unlock.png"; then
    log "Unlock screen updated; it shows on the next reboot"
  else
    warn "Plymouth apply failed. Re-run: $HOME/.config/omarchy/plymouth/apply-om-unlock.sh"
  fi
else
  log "Skipping Plymouth apply; assets are in ~/.config/omarchy/plymouth/"
fi

# --- local bins --------------------------------------------------------------

log "Installing helper scripts"
mkdir -p "$HOME/.local/bin"
install_file "$FILES/bin/ha-licht" "$HOME/.local/bin/ha-licht" 755
install_file "$FILES/bin/omarchy-agent-usage-grok" "$HOME/.local/bin/omarchy-agent-usage-grok" 755
install_file "$FILES/bin/wetter-plz-lookup" "$HOME/.local/bin/wetter-plz-lookup" 755

# --- home assistant ----------------------------------------------------------

log "Home Assistant credentials"
ha_dir="$HOME/.config/homeassistant"
ha_url_file="$ha_dir/url"
ha_token_file="$ha_dir/token"
ha_url="${HA_URL:-}"
ha_token="${HA_TOKEN:-}"

if [[ -z $ha_url && -r $ha_url_file ]]; then
  ha_url="$(<"$ha_url_file")"
fi
if [[ -z $ha_token && -r $ha_token_file ]]; then
  ha_token="$(<"$ha_token_file")"
fi

if [[ -z $ha_url || -z $ha_token ]]; then
  if [[ -t 0 ]]; then
    printf '\nHome Assistant (used by the weather pill and Super-menu HA entries).\n'
    printf 'Create a token in HA: Profile → Security → Long-lived access tokens.\n'
    ha_url="$(ask "HA URL" "${ha_url:-http://homeassistant.local:8123}")"
    ha_token="$(ask_secret "HA long-lived token")"
  else
    warn "No HA credentials (set HA_URL and HA_TOKEN, or re-run interactively)"
  fi
fi

if [[ -n $ha_url && -n $ha_token ]]; then
  mkdir -p "$ha_dir"
  trim <<<"$ha_url" >"$ha_url_file"
  trim <<<"$ha_token" >"$ha_token_file"
  chmod 600 "$ha_url_file" "$ha_token_file"
  log "Wrote $ha_url_file"
else
  warn "Skipped HA credentials; pa.weather room/dusk and ha-licht will not work yet"
fi

# --- weather PLZ -------------------------------------------------------------

log "Weather location (from German PLZ)"
weather_plz="${WEATHER_PLZ:-}"
if [[ -z $weather_plz ]]; then
  if [[ -t 0 ]]; then
    printf '\nGerman PLZ for the weather pill (looked up on wetter.de, then stored as a location URL).\n'
    weather_plz="$(ask "Postleitzahl")"
  else
    warn "No WEATHER_PLZ; right-click weather will stay unset"
  fi
fi
weather_plz="$(trim <<<"$weather_plz")"
if [[ $weather_plz =~ ^[0-9]{5}$ ]]; then
  lookup="$HOME/.local/bin/wetter-plz-lookup"
  [[ -x $lookup ]] || lookup="$FILES/bin/wetter-plz-lookup"
  if weather_hit="$("$lookup" "$weather_plz")"; then
    weather_url="${weather_hit%%$'\t'*}"
    weather_title="${weather_hit#*$'\t'}"
    log "wetter.de: $weather_title -> $weather_url"
    python3 - "$HOME/.config/omarchy/shell.json" "$weather_url" <<'PY'
import json, sys
path, url = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
center = data.get("bar", {}).get("layout", {}).get("center", [])
for widget in center:
    if widget.get("id") == "pa.weather":
        widget.pop("plz", None)
        widget["wetterUrl"] = url
        break
else:
    sys.exit("pa.weather widget not found in shell.json")
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
    if command -v omarchy >/dev/null; then
      omarchy bar set pa.weather wetterUrl "$weather_url" >/dev/null 2>&1 || true
    fi
  else
    warn "Could not resolve PLZ $weather_plz on wetter.de"
  fi
else
  if [[ -n $weather_plz ]]; then
    warn "Ignoring PLZ '$weather_plz' (need exactly 5 digits)"
  else
    warn "Skipped weather location; later: wetter-plz-lookup 12345 && omarchy bar set pa.weather wetterUrl <url>"
  fi
fi

# --- automation --------------------------------------------------------------

log "Installing hooks and user systemd units"
run omarchy hook install post-boot "$FILES/omarchy/hooks/post-boot.d/grok-usage.hook"
run omarchy hook install post-boot "$FILES/omarchy/hooks/post-boot.d/thunderbird-calendar.hook"

install_tree "$FILES/systemd/user" "$HOME/.config/systemd/user"
if command -v systemctl >/dev/null; then
  systemctl --user daemon-reload
  for unit in omarchy-agent-usage-grok.timer omarchy-agent-usage-grok.path omarchy-thunderbird-calendar-sync.timer; do
    systemctl --user enable --now "$unit" || warn "could not enable $unit"
  done
  systemctl --user start omarchy-agent-usage-grok.service ||
    warn "Grok usage collector failed (run grok login later)"
  systemctl --user start omarchy-thunderbird-calendar-sync.service ||
    warn "Thunderbird calendar sync failed (needs a configured Thunderbird profile)"
fi

# --- default agent -----------------------------------------------------------

log "Setting default agent to pi"
mkdir -p "$HOME/.config/omarchy/defaults"
printf 'pi\n' >"$HOME/.config/omarchy/defaults/agent"
if command -v mise >/dev/null; then
  if ! mise where pi >/dev/null 2>&1; then
    run mise use -g pi || warn "Could not install pi with mise; agent file is still set"
  else
    log "pi already installed via mise"
  fi
else
  warn "mise not found; wrote default agent file only"
fi

# --- apply -------------------------------------------------------------------

if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  log "Reloading Hyprland"
  hyprctl reload >/dev/null
  errors="$(hyprctl configerrors 2>/dev/null || true)"
  if [[ -n ${errors//[[:space:]]/} && $errors != "no errors" ]]; then
    warn "hyprctl configerrors:"
    printf '%s\n' "$errors" >&2
  fi
else
  warn "Hyprland not running; overlays apply on next login"
fi

if command -v omarchy-shell >/dev/null; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
fi

log "Done. Open a new session or wait for the shell to hot-reload."
log "Handy dictation: Ctrl+F1. Thunderbird overlay: Super+Shift+E. Herdr: Super+Shift+A."
log "Grok usage in the agents panel needs: grok login"
