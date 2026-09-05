#!/usr/bin/env bash
# Apply Omarchy customizations on a fresh install.
#
# Usage:
#   ./install.sh
#   ./install.sh --yes
#   HA_URL=http://homeassistant.local:8123 HA_TOKEN=... SHELLY_AUTH_KEY=... ./install.sh --yes
#
# Copies this tree onto ~/.config and ~/.local, installs packages, then
# reloads Hyprland / the Omarchy shell. Existing files are backed up first.
#
# Included: Hyprland overlays, NeoQwertz keymap, bar plugins, Handy (NVIDIA
# ICD + GPU keepalive so dictation does not stall ~60s after RTD3), Chromium/
# Edge VAAPI on the Intel iGPU (hybrid NVIDIA decode freezes HTML5 video),
# Home Assistant menu + weather, screensaver/about branding, Plymouth/SDDM Om
# unlock logo, default agent pi, VS Code as editor (Omarchy + Files MIME),
# Grok usage + mailbox (CLI, daemon, clock + email bar widgets) +
# sunrise/sunset nightlight automation, extra packages.
#
# CAD Assistant is made usable here twice over: its bundled 2021 Qt5 breaks
# under Wayland (QT_QPA_PLATFORM=xcb wrapper), and the AppImage's desktop
# file ships Exec=CADAssistant, which only resolves inside the container.
#
# mailbox is cloned from github.com/parnoldx/mailbox-cli (override with
# MAILBOX_SRC) and installed to ~/.local/bin. The daemon is socket-activated.

set -euo pipefail

# Root steps (/usr/local/bin wrapper, desktop file fix, Plymouth/SDDM) all use
# plain sudo, so one upfront `sudo -v` covers them. A background loop refreshes
# the timestamp while the script runs; killed on exit.
SUDO_KEEPALIVE_PID=""
cleanup() {
  [[ -n $SUDO_KEEPALIVE_PID ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
}
trap cleanup EXIT

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$ROOT/files"
STAMP="$(date +%s)"
YES=0
SKIP_PACKAGES=0
SKIP_AUR=0
SKIP_PLYMOUTH=0

# go is for building mailbox from source.
REPO_PACKAGES=(thunderbird bitwarden bitwarden-cli git-lfs libqalculate go rbw)
AUR_PACKAGES=(cadassistant-appimage handy-bin microsoft-edge-stable-bin visual-studio-code-bin)

usage() {
  cat <<'EOF'
Usage: install.sh [options]

  --yes              Do not ask for confirmation
  --skip-packages    Skip pacman and AUR installs
  --skip-aur         Install official packages only
  --skip-plymouth    Skip LUKS unlock / SDDM Om logo
  -h, --help         Show this help

Home Assistant credentials (optional, prompted if missing):
  HA_URL       e.g. http://homeassistant.local:8123
  HA_TOKEN     long-lived access token

Weather (optional, prompted if missing):
  WEATHER_PLZ  German 5-digit postal code; resolved to a wetter.de location id

Bitwarden vault (optional, prompted if missing):
  RBW_EMAIL    Bitwarden account email for the rbw password picker
  RBW_SERVER   self-hosted/Vaultwarden URL; empty for bitwarden.com

Shelly door opener (optional, prompted if missing):
  SHELLY_AUTH_KEY  cloud auth_key for ha-tuer

Mailbox (optional):
  MAILBOX_SRC   existing mailbox-cli checkout; cloned to
                ~/.local/src/mailbox-cli if unset
  MAILBOX_REPO  git URL (default https://github.com/parnoldx/mailbox-cli.git)
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

log "Asking for sudo once (wrapper install, desktop file fix, Plymouth); no further prompts"
sudo -v || die "sudo privileges are required"
(
  while :; do
    sleep 60
    sudo -v || exit
  done
) &
SUDO_KEEPALIVE_PID=$!

cat <<EOF
This will customize the current Omarchy user ($USER) to match the existing
desktop:

  Hyprland    scale 1.25, gaps 2/4, rounding 4, NeoQwertz keymap,
              Thunderbird/Herdr overlays, Handy (NVIDIA ICD + dGPU keepalive),
              Super+J layout toggle, Chromium/Edge VAAPI on Intel iGPU
  Bar         transparent; pa.menu / mailbox.clock / mailbox.email /
              pa.weather / pa.tray / pa.agents / Handy
  Mailbox     CLI + socket-activated daemon; bar clock (calendar popup,
              natural-language event/task add) and email widget (unread +
              screener); Super+Shift+Alt+E toggles the mail panel
  Clock       month grid from the mailbox daemon; right-click a day for the
              entry pane — type the event in English or German
              ("lunch with Ana 12:30 till 14:00"); plays one nudge sound
              when a joinable meeting runs a minute without anyone clicking Join
  HA          launcher Licht/Leselicht/Abdunkeln + room temp / dusk
  Weather     asks for a German PLZ, stores the wetter.de URL and coordinates;
              popup shows rain radar only while rain is falling or forecast today
  Branding    screensaver + about
  Plymouth    black/white Om on LUKS unlock and SDDM (sudo, initramfs rebuild)
  Agent       pi (mise global, no agent launch)
  Editor      VS Code (omarchy-launch-editor + Files / xdg-open)
  Nightlight  off at sunrise, on at sunset (from the weather location)
  Automation  Grok usage collector + mailbox daemon +
              sunrise/sunset nightlight
  Vault       rbw password TUI (floating terminal): fuzzy-find an entry,
              copy password / username / TOTP; bare `bw` opens it
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

    # CAD Assistant's bundled Qt5 crashes under Wayland and its desktop file
    # points at Exec=CADAssistant, which only exists inside the AppImage
    # sandbox. The wrapper in /usr/local/bin fixes terminal use (it shadows
    # /usr/bin without touching pacman's symlink); the Exec rewrite makes the
    # launcher entry work with the same env vars.
    cad_desktop=/usr/share/applications/cadassistant.desktop
    if pacman -Q cadassistant-appimage &>/dev/null; then
      log "Installing CAD Assistant xcb wrapper"
      run sudo install -Dm755 "$FILES/bin/cadassistant" /usr/local/bin/cadassistant
      if ! grep -q 'QT_QPA_PLATFORM=xcb' "$cad_desktop" 2>/dev/null; then
        log "Fixing CAD Assistant desktop file"
        run sudo sed -i \
          's|^Exec=.*|Exec=env DESKTOPINTEGRATION=false QT_QPA_PLATFORM=xcb /usr/bin/cadassistant %U|' \
          "$cad_desktop"
      fi
    fi
  fi
else
  log "Skipping package installs"
fi

# --- hyprland ----------------------------------------------------------------

log "Installing Hyprland overlays"
for f in hyprland.lua bindings.lua autostart.lua input.lua looknfeel.lua monitors.lua; do
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
chmod 755 "$HOME/.config/omarchy/plugins/pa.weather/ha-room-temp"

# pa.clock was the Thunderbird-backed calendar widget. mailbox.clock replaces it.
if [[ -d $HOME/.config/omarchy/plugins/pa.clock ]]; then
  log "Removing leftover pa.clock (replaced by mailbox.clock)"
  rm -rf "$HOME/.config/omarchy/plugins/pa.clock"
fi

log "Installing mailbox CLI, clock widget, and email widget"
if [[ -z ${MAILBOX_SRC:-} ]]; then
  for cand in \
    "$HOME/.local/src/mailbox-cli" \
    "$HOME/Work/mailbox-cli" \
    "$HOME/Work/tries/2026-08-29-mailbox-cli"; do
    if [[ -d $cand/.git && -f $cand/Makefile ]]; then
      MAILBOX_SRC=$cand
      break
    fi
  done
fi
mailbox_src="${MAILBOX_SRC:-$HOME/.local/src/mailbox-cli}"
mailbox_repo="${MAILBOX_REPO:-https://github.com/parnoldx/mailbox-cli.git}"
log "mailbox-cli source: $mailbox_src"
if [[ ! -d $mailbox_src/.git ]]; then
  if [[ -e $mailbox_src ]]; then
    die "MAILBOX_SRC $mailbox_src exists and is not a git checkout"
  fi
  command -v git >/dev/null || die "git is not on PATH; cannot clone mailbox-cli"
  mkdir -p "$(dirname "$mailbox_src")"
  run git clone --depth 1 "$mailbox_repo" "$mailbox_src"
fi
command -v go >/dev/null || die "go is not on PATH; mailbox CLI cannot be built (install go, or drop --skip-packages)"
command -v make >/dev/null || die "make is not on PATH; mailbox CLI cannot be built"
run make -C "$mailbox_src" install
run make -C "$mailbox_src" install-plugins
mkdir -p "$HOME/.agents/skills" "$HOME/.claude/skills"
if ! make -C "$mailbox_src" skill; then
  warn "mailbox skill not installed; later: make -C $mailbox_src skill"
fi

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
install_file "$FILES/bin/ha-tuer" "$HOME/.local/bin/ha-tuer" 755
install_file "$FILES/bin/handy-toggle" "$HOME/.local/bin/handy-toggle" 755
install_file "$FILES/bin/handy-daemon" "$HOME/.local/bin/handy-daemon" 755
install_file "$FILES/bin/handy-gpu-keepalive" "$HOME/.local/bin/handy-gpu-keepalive" 755
install_file "$FILES/bin/handy-ensure-settings" "$HOME/.local/bin/handy-ensure-settings" 755
install_file "$FILES/bin/transcribe" "$HOME/.local/bin/transcribe" 755
install_file "$FILES/bin/omarchy-agent-usage-grok" "$HOME/.local/bin/omarchy-agent-usage-grok" 755
install_file "$FILES/bin/wetter-plz-lookup" "$HOME/.local/bin/wetter-plz-lookup" 755
install_file "$FILES/bin/hyprsunset-solar" "$HOME/.local/bin/hyprsunset-solar" 755
install_file "$FILES/bin/set-code-mime-defaults" "$HOME/.local/bin/set-code-mime-defaults" 755
install_file "$FILES/bin/rbw-tui" "$HOME/.local/bin/rbw-tui" 755
install_file "$FILES/bin/bw" "$HOME/.local/bin/bw" 755
install_file "$FILES/bin/vault-bridge" "$HOME/.local/bin/vault-bridge" 755

# Shadows /usr/share/applications/bitwarden.desktop so the launcher and
# search open the same rbw TUI as the Passwörter menu entry, not the
# Electron desktop app.
install_file "$FILES/applications/bitwarden.desktop" \
  "$HOME/.local/share/applications/bitwarden.desktop"
if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
fi

# --- bitwarden / rbw vault ---------------------------------------------------

# ~/.local/bin precedes /usr/bin on PATH, so the bw shim shadows the official
# bitwarden-cli: bare `bw` opens the rbw password TUI, `bw <args>` forwards to
# rbw. The official CLI stays installed for direct use via /usr/bin/bw.
log "Bitwarden vault (rbw)"
rbw_dir="$HOME/.config/rbw"
if [[ -f $rbw_dir/config.json ]]; then
  log "rbw config already present"
else
  rbw_email="${RBW_EMAIL:-}"
  rbw_server="${RBW_SERVER:-}"
  if [[ -z $rbw_email || -z $rbw_server ]] && [[ -t 0 ]]; then
    printf '\nBitwarden account for the rbw vault (fuzzy password picker in the menu).\n'
    printf 'Server is only needed for self-hosted/Vaultwarden instances; empty for bitwarden.com.\n'
    rbw_email="$(ask "Bitwarden email")"
    rbw_server="$(ask "Server URL (empty = bitwarden.com)")"
  fi
  if [[ -n $rbw_email ]]; then
    mkdir -p "$rbw_dir"
    if [[ -n $rbw_server ]]; then
      printf '{"email":"%s","sso_id":null,"base_url":"%s","identity_url":null,"ui_url":null,"notifications_url":null,"lock_timeout":3600,"sync_interval":3600,"pinentry":"pinentry","client_cert_path":null}\n' \
        "$rbw_email" "$rbw_server" >"$rbw_dir/config.json"
    else
      printf '{"email":"%s","sso_id":null,"base_url":null,"identity_url":null,"ui_url":null,"notifications_url":null,"lock_timeout":3600,"sync_interval":3600,"pinentry":"pinentry","client_cert_path":null}\n' \
        "$rbw_email" >"$rbw_dir/config.json"
    fi
    log "Wrote $rbw_dir/config.json"
    warn "One-time setup remains: rbw register (API token from Bitwarden web vault → Settings → Security → Keys), then rbw sync"
  else
    warn "No RBW_EMAIL; run 'rbw config' manually later"
  fi
fi

if [[ -x $HOME/.local/bin/vault-bridge ]]; then
  log "Installing vault-bridge (one pinentry unlocks rbw and the Bitwarden extension)"
  if command -v rbw >/dev/null; then
    "$HOME/.local/bin/vault-bridge" setup --quiet
    warn "Bitwarden extension: enable Unlock with biometrics (Settings → Account security). Super+Shift+B then unlocks rbw and the extension together. Do not enable Bitwarden desktop 'Allow browser integration'."
  else
    warn "rbw not on PATH; skip vault-bridge setup. Later: vault-bridge setup"
  fi
fi

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

# --- shelly door opener ------------------------------------------------------

log "Shelly door opener credentials"
shelly_dir="$HOME/.config/shelly"
shelly_auth_file="$shelly_dir/auth_key"
shelly_auth="${SHELLY_AUTH_KEY:-}"

if [[ -z $shelly_auth && -r $shelly_auth_file ]]; then
  shelly_auth="$(<"$shelly_auth_file")"
fi

if [[ -z $shelly_auth ]]; then
  if [[ -t 0 ]]; then
    printf '\nShelly Cloud auth_key (used by Super-menu HA → Tür öffnen).\n'
    shelly_auth="$(ask_secret "Shelly auth_key")"
  else
    warn "No Shelly credentials (set SHELLY_AUTH_KEY, or re-run interactively)"
  fi
fi

if [[ -n $shelly_auth ]]; then
  mkdir -p "$shelly_dir"
  trim <<<"$shelly_auth" >"$shelly_auth_file"
  chmod 600 "$shelly_auth_file"
  log "Wrote $shelly_auth_file"
else
  warn "Skipped Shelly credentials; ha-tuer will not work yet"
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
    IFS=$'\t' read -r weather_url weather_title weather_lat weather_lon <<<"$weather_hit"
    log "wetter.de: $weather_title -> $weather_url"
    if [[ -n ${weather_lat:-} && -n ${weather_lon:-} ]]; then
      if command -v omarchy-weather-location >/dev/null; then
        omarchy-weather-location --set "$weather_title" "${weather_lat},${weather_lon}"
        log "Weather coordinates: $weather_lat,$weather_lon"
      else
        warn "omarchy-weather-location missing; nightlight solar times need it"
      fi
    fi
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

# --- mailbox setup -----------------------------------------------------------

log "Mailbox account"
mailbox_bin="$HOME/.local/bin/mailbox"
mailbox_config="$HOME/.config/mailbox/config.toml"
if [[ -f $mailbox_config ]]; then
  log "mailbox config already present"
elif [[ -t 0 ]] && (( YES == 0 )) && [[ -x $mailbox_bin ]]; then
  printf '\nmailbox setup (IMAP + CalDAV + daemon). This is the wizard that writes\n'
  printf '~/.config/mailbox/config.toml and enables mailbox.socket.\n'
  "$mailbox_bin" setup || warn "mailbox setup failed; run it later"
else
  warn "No mailbox config; run 'mailbox setup' later (writes config + enables the daemon)"
fi

# --- automation --------------------------------------------------------------

log "Installing hooks and user systemd units"
run omarchy hook install post-boot "$FILES/omarchy/hooks/post-boot.d/grok-usage.hook"
run omarchy hook install post-boot "$FILES/omarchy/hooks/post-boot.d/hyprsunset-solar.hook"
rm -f "$HOME/.config/omarchy/hooks/post-boot.d/thunderbird-calendar.hook"

install_tree "$FILES/systemd/user" "$HOME/.config/systemd/user"
if command -v systemctl >/dev/null; then
  systemctl --user disable --now omarchy-thunderbird-calendar-sync.timer 2>/dev/null || true
  systemctl --user disable --now omarchy-thunderbird-calendar-sync.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/omarchy-thunderbird-calendar-sync.timer" \
    "$HOME/.config/systemd/user/omarchy-thunderbird-calendar-sync.service"
  systemctl --user daemon-reload
  for unit in omarchy-agent-usage-grok.timer omarchy-agent-usage-grok.path handy-gpu-keepalive.service hyprsunset-solar.timer hyprsunset-solar-resume.service; do
    systemctl --user enable --now "$unit" || warn "could not enable $unit"
  done
  if [[ -f $mailbox_config ]]; then
    systemctl --user enable --now mailbox.socket || warn "could not enable mailbox.socket"
  else
    warn "mailbox.socket not enabled yet; mailbox setup does that"
  fi
  if [[ -x $HOME/.local/bin/handy-ensure-settings ]]; then
    "$HOME/.local/bin/handy-ensure-settings" || warn "could not set Handy never-unload"
  fi
  systemctl --user start omarchy-agent-usage-grok.service ||
    warn "Grok usage collector failed (run grok login later)"
  systemctl --user start hyprsunset-solar.service ||
    warn "Nightlight solar times failed (needs weather coordinates)"
fi

# --- default editor ----------------------------------------------------------

log "Setting default editor to VS Code"
mkdir -p "$HOME/.local/state/omarchy/defaults"
printf 'code\n' >"$HOME/.local/state/omarchy/defaults/editor"
if command -v omarchy >/dev/null; then
  omarchy default editor code >/dev/null || warn "Could not run omarchy default editor code"
fi
if [[ -x $HOME/.local/bin/set-code-mime-defaults ]]; then
  "$HOME/.local/bin/set-code-mime-defaults" || warn "Could not set Files MIME defaults to VS Code"
else
  warn "set-code-mime-defaults missing; Files may still open nvim"
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
log "Handy dictation: Ctrl+F1 (NVIDIA ICD + dGPU keepalive; model never unloads)."
log "File transcription: transcribe file.mp4 [-o out.txt]."
log "Thunderbird overlay: Super+Shift+E. Herdr: Super+Shift+A."
log "Mailbox panel: Super+Shift+Alt+E. Calendar: Super+Ctrl+D."
log "Grok usage in the agents panel needs: grok login"
if [[ ! -f $HOME/.config/mailbox/config.toml ]]; then
  log "Mailbox still needs: mailbox setup"
fi
