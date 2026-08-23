const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

const MINUTE = 60 * 1000
const now = Date.parse("2026-08-23T10:00:00+02:00")

function event(overrides) {
  return Object.assign({
    id: "standup",
    title: "Standup",
    start: "2026-08-23T10:05:00+02:00",
    end: "2026-08-23T10:20:00+02:00",
    allDay: false,
    meetingUrl: "https://meet.google.com/abc-defg-hij"
  }, overrides)
}

test("nextEvent skips all-day and past events", () => {
  const events = [
    event({ id: "all", allDay: true, start: "2026-08-23", end: "2026-08-24" }),
    event({ id: "past", start: "2026-08-23T09:00:00+02:00", end: "2026-08-23T09:30:00+02:00" }),
    event({ id: "later", start: "2026-08-23T11:00:00+02:00", end: "2026-08-23T11:30:00+02:00" }),
    event({ id: "soon", start: "2026-08-23T10:15:00+02:00", end: "2026-08-23T10:45:00+02:00" })
  ]
  assert.equal(Model.nextEvent(events, now).id, "soon")
})

test("nextEvent keeps the meeting that is already in progress", () => {
  const events = [
    event({ id: "current", start: "2026-08-23T09:55:00+02:00", end: "2026-08-23T10:25:00+02:00" }),
    event({ id: "next", start: "2026-08-23T10:30:00+02:00", end: "2026-08-23T11:00:00+02:00" })
  ]
  assert.equal(Model.nextEvent(events, now).id, "current")
  assert.equal(Model.isInProgress(events[0], now), true)
  assert.equal(Model.nextEvent(events, Date.parse("2026-08-23T10:25:00+02:00")).id, "next")
})

test("formatCountdown uses MeetingBar-style units and now", () => {
  assert.equal(Model.formatCountdown(30 * 1000), "now")
  assert.equal(Model.formatCountdown(4 * MINUTE), "in 4m")
  assert.equal(Model.formatCountdown(60 * MINUTE), "in 1h")
  assert.equal(Model.formatCountdown(90 * MINUTE), "in 1h 30m")
  assert.equal(Model.formatCountdown(-30 * 1000), "now")
  assert.equal(Model.formatCountdown(24 * 60 * MINUTE), null)
})

test("shouldAnnounce covers the lead window and only the first minutes after start", () => {
  const upcoming = event()
  assert.equal(Model.shouldAnnounce(upcoming, now, 5), true)
  assert.equal(Model.shouldAnnounce(upcoming, now, 4), false)
  assert.equal(Model.shouldAnnounce(event({ start: "2026-08-23T09:55:00+02:00", end: "2026-08-23T10:20:00+02:00" }), now, 15, 5), true)
  assert.equal(Model.shouldAnnounce(event({ start: "2026-08-23T09:54:00+02:00", end: "2026-08-23T10:20:00+02:00" }), now, 15, 5), false)
  assert.equal(Model.shouldAnnounce(upcoming, now, 0), false)
})

test("isDismissed matches one occurrence and then stays quiet", () => {
  const upcoming = event()
  const key = Model.occurrenceKey(upcoming)
  assert.equal(key, "standup|2026-08-23T10:05:00+02:00")
  assert.equal(Model.isDismissed(upcoming, key), true)
  assert.equal(Model.isDismissed(upcoming, ""), false)
  assert.equal(Model.isDismissed(event({ id: "other" }), key), false)
})

test("formatStartsIn spells the Basecamp reminder copy", () => {
  assert.equal(Model.formatStartsIn(30 * 1000), "starts now")
  assert.equal(Model.formatStartsIn(1 * MINUTE), "starts in 1 minute")
  assert.equal(Model.formatStartsIn(14 * MINUTE), "starts in 14 minutes")
  assert.equal(Model.formatStartsIn(60 * MINUTE), "starts in 1 hour")
})

test("isImminent is only the last minute", () => {
  assert.equal(Model.isImminent(5 * MINUTE), false)
  assert.equal(Model.isImminent(1 * MINUTE), false)
  assert.equal(Model.isImminent(30 * 1000), true)
  assert.equal(Model.isImminent(-10 * 1000), true)
})

test("joinButtonLabel names the meeting service", () => {
  assert.equal(Model.joinButtonLabel("https://us02web.zoom.us/j/1"), "Join Zoom")
  assert.equal(Model.joinButtonLabel("https://meet.google.com/abc-defg-hij"), "Join Meet")
  assert.equal(Model.joinButtonLabel("https://teams.microsoft.com/l/meetup-join/x"), "Join Teams")
  assert.equal(Model.joinButtonLabel("https://meet.jit.si/Standup"), "Join Jitsi")
  assert.equal(Model.joinButtonLabel("https://example.com/call"), "Join")
})

test("safeUrl only launches plain https meeting links", () => {
  assert.equal(Model.meetingUrlFor(event()), "https://meet.google.com/abc-defg-hij")
  assert.equal(Model.safeUrl("http://meet.google.com/abc"), "")
  assert.equal(Model.safeUrl("https://meet.google.com/abc; rm -rf /"), "")
  assert.equal(Model.safeUrl("javascript:alert(1)"), "")
  assert.equal(Model.meetingUrlFor(null), "")
  assert.equal(Model.meetingUrlFor({
    meetingUrl: "https://us02web.zoom.us/meeting/abc/ics?icsToken=tok"
  }), "")
  assert.equal(Model.meetingUrlFor({
    meetingUrl: "https://us02web.zoom.us/j/88971526434"
  }), "https://us02web.zoom.us/j/88971526434")
})

test("safeColor takes hex calendar colours and nothing else", () => {
  assert.equal(Model.safeColor("#6600cc"), "#6600cc")
  assert.equal(Model.safeColor("  #CEE7FF "), "#CEE7FF")
  assert.equal(Model.safeColor("#abc"), "#abc")
  assert.equal(Model.safeColor("#aabbccdd"), "#aabbccdd")
  assert.equal(Model.safeColor("rebeccapurple"), "")
  assert.equal(Model.safeColor("#12345"), "")
  assert.equal(Model.safeColor(null), "")
})

test("dayColors lists each calendar once, in event order", () => {
  const events = [
    { color: "#6600cc" },
    { color: "#CEE7FF" },
    { color: "#6600cc" },
    { color: "not-a-colour" },
    {}
  ]
  assert.deepEqual(Model.dayColors(events), ["#6600cc", "#CEE7FF"])
  assert.deepEqual(Model.dayColors([]), [])
  assert.deepEqual(Model.dayColors(null), [])
})

test("monthGrid carries the calendar colours of each day", () => {
  const index = Model.indexEventsByDate([
    { dateKey: "2026-08-05", color: "#6600cc" },
    { dateKey: "2026-08-05", color: "#CEE7FF" },
    { dateKey: "2026-08-06", color: "#CEE7FF" }
  ])
  const days = Model.monthGrid(2026, 7, 1, "2026-08-23", index)
    .flatMap(week => week.days)
  const fifth = days.find(day => day.key === "2026-08-05")
  const sixth = days.find(day => day.key === "2026-08-06")
  const seventh = days.find(day => day.key === "2026-08-07")
  assert.deepEqual(fifth.colors, ["#6600cc", "#CEE7FF"])
  assert.deepEqual(sixth.colors, ["#CEE7FF"])
  assert.equal(seventh.hasEvent, false)
  assert.deepEqual(seventh.colors, [])
})
