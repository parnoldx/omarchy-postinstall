# Omarchy Clock — New Event (Thunderbird add-on)

Right-clicking a day in the clock popup should open Thunderbird's **New Event**
dialog on that day. Thunderbird has no way to ask for that from outside:
`-calendar` only switches tabs, `-file` hands an `.ics` to the import tab, and
`-chrome` cannot pass the arguments the event dialog needs. The dialog is only
reachable from chrome JS, so this add-on makes the call from inside Thunderbird.

## How it works

- `new-thunderbird-event YYYY-MM-DD` (in the plugin directory) raises the mail
  overlay and writes `~/.local/state/omarchy/thunderbird-new-event.json`.
- This add-on polls that path and, when it appears, consumes it and calls
  `createEventWithDialog` — the same entry point as Thunderbird's own Ctrl+I —
  with the requested day at the next full hour.

A file rather than a socket or a native messaging host: nothing new listens, and
the request lives in the user's own state directory under their own permissions.

## Install

```sh
./build                 # writes ../thunderbird-newevent.xpi
```

Then in Thunderbird: **Add-ons and Themes → gear icon → Install Add-on From
File…** and pick `thunderbird-newevent.xpi`.

It is unsigned, which Arch's Thunderbird accepts because that build sets
`MOZ_REQUIRE_SIGNING=false`. Re-run `./build` and re-install after editing the
add-on; bump `version` in `manifest.json` so Thunderbird treats it as an upgrade.
