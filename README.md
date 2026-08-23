# omarchy-postinstall

Personal Omarchy post-install. Run it on a fresh box to apply Hyprland overlays, bar plugins (including `pa.agents`, a stacked-sections fork of the stock agents panel), Handy (NVIDIA-only Vulkan + a CUDA keepalive so dictation does not stall ~60s after the laptop dGPU hits D3cold), Home Assistant helpers, branding, Plymouth/SDDM Om unlock, default agent `pi`, VS Code as the editor (Omarchy launcher and Files), and extra packages.

Passwords run through `rbw` (unofficial Bitwarden client): unlock once per session, then a fuzzy-finder TUI in a floating terminal copies password, username or TOTP code (`rbw-tui`, menu entry 󰢁 Passwörter). Bare `bw` opens that picker; `bw <args>` forwards to rbw — the official bitwarden-cli stays installed but is shadowed on PATH.
Home Assistant credentials, the Shelly door-opener auth key, and a German PLZ are prompted (or passed as env vars) and written only on the target machine — nothing location-specific is stored in this repo. The weather popup shows a rain radar only while rain is falling here or forecast today.

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

The clock popup dots each day in the colours Thunderbird gives those calendars, and right-clicking a day swipes to an entry pane: type the event the way you would say it, in English or German (`lunch with Ana 12:30 till 14:00`, `mittag morgen 12:30 bis 14 Uhr`, `/work`, `-a40m`, `-r1w`, `!!`), and the phrase paints itself as it is parsed — title, date, time, duration, the calendar in its own colour. The pills below open the parts the phrase did not mention, EVENT/TASK switches what gets written, and Create files it into Thunderbird without the window taking focus. Pasting a meeting link anywhere in the phrase lifts it out of the title and onto the event, so the bar's Join button lights up for events you made yourself. All of it goes through a small Thunderbird add-on (`files/omarchy/plugins/pa.clock/thunderbird-newevent/`), which the install packs into `~/.config/omarchy/plugins/pa.clock/thunderbird-newevent.xpi`. Install it once by hand — it is unsigned and Thunderbird has no CLI for this: **Add-ons and Themes → gear → Install Add-on From File…** (reinstall the same way after an upgrade; the entry pane needs add-on 1.3.0 or newer). Arch's Thunderbird accepts it because that build sets `MOZ_REQUIRE_SIGNING=false`.

After install, sign into Thunderbird (calendar popup) and run `grok login` (agents usage). Right-click on the weather pill opens the wetter.de forecast resolved from `WEATHER_PLZ`. The weather popup adds a RainViewer map when precipitation is current or forecast today.

`omarchy default editor` only covers Omarchy launchers (`$EDITOR`, keybindings). Files / `xdg-open` still follow MIME, which Omarchy ships as Neovim. The post-install sets both: `omarchy default editor code` and `~/.config/mimeapps.list` for text/source types. Re-apply MIME later with `set-code-mime-defaults`.
