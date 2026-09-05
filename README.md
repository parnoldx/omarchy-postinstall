# omarchy-postinstall

Personal Omarchy post-install. Run it on a fresh box to apply Hyprland overlays, bar plugins (including `pa.agents`, a stacked-sections fork of the stock agents panel), mailbox (CLI, socket-activated daemon, `mailbox.clock` calendar widget, `mailbox.email` unread/screener widget), Handy (NVIDIA-only Vulkan + a CUDA keepalive so dictation does not stall ~60s after the laptop dGPU hits D3cold), Chromium/Edge video decode on the Intel iGPU (Omarchy's NVIDIA VAAPI freezes HTML5 players on this hybrid laptop), Home Assistant helpers, branding, Plymouth/SDDM Om unlock, default agent `pi`, VS Code as the editor (Omarchy launcher and Files), a Super+Ctrl+F fzf+yazi file finder, a `kill-tui` process killer, seven community bar plugins (Quick Look, Jot, Workspace Layout, Time Machine, Pocket, Omatree, YouTube Music — installed via `omarchy plugin add`, stock `omarchy.menu` disabled in favor of `pa.menu`), and extra packages.

Passwords run through `rbw` (unofficial Bitwarden client): Super+Shift+B (also the launcher Bitwarden entry and menu 󰢁 Passwörter) opens a fuzzy-finder TUI that copies password, username or TOTP. Bare `bw` opens the same picker; `bw <args>` forwards to rbw — the official bitwarden-cli stays installed but is shadowed on PATH. `vault-bridge` sits in as rbw's pinentry and as the Chrome native-messaging host, so that one master-password prompt also unlocks the Bitwarden extension (it speaks the extension's biometric protocol). After install, turn on **Unlock with biometrics** in the extension Settings — do not enable the official Bitwarden desktop "Allow browser integration", which would overwrite the native-host manifest.
Home Assistant credentials, the Shelly door-opener auth key, and a German PLZ are prompted (or passed as env vars) and written only on the target machine — nothing location-specific is stored in this repo. The weather popup shows a rain radar only while rain is falling here or forecast today. Night light turns off at sunrise and on at sunset for that same weather location. The bar indicator is refreshed at those times and after resume, because Omarchy only re-reads hyprsunset when told.

## New Omarchy box

In a terminal (needs `sudo` for packages and Plymouth):

```bash
git clone https://github.com/parnoldx/omarchy-postinstall.git ~/work/omarchy-postinstall
~/work/omarchy-postinstall/install.sh
```

Non-interactive, with secrets already in the environment:

```bash
git clone https://github.com/parnoldx/omarchy-postinstall.git ~/work/omarchy-postinstall
HA_URL=http://homeassistant.local:8123 HA_TOKEN=... SHELLY_AUTH_KEY=... WEATHER_PLZ=12345 \
  ~/work/omarchy-postinstall/install.sh --yes
```

`--skip-packages` skips pacman/AUR. `--skip-aur` installs official repos only. `--skip-plymouth` copies the Om logo but does not rebuild the initramfs.

mailbox is cloned from [parnoldx/mailbox-cli](https://github.com/parnoldx/mailbox-cli) into `~/.local/src/mailbox-cli` (override with `MAILBOX_SRC`) and installed with `make install` + `make install-plugins`. The daemon is socket-activated (`mailbox.socket`); the first bar widget to connect starts it. Interactive install runs `mailbox setup` if `~/.config/mailbox/config.toml` is missing. `--yes` skips that — run `mailbox setup` afterwards.

The clock popup (`mailbox.clock`) reads calendars from the daemon. Right-clicking a day swipes to an entry pane: type the event the way you would say it, in English or German (`lunch with Ana 12:30 till 14:00`, `mittag morgen 12:30 bis 14 Uhr`, `/work`, `-a40m`, `-r1w`, `!!`), and the phrase paints itself as it is parsed — title, date, time, duration, the calendar in its own colour. Super+Ctrl+D toggles the calendar. The email widget (`mailbox.email`) shows in the bar only when there is unread mail or a screener decision waiting; Super+Shift+Alt+E toggles the panel. Opening a message from that panel shells out to `mailbox-gui` if you have built it (`make -C ~/.local/src/mailbox-cli install-gui`); the CLI, daemon, and widgets do not need it.

After install, run `mailbox setup` if you skipped it, and `grok login` (agents usage). Right-click on the weather pill opens the wetter.de forecast resolved from `WEATHER_PLZ`. The weather popup adds a RainViewer map when precipitation is current or forecast today.

`omarchy default editor` only covers Omarchy launchers (`$EDITOR`, keybindings). Files / `xdg-open` still follow MIME, which Omarchy ships as Neovim. The post-install sets both: `omarchy default editor code` and `~/.config/mimeapps.list` for text/source types. Re-apply MIME later with `set-code-mime-defaults`.

Super+Ctrl+F fuzzy-finds files with fzf + yazi in a floating terminal (Super+Ctrl+Shift+F browses, Super+Ctrl+Alt+F searches by type); Super+Shift+F/Super+Alt+Shift+F open `flea`, a graphical file manager. `kill-tui` (Super menu → Kill Process) fuzzy-finds a running process and sends SIGTERM/SIGKILL. Super+N toggles `Jot`, a scratch-note overlay.
