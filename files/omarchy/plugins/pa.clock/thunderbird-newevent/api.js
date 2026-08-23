// Thunderbird has no command line or URL that opens the New Event dialog on a
// given day: -calendar only switches tabs, and -file hands an .ics to the
// import tab, which is a different thing entirely. The dialog is only reachable
// from chrome JS (createEventWithDialog, the same call the Ctrl+I command
// makes), so the clock widget drops a small JSON request in the state dir and
// this add-on makes the call inside Thunderbird.
//
// A file is the trigger rather than a socket or a native messaging host on
// purpose: nothing new listens, and the request lives under the user's own
// state directory with their own permissions.

var { ExtensionCommon } = ChromeUtils.importESModule(
  "resource://gre/modules/ExtensionCommon.sys.mjs"
);
var { setInterval, clearInterval } = ChromeUtils.importESModule(
  "resource://gre/modules/Timer.sys.mjs"
);

// Fast enough that the dialog feels like it belongs to the click, cheap enough
// to ignore: one stat of a path that is almost always missing.
const POLL_MS = 400;

var omarchyNewEvent = class extends ExtensionCommon.ExtensionAPI {
  getAPI() {
    const api = this;
    return {
      omarchyNewEvent: {
        async watch(relativePath) {
          api.stopWatching();
          const home = Services.dirsvc.get("Home", Ci.nsIFile).path;
          const path = PathUtils.join(home, ...relativePath.split("/"));
          api.timer = setInterval(() => api.poll(path), POLL_MS);
        },
      },
    };
  }

  onShutdown() {
    this.stopWatching();
  }

  stopWatching() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  async poll(path) {
    // Re-entrancy guard: reading, deleting and opening the dialog all await, so
    // a slow tick must not let the next one act on a request already consumed.
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      let raw;
      try {
        raw = await IOUtils.readUTF8(path);
      } catch (e) {
        return; // No request pending — the common case.
      }
      // Consume before acting, so a request that somehow makes the dialog throw
      // cannot re-trigger forever.
      await IOUtils.remove(path, { ignoreAbsent: true });
      this.openDialog(raw);
    } finally {
      this.busy = false;
    }
  }

  openDialog(raw) {
    let request;
    try {
      request = JSON.parse(raw);
    } catch (e) {
      console.error("omarchy-clock: unreadable new-event request", e);
      return;
    }

    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(request?.date ?? ""));
    if (!match) {
      console.error("omarchy-clock: new-event request has no YYYY-MM-DD date");
      return;
    }

    const win = Services.wm.getMostRecentWindow("mail:3pane");
    if (!win || typeof win.createEventWithDialog != "function") {
      console.error("omarchy-clock: no Thunderbird window to open the dialog in");
      return;
    }

    const { cal } = ChromeUtils.importESModule(
      "resource:///modules/calendar/calUtils.sys.mjs"
    );

    let day = cal.dtz.now();
    if (!day.isMutable) {
      day = day.clone();
    }
    day.resetTo(
      Number(match[1]),
      Number(match[2]) - 1,
      Number(match[3]),
      0,
      0,
      0,
      cal.dtz.defaultTimezone
    );
    day.isDate = true;

    // Same shape as the calendar_new_event_command: the requested day at the
    // next full hour, in whichever calendar is currently selected.
    const start = cal.dtz.getDefaultStartDate(day);
    const calendar =
      typeof win.getSelectedCalendar == "function" ? win.getSelectedCalendar() : null;
    win.createEventWithDialog(calendar, start);
  }
};
