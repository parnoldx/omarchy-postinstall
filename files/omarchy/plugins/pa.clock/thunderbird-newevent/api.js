// The clock widget drops a JSON request in the user's state dir; this
// add-on consumes it from inside Thunderbird.
//
// Two request shapes share the same file:
//
//   {date: "YYYY-MM-DD"}
//     Opens the New Event dialog on that day (the original right-click
//     path, kept for anything that still writes it).
//
//   {kind: "event"|"task", title, startMs, ...}
//     Silent create via calendar.addItem. Thunderbird is not focused and
//     no dialog opens. A throw falls back to the prefilled dialog rather
//     than dropping the item.
//
// The calendar/task-list roster is written alongside so the widget's
// dropdowns show real names instead of guessing.

var { ExtensionCommon } = ChromeUtils.importESModule(
  "resource://gre/modules/ExtensionCommon.sys.mjs"
);
var { setInterval, clearInterval } = ChromeUtils.importESModule(
  "resource://gre/modules/Timer.sys.mjs"
);

const POLL_MS = 400;
const CALENDARS_REL = ".local/state/omarchy/thunderbird-calendars.json";
const TWO_YEARS_MS = 2 * 366 * 24 * 60 * 60 * 1000;

function loadCal() {
  return ChromeUtils.importESModule("resource:///modules/calendar/calUtils.sys.mjs").cal;
}

var omarchyNewEvent = class extends ExtensionCommon.ExtensionAPI {
  getAPI() {
    const api = this;
    return {
      omarchyNewEvent: {
        async watch(relativePath) {
          api.stopWatching();
          const home = Services.dirsvc.get("Home", Ci.nsIFile).path;
          const path = PathUtils.join(home, ...relativePath.split("/"));
          api.calendarsPath = PathUtils.join(home, ...CALENDARS_REL.split("/"));
          api.attachManager();
          api.writeCalendars();
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
    this.detachManager();
  }

  attachManager() {
    this.detachManager();
    try {
      const cal = loadCal();
      const api = this;
      this.observer = {
        QueryInterface: ChromeUtils.generateQI(["calICalendarManagerObserver"]),
        onCalendarRegistered() { api.writeCalendars(); },
        onCalendarUnregistering() { api.writeCalendars(); },
        onCalendarDeleting() { api.writeCalendars(); },
      };
      cal.manager.addObserver(this.observer);
    } catch (e) {
      console.error("omarchy-clock: cannot watch calendars", e);
    }
  }

  detachManager() {
    if (!this.observer) return;
    try {
      loadCal().manager.removeObserver(this.observer);
    } catch (e) {
      // Thunderbird is tearing down; the manager is already gone.
    }
    this.observer = null;
  }

  async writeCalendars() {
    if (!this.calendarsPath) return;
    let list = [];
    try {
      const cal = loadCal();
      for (const calendar of cal.manager.getCalendars()) {
        if (!calendar || calendar.getProperty("disabled")) continue;
        list.push({
          id: String(calendar.id || ""),
          name: String(calendar.name || ""),
          events: calendar.getProperty("capabilities.events.supported") !== false,
          tasks: calendar.getProperty("capabilities.tasks.supported") !== false,
        });
      }
    } catch (e) {
      console.error("omarchy-clock: cannot list calendars", e);
      return;
    }
    const body = JSON.stringify({ version: 1, calendars: list }) + "\n";
    try {
      await IOUtils.writeUTF8(this.calendarsPath, body, {
        tmpPath: this.calendarsPath + ".tmp",
      });
    } catch (e) {
      console.error("omarchy-clock: cannot write calendars file", e);
    }
  }

  async poll(path) {
    if (this.busy) return;
    this.busy = true;
    try {
      let raw;
      try {
        raw = await IOUtils.readUTF8(path);
      } catch (e) {
        return;
      }
      await IOUtils.remove(path, { ignoreAbsent: true });
      await this.handleRequest(raw);
    } finally {
      this.busy = false;
    }
  }

  async handleRequest(raw) {
    let request;
    try {
      request = JSON.parse(raw);
    } catch (e) {
      console.error("omarchy-clock: unreadable new-event request", e);
      return;
    }

    if (request && (request.kind === "event" || request.kind === "task")) {
      try {
        await this.silentCreate(request);
        this.writeCalendars();
        return;
      } catch (e) {
        console.error("omarchy-clock: silent create failed, opening dialog", e);
        this.openDialogFromCreate(request);
        return;
      }
    }

    this.openDialog(raw);
  }

  resolveCalendar(name, wantTasks) {
    const cal = loadCal();
    const calendars = cal.manager.getCalendars();
    const needle = String(name || "").toLowerCase();
    if (needle) {
      for (const calendar of calendars) {
        if (String(calendar.name || "").toLowerCase() === needle) return calendar;
      }
      for (const calendar of calendars) {
        const n = String(calendar.name || "").toLowerCase();
        if (needle.length >= 2 && n.indexOf(needle) === 0) return calendar;
      }
    }
    const win = Services.wm.getMostRecentWindow("mail:3pane");
    if (win && typeof win.getSelectedCalendar == "function") {
      const selected = win.getSelectedCalendar();
      if (selected) return selected;
    }
    for (const calendar of calendars) {
      if (calendar.getProperty("disabled")) continue;
      const ok = wantTasks
        ? calendar.getProperty("capabilities.tasks.supported") !== false
        : calendar.getProperty("capabilities.events.supported") !== false;
      if (ok) return calendar;
    }
    return calendars[0] || null;
  }

  dateTimeFromMs(ms, timezone) {
    const cal = loadCal();
    const js = new Date(ms);
    return cal.dtz.jsDateToDateTime(js, timezone);
  }

  applyRecurrence(item, recurrence) {
    if (!recurrence || !recurrence.freq) return;
    const cal = loadCal();
    const { CalRecurrenceInfo } = ChromeUtils.importESModule(
      "resource:///modules/CalRecurrenceInfo.sys.mjs"
    );
    const freq = String(recurrence.freq).toUpperCase();
    const interval = Math.max(1, Math.round(Number(recurrence.interval) || 1));
    const rule = cal.createRecurrenceRule(`FREQ=${freq};INTERVAL=${interval}`);
    const info = new CalRecurrenceInfo(item);
    info.appendRecurrenceItem(rule);
    item.recurrenceInfo = info;
  }

  applyAlert(item, alertMinutes) {
    if (!(alertMinutes > 0)) return;
    const cal = loadCal();
    const { CalAlarm } = ChromeUtils.importESModule(
      "resource:///modules/CalAlarm.sys.mjs"
    );
    const alarm = new CalAlarm();
    alarm.action = "DISPLAY";
    alarm.related = Ci.calIAlarm.ALARM_RELATED_START;
    alarm.offset = cal.createDuration("-PT" + Math.round(alertMinutes) + "M");
    item.addAlarm(alarm);
  }

  validateStamp(ms) {
    const n = Number(ms);
    if (!isFinite(n)) return false;
    return Math.abs(n - Date.now()) <= TWO_YEARS_MS;
  }

  // A meeting link goes on the item's URL property: it is the standard
  // place for one, Thunderbird shows it as the event's link, and the clock's
  // sync reads URL ahead of location and description when it looks for
  // something to join.
  linkOf(request) {
    const text = String(request.link || "").trim();
    if (!/^https?:\/\//i.test(text)) return "";
    if (/[\s"'<>]/.test(text)) return "";
    if (text.length > 2000) return "";
    return text;
  }

  async silentCreate(request) {
    const title = String(request.title || "").trim();
    if (!title) throw new Error("empty title");
    if (title.length > 300) throw new Error("title too long");
    const description = String(request.description || "").trim().slice(0, 8000);

    const calendar = this.resolveCalendar(request.calendarName, request.kind === "task");
    if (!calendar) throw new Error("no calendar");

    const cal = loadCal();
    const tz = cal.dtz.defaultTimezone;

    if (request.kind === "task") {
      const { CalTodo } = ChromeUtils.importESModule(
        "resource:///modules/CalTodo.sys.mjs"
      );
      const todo = new CalTodo();
      todo.title = title;
      if (request.dueMs != null) {
        if (!this.validateStamp(request.dueMs)) throw new Error("due out of range");
        todo.dueDate = this.dateTimeFromMs(request.dueMs, tz);
      }
      if (request.priority === 1 || request.priority === 5 || request.priority === 9)
        todo.priority = request.priority;
      if (description) todo.setProperty("DESCRIPTION", description);
      const todoLink = this.linkOf(request);
      if (todoLink) todo.setProperty("URL", todoLink);
      this.applyRecurrence(todo, request.recurrence);
      todo.calendar = calendar;
      await calendar.addItem(todo);
      return;
    }

    if (!this.validateStamp(request.startMs)) throw new Error("start out of range");
    const { CalEvent } = ChromeUtils.importESModule(
      "resource:///modules/CalEvent.sys.mjs"
    );
    const event = new CalEvent();
    event.title = title;
    const start = this.dateTimeFromMs(request.startMs, tz);
    if (request.allDay) start.isDate = true;
    event.startDate = start;

    let endMs = request.endMs;
    if (endMs == null) {
      endMs = request.allDay ? request.startMs + 24 * 60 * 60 * 1000 : request.startMs + 60 * 60 * 1000;
    }
    if (!this.validateStamp(endMs) && !request.allDay) throw new Error("end out of range");
    const end = this.dateTimeFromMs(endMs, tz);
    if (request.allDay) end.isDate = true;
    event.endDate = end;

    if (request.location) event.setProperty("LOCATION", String(request.location));
    if (description) event.setProperty("DESCRIPTION", description);
    const link = this.linkOf(request);
    if (link) event.setProperty("URL", link);
    this.applyAlert(event, request.alertMinutes);
    this.applyRecurrence(event, request.recurrence);
    event.calendar = calendar;
    await calendar.addItem(event);
  }

  openDialogFromCreate(request) {
    const win = Services.wm.getMostRecentWindow("mail:3pane");
    if (!win) return;
    try {
      const cal = loadCal();
      const tz = cal.dtz.defaultTimezone;
      const calendar = this.resolveCalendar(request.calendarName, request.kind === "task");
      if (request.kind === "task" && typeof win.createTodoWithDialog == "function") {
        const due = request.dueMs != null ? this.dateTimeFromMs(request.dueMs, tz) : null;
        win.createTodoWithDialog(calendar, due, String(request.title || ""));
        return;
      }
      if (typeof win.createEventWithDialog == "function") {
        const start = this.dateTimeFromMs(request.startMs || Date.now(), tz);
        const end = request.endMs != null ? this.dateTimeFromMs(request.endMs, tz) : null;
        win.createEventWithDialog(calendar, start, end, String(request.title || ""));
      }
    } catch (e) {
      console.error("omarchy-clock: dialog fallback failed", e);
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

    const cal = loadCal();

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

    const start = cal.dtz.getDefaultStartDate(day);
    const calendar =
      typeof win.getSelectedCalendar == "function" ? win.getSelectedCalendar() : null;
    win.createEventWithDialog(calendar, start);
  }
};
