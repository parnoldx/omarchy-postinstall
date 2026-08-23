# Omarchy Clock — New Event (Thunderbird add-on)

The clock widget cannot create a calendar item from outside Thunderbird:
`-calendar` only switches tabs, `-file` hands an `.ics` to the import tab,
and `-chrome` cannot pass the arguments the event dialog needs. This add-on
watches a request file and acts from inside Thunderbird.

## How it works

`quick-add-thunderbird '<json>'` (and the older `new-thunderbird-event
YYYY-MM-DD`) write `~/.local/state/omarchy/thunderbird-new-event.json`.
The add-on polls that path, consumes the file, and:

- `{kind:"event"|"task", title, startMs, …}` — creates the item with
  `calendar.addItem`. Thunderbird is not focused and no dialog opens.
- `{date:"YYYY-MM-DD"}` — opens the New Event dialog on that day, same
  as Thunderbird's own Ctrl+I.

A throw on the silent path falls back to the prefilled dialog rather than
dropping the item.

On start (and whenever calendars are added or removed) the add-on also
writes `~/.local/state/omarchy/thunderbird-calendars.json` so the widget's
dropdowns show real calendar and task-list names.

A file rather than a socket or a native messaging host: nothing new
listens, and the request lives in the user's own state directory under
their own permissions.

## Install

```sh
./build                 # writes ../thunderbird-newevent.xpi
```

Then in Thunderbird: **Add-ons and Themes → gear icon → Install Add-on From
File…** and pick `thunderbird-newevent.xpi`.

It is unsigned, which Arch's Thunderbird accepts because that build sets
`MOZ_REQUIRE_SIGNING=false`. Re-run `./build` and re-install after editing
the add-on; bump `version` in `manifest.json` so Thunderbird treats it as
an upgrade. This revision is **1.1.0**.
