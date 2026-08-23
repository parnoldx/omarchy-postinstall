// Pure date and format math for the clock widget and its calendar panel.
// Everything here is locale- and Qt-free so it can be unit tested under node
// (test/shell.d/clock-test.sh); the QML owns month/weekday naming through
// Qt.locale().

var MS_PER_DAY = 86400000

// Weekday indices match both JS Date.getDay() and QML's Locale.Sunday…
// Locale.Saturday, so a locale's firstDayOfWeek can be passed straight in.
var WEEKDAY_NAMES = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

// ---- Bar label formats. Right-clicking the clock walks these in order and
//      writes the result back to shell.json, so the label the bar shows and
//      the format the config stores are always the same thing.
//
// The locale-shaped time presets are each followed by their 12-hour twin, so
// the walk from a 24-hour label to the same label in AM/PM is a single right
// click rather than a lap of the ring. The ISO preset is deliberately left
// without one: ISO 8601 writes time on a 24-hour clock, so an AM/PM variant
// would contradict the only thing that format is for.
var CLOCK_FORMATS = [
  "dddd HH:mm",
  "dddd h:mm AP",
  "HH:mm",
  "h:mm AP",
  "ddd d MMM HH:mm",
  "ddd d MMM h:mm AP",
  "ddd d HH:mm",
  "ddd d h:mm AP",
  "d MMMM 'W'ww yyyy",
  "yyyy-MM-dd HH:mm"
]

// Vertical bars have room for a few stacked lines and nothing else, so the
// ring stays short. AM/PM costs a fourth line, which is why only the plain
// time carries it here.
var VERTICAL_CLOCK_FORMATS = [
  "HH\n—\nmm",
  "h\n—\nmm\nAP",
  "dd\nMMM\n'W'ww\n''yy",
  "HH\nmm"
]

function clockFormats(vertical) {
  return vertical ? VERTICAL_CLOCK_FORMATS.slice() : CLOCK_FORMATS.slice()
}

// The presets in a fixed order, plus the configured alternate and current
// format when they are something else. The order must not depend on which
// entry is current: cycling writes the result back to shell.json, and a ring
// that reshuffled itself around the current value would bounce between two
// entries instead of walking.
function clockFormatRing(configured, configuredAlt, presets) {
  var ring = []
  var candidates = (presets || []).concat([configuredAlt, configured])
  for (var i = 0; i < candidates.length; i++) {
    var format = String(candidates[i] === undefined || candidates[i] === null ? "" : candidates[i])
    if (format === "" || ring.indexOf(format) !== -1) continue
    ring.push(format)
  }
  return ring.length > 0 ? ring : ["HH:mm"]
}

// Next entry after `current`. An unknown current format (a hand-written one
// that is not in the ring) starts the walk at the top.
function nextClockFormat(ring, current) {
  if (!ring || ring.length === 0) return ""
  var index = ring.indexOf(String(current === undefined || current === null ? "" : current))
  return ring[(index + 1) % ring.length]
}

// Two-digit ISO week, substituted into a format's 'ww' token before Qt
// formats it -- Qt has no ISO week specifier of its own.
function isoWeekLiteral(year, month, day) {
  return pad2(isoWeek(year, month, day))
}

function pad2(value) {
  var n = Number(value)
  return (n < 10 ? "0" : "") + n
}

// Stable "yyyy-MM-dd" identity for a day, so a grid cell can be compared
// against today without dragging Date objects through bindings.
function dateKey(year, month, day) {
  return year + "-" + pad2(Number(month) + 1) + "-" + pad2(day)
}

function keyForDate(date) {
  return dateKey(date.getFullYear(), date.getMonth(), date.getDate())
}

function coerceWeekStart(value) {
  if (value === undefined || value === null) return null
  if (typeof value === "number")
    return isFinite(value) ? ((Math.round(value) % 7) + 7) % 7 : null

  var text = String(value).replace(/^\s+|\s+$/g, "").toLowerCase()
  if (text === "") return null

  for (var i = 0; i < WEEKDAY_NAMES.length; i++)
    if (WEEKDAY_NAMES[i] === text || WEEKDAY_NAMES[i].substr(0, 3) === text) return i

  var parsed = parseInt(text, 10)
  return isFinite(parsed) ? ((parsed % 7) + 7) % 7 : null
}

// Configured week start, falling back to the locale's own first day when
// the setting is missing or nonsense.
function normalizedWeekStart(value, fallback) {
  var configured = coerceWeekStart(value)
  if (configured !== null) return configured
  var fallbackStart = coerceWeekStart(fallback)
  return fallbackStart === null ? 1 : fallbackStart
}

function weekStartSettingName(index) {
  return WEEKDAY_NAMES[normalizedWeekStart(index, 1)]
}

// The toggle flips between the two conventions people actually switch
// between. A calendar configured to any other start (Saturday, say) is
// shown as-is and lands on Monday the first time it is toggled.
function toggledWeekStart(index) {
  return normalizedWeekStart(index, 1) === 1 ? 0 : 1
}

function weekdayOrder(weekStart) {
  var start = normalizedWeekStart(weekStart, 1)
  var out = []
  for (var i = 0; i < 7; i++) out.push((start + i) % 7)
  return out
}

// ISO-8601 week number: the week owning the Thursday of that date's
// Monday-based week. Mirrors the clock widget's 'ww' format token.
function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7)
}

function dayOfYear(year, month, day) {
  return Math.round((Date.UTC(year, month, day) - Date.UTC(year, 0, 1)) / MS_PER_DAY) + 1
}

function daysInYear(year) {
  return dayOfYear(year, 11, 31)
}

// Share of the year already behind you: whole days completed over days in
// the year, so January 1 reads 0% and December 31 reads 100%.
function yearProgress(year, month, day) {
  var total = daysInYear(year)
  if (total <= 0) return 0
  return Math.max(0, Math.min(1, (dayOfYear(year, month, day) - 1) / total))
}

function yearProgressPercent(year, month, day) {
  return Math.round(yearProgress(year, month, day) * 100)
}

// Memento mori. The default span is a round number rather than anything from
// an actuarial table: the point of the bar is the reminder, not the
// arithmetic, and whoever wants a different number can say so.
var DEFAULT_LIFE_EXPECTANCY = 90

// A birth year rather than an age, so the bar keeps counting on its own
// instead of going stale the moment it is entered. 0 means "not set", which
// is also what a blank, malformed, future, or implausibly distant year means.
function parseBirthYear(value, currentYear) {
  var now = Math.round(Number(currentYear))
  if (!isFinite(now)) return 0
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d{4}$/.test(text)) return 0
  var year = parseInt(text, 10)
  if (!isFinite(year) || year > now || year < now - 120) return 0
  return year
}

// Whole years, the way people say their age: born in 1979 makes you 47 for
// all of 2026, whichever side of your birthday today falls.
function ageFromBirthYear(birthYear, currentYear) {
  var born = parseBirthYear(birthYear, currentYear)
  if (born <= 0) return 0
  return Math.round(Number(currentYear)) - born
}

// 0 means "not set", which is also what a blank, negative, fractional, or
// absurd entry means — the life bar simply stays hidden.
function parseAge(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return 0
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 120) return 0
  return years
}

// Unset or nonsense falls back to the default rather than to zero, so the
// bar always has something to measure against.
function parseLifeExpectancy(value) {
  var text = String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
  if (!/^\d+$/.test(text)) return DEFAULT_LIFE_EXPECTANCY
  var years = parseInt(text, 10)
  if (!isFinite(years) || years <= 0 || years > 150) return DEFAULT_LIFE_EXPECTANCY
  return years
}

function lifeProgress(age, expectancy) {
  var years = parseAge(age)
  var span = parseLifeExpectancy(expectancy)
  if (years <= 0 || span <= 0) return 0
  return Math.max(0, Math.min(1, years / span))
}

function lifeProgressPercent(age, expectancy) {
  return Math.round(lifeProgress(age, expectancy) * 100)
}

// Always six rows of seven days. A fixed grid keeps the popup exactly the
// same height in every month, so stepping through the year never makes the
// panel jump under the pointer.
function monthGrid(year, month, weekStart, todayKey, eventIndex) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = String(todayKey || "")
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    var thursday = null
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var key = dateKey(cellYear, cellMonth, cellDay)
      if (weekday === 4) thursday = { year: cellYear, month: cellMonth, day: cellDay }
      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today,
        hasEvent: eventIndex ? !!eventIndex[key] : false,
        colors: eventIndex ? dayColors(eventIndex[key]) : []
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    // Number every row by the ISO week owning its Thursday. That is the
    // definition itself for Monday-start weeks, and the only answer that
    // stays stable for the other starts, where a row straddles two ISO
    // weeks but shares all of Monday through Thursday with one of them.
    var anchor = thursday || days[0]
    weeks.push({
      week: isoWeek(anchor.year, anchor.month, anchor.day),
      days: days
    })
  }
  return weeks
}

function stepMonth(year, month, delta) {
  var target = new Date(year, Number(month) + Number(delta), 1)
  return { year: target.getFullYear(), month: target.getMonth() }
}

function indexEventsByDate(events) {
  var index = {}
  if (!events || !events.length) return index
  for (var i = 0; i < events.length; i++) {
    var event = events[i]
    var key = event && event.dateKey
    if (!key) continue
    if (!index[key]) index[key] = []
    index[key].push(event)
  }
  return index
}

function eventsForDateKey(index, dateKey) {
  if (!index || !dateKey) return []
  var list = (index[dateKey] || []).slice()
  list.sort(function(a, b) {
    if (a.allDay && !b.allDay) return -1
    if (!a.allDay && b.allDay) return 1
    return String(a.start || a.time || "").localeCompare(String(b.start || b.time || ""))
  })
  return list
}

function dateFromKey(dateKey, fallback) {
  var parts = String(dateKey || "").split("-")
  if (parts.length !== 3) return fallback
  var year = parseInt(parts[0], 10)
  var month = parseInt(parts[1], 10)
  var day = parseInt(parts[2], 10)
  if (isNaN(year) || isNaN(month) || isNaN(day)) return fallback
  return new Date(year, month - 1, day)
}

function formatDateKey(dk) {
  var d = dateFromKey(dk, null)
  if (!d) return String(dk || "")
  return d.toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" })
}

function parseEventDocument(raw) {
  if (!raw) return null
  try {
    var parsed = JSON.parse(raw)
    if (parsed && parsed.version === 1) return parsed
  } catch (error) {
    return null
  }
  return null
}

var MINUTE_MS = 60 * 1000
var HOUR_MS = 60 * MINUTE_MS
var DAY_MS = 24 * HOUR_MS

function eventStartMs(event) {
  if (!event || !event.start) return NaN
  return Date.parse(event.start)
}

function eventEndMs(event) {
  if (!event) return NaN
  if (event.end) {
    var end = Date.parse(event.end)
    if (!isNaN(end)) return end
  }
  var start = eventStartMs(event)
  if (isNaN(start)) return NaN
  return start + HOUR_MS
}

// Timed events only. All-day rows stay on the calendar grid and never
// take the bar: they have no join link and no "in 4m" that would mean
// anything.
function isInProgress(event, nowMs) {
  if (!event || event.allDay) return false
  var start = eventStartMs(event)
  var end = eventEndMs(event)
  if (isNaN(start) || isNaN(end)) return false
  return nowMs >= start && nowMs < end
}

// Current meeting first, otherwise the soonest timed start still ahead.
// MeetingBar keeps the join target on the bar after the hour, so a click
// at 10:01 still opens the 10:00 standup rather than the 11:00 next.
function nextEvent(events, nowMs) {
  var current = null
  var currentStart = null
  var upcoming = null
  var upcomingStart = null

  for (var i = 0; i < (events || []).length; i++) {
    var event = events[i]
    if (!event || event.allDay) continue

    var startMs = eventStartMs(event)
    if (isNaN(startMs)) continue

    if (isInProgress(event, nowMs)) {
      if (currentStart === null || startMs < currentStart) {
        current = event
        currentStart = startMs
      }
      continue
    }

    if (startMs < nowMs) continue
    if (upcomingStart === null || startMs < upcomingStart) {
      upcoming = event
      upcomingStart = startMs
    }
  }

  return current || upcoming
}

function formatCountdown(deltaMs) {
  if (deltaMs === null || isNaN(deltaMs)) return null
  if (deltaMs >= DAY_MS || deltaMs < -DAY_MS) return null
  if (deltaMs < MINUTE_MS) return "now"

  var minutes = Math.floor(deltaMs / MINUTE_MS)
  if (minutes < 60) return "in " + minutes + "m"

  var hours = Math.floor(minutes / 60)
  var rest = minutes % 60
  return rest === 0 ? "in " + hours + "h" : "in " + hours + "h " + rest + "m"
}

// "starts in 5 minutes", then "starts now" in the last minute.
function formatStartsIn(deltaMs) {
  if (deltaMs === null || isNaN(deltaMs)) return ""
  if (deltaMs < MINUTE_MS) return "starts now"
  var minutes = Math.floor(deltaMs / MINUTE_MS)
  if (minutes <= 0) return "starts now"
  if (minutes === 1) return "starts in 1 minute"
  if (minutes < 60) return "starts in " + minutes + " minutes"
  var hours = Math.floor(minutes / 60)
  var rest = minutes % 60
  if (rest === 0) return hours === 1 ? "starts in 1 hour" : "starts in " + hours + " hours"
  return "starts in " + hours + "h " + rest + "m"
}

// Red only in the last minute, including "starts now".
function isImminent(deltaMs) {
  if (deltaMs === null || isNaN(deltaMs)) return false
  return deltaMs < MINUTE_MS
}

function joinButtonLabel(url) {
  var text = String(url || "").toLowerCase()
  if (text.indexOf("zoom.") !== -1) return "Join Zoom"
  if (text.indexOf("meet.google.") !== -1) return "Join Meet"
  if (text.indexOf("teams.") !== -1) return "Join Teams"
  if (text.indexOf("jit.si") !== -1 || text.indexOf("jitsi") !== -1) return "Join Jitsi"
  return "Join"
}

var MAX_ANNOUNCE_TITLE = 28

function truncateTitle(title, limit) {
  var text = String(title === undefined || title === null ? "" : title)
  var max = limit || MAX_ANNOUNCE_TITLE
  if (text.length <= max) return text
  return text.substring(0, max - 1).replace(/\s+$/, "") + "…"
}

function announceLabel(clockText, title, countdown, limit) {
  if (!countdown) return clockText
  var shown = truncateTitle(title, limit)
  if (!shown) return clockText
  return clockText + "  ·  " + shown + " " + countdown
}

function millisUntil(event, nowMs) {
  if (!event) return null
  var startMs = Date.parse(event.start)
  if (isNaN(startMs)) return null
  return startMs - nowMs
}

function shouldAnnounce(event, nowMs, leadMinutes, startedLeadMinutes) {
  if (!event) return false
  var delta = millisUntil(event, nowMs)
  if (delta === null) return false

  if (delta <= 0) {
    if (!isInProgress(event, nowMs)) return false
    var startedLead = startedLeadMinutes === undefined || startedLeadMinutes === null
      ? 5
      : Number(startedLeadMinutes)
    if (!isFinite(startedLead) || startedLead <= 0) return false
    return -delta <= startedLead * MINUTE_MS
  }

  var lead = Number(leadMinutes)
  if (!isFinite(lead) || lead <= 0) return false
  return delta <= lead * MINUTE_MS
}

function occurrenceKey(event) {
  if (!event) return ""
  var id = String(event.id || "")
  var start = String(event.start || "")
  if (!id && !start) return ""
  return id + "|" + start
}

function isDismissed(event, dismissedKey) {
  var key = occurrenceKey(event)
  return key !== "" && key === String(dismissedKey || "")
}

function joinTooltip(event) {
  var title = String(event && event.title ? event.title : "").replace(/^\s+|\s+$/g, "")
  return title ? "Join " + title : "Join meeting"
}

function eventDisplayTime(event) {
  if (!event) return ""
  if (event.allDay) return "All day"
  if (event.time) return event.time
  if (!event.start) return ""
  var start = new Date(event.start)
  if (isNaN(start.getTime())) return ""
  var h = start.getHours()
  var m = start.getMinutes()
  return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
}

// Only https is ever launched. A meeting link is supplied by whoever sent
// the invitation, so treating it as trusted input would be a mistake.
function safeUrl(url) {
  var text = String(url || "").trim()
  if (text.indexOf("https://") !== 0) return ""
  if (/[\s"'<>]/.test(text)) return ""
  return text
}

// Thunderbird keeps a colour per calendar and the sync script carries it onto
// every event, so a work event and a personal one on the same day can be told
// apart at a glance instead of both reading as the theme accent. Validated
// rather than trusted: the value comes out of the profile prefs, and QML turns
// anything it cannot parse into black rather than falling back.
function safeColor(value) {
  var text = String(value || "").trim()
  return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(text) ? text : ""
}

function eventColor(event) {
  return event ? safeColor(event.color) : ""
}

// The distinct calendar colours on one day, in the order their first event
// falls. A day with three events out of one calendar gets one dot; a day
// split across two calendars gets two.
function dayColors(events) {
  var colors = []
  for (var i = 0; events && i < events.length; i++) {
    var color = eventColor(events[i])
    if (color && colors.indexOf(color) === -1) colors.push(color)
  }
  return colors
}

function isCalendarFileUrl(url) {
  var text = String(url || "")
  return /\/ics(\?|$)/i.test(text) || /\.ics(\?|$)/i.test(text) || /icsToken=/i.test(text)
}

function meetingUrlFor(event) {
  var text = event ? safeUrl(event.meetingUrl) : ""
  if (!text || isCalendarFileUrl(text)) return ""
  return text
}

if (typeof module !== "undefined") {
  module.exports = {
    dateKey: dateKey,
    keyForDate: keyForDate,
    normalizedWeekStart: normalizedWeekStart,
    weekStartSettingName: weekStartSettingName,
    toggledWeekStart: toggledWeekStart,
    weekdayOrder: weekdayOrder,
    isoWeek: isoWeek,
    dayOfYear: dayOfYear,
    daysInYear: daysInYear,
    yearProgress: yearProgress,
    yearProgressPercent: yearProgressPercent,
    parseAge: parseAge,
    parseBirthYear: parseBirthYear,
    ageFromBirthYear: ageFromBirthYear,
    parseLifeExpectancy: parseLifeExpectancy,
    lifeProgress: lifeProgress,
    lifeProgressPercent: lifeProgressPercent,
    monthGrid: monthGrid,
    stepMonth: stepMonth,
    clockFormats: clockFormats,
    clockFormatRing: clockFormatRing,
    nextClockFormat: nextClockFormat,
    isoWeekLiteral: isoWeekLiteral,
    indexEventsByDate: indexEventsByDate,
    eventsForDateKey: eventsForDateKey,
    dateFromKey: dateFromKey,
    formatDateKey: formatDateKey,
    parseEventDocument: parseEventDocument,
    nextEvent: nextEvent,
    eventStartMs: eventStartMs,
    eventEndMs: eventEndMs,
    isInProgress: isInProgress,
    formatCountdown: formatCountdown,
    formatStartsIn: formatStartsIn,
    isImminent: isImminent,
    joinButtonLabel: joinButtonLabel,
    truncateTitle: truncateTitle,
    announceLabel: announceLabel,
    millisUntil: millisUntil,
    shouldAnnounce: shouldAnnounce,
    occurrenceKey: occurrenceKey,
    isDismissed: isDismissed,
    joinTooltip: joinTooltip,
    eventDisplayTime: eventDisplayTime,
    safeUrl: safeUrl,
    safeColor: safeColor,
    eventColor: eventColor,
    dayColors: dayColors,
    isCalendarFileUrl: isCalendarFileUrl,
    meetingUrlFor: meetingUrlFor
  }
}
