const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

function localStamp(year, month, day, hour, minute) {
  const m = String(month).padStart(2, "0")
  const d = String(day).padStart(2, "0")
  const h = String(hour).padStart(2, "0")
  const min = String(minute).padStart(2, "0")
  return `${year}-${m}-${d}T${h}:${min}`
}

function hoursFrom(year, month, day, startHour, count, tempAt) {
  const entries = []
  for (let i = 0; i < count; i++) {
    const date = new Date(year, month - 1, day, startHour + i, 0, 0)
    entries.push({
      time: localStamp(date.getFullYear(), date.getMonth() + 1, date.getDate(), date.getHours(), 0),
      temp: typeof tempAt === "function" ? tempAt(i, date) : (tempAt ?? 20)
    })
  }
  return entries
}

function reportWithHours(entries, sun) {
  const daily = sun || {}
  return {
    hourly: {
      time: entries.map(e => e.time),
      temperature_2m: entries.map(e => e.temp),
      weather_code: entries.map(e => e.code ?? 0),
      is_day: entries.map(e => e.isDay ?? 1)
    },
    daily: {
      time: daily.time || [],
      sunrise: daily.sunrise || [],
      sunset: daily.sunset || []
    }
  }
}

test("hourly forecast starts at the current hour and steps every hour", () => {
  const now = new Date(2026, 7, 30, 14, 36, 0)
  const hours = Model.buildHourlyForecast(reportWithHours(hoursFrom(2026, 8, 30, 12, 14)), now, 1, 8)

  assert.deepEqual(hours.map(h => h.timeLabel), ["14", "15", "16", "17", "18", "19", "20", "21"])
  assert.equal(hours[0].kind, "hour")
  assert.equal(hours[0].isNow, true)
  assert.equal(hours[1].isNow, false)
})

test("hourly forecast can fill twelve slots", () => {
  const now = new Date(2026, 7, 30, 14, 36, 0)
  const hours = Model.buildHourlyForecast(reportWithHours(hoursFrom(2026, 8, 30, 12, 20)), now, 1, 12)

  assert.deepEqual(hours.map(h => h.timeLabel), ["14", "15", "16", "17", "18", "19", "20", "21", "22", "23", "0", "1"])
})

test("hourly forecast inserts a future sunset between hours", () => {
  const now = new Date(2026, 7, 30, 14, 36, 0)
  const hours = Model.buildHourlyForecast(reportWithHours(hoursFrom(2026, 8, 30, 12, 14, 18), {
    time: ["2026-08-30"],
    sunrise: ["2026-08-30T06:28"],
    sunset: ["2026-08-30T20:04"]
  }), now, 1, 8)

  assert.deepEqual(hours.map(h => h.timeLabel), ["14", "15", "16", "17", "18", "19", "20", "20:04"])
  const sunset = hours[7]
  assert.equal(sunset.kind, "sunset")
  assert.equal(sunset.tempC, "18")
  assert.equal(Model.hourlySlotIcon(sunset), "")
})

test("hourly forecast skips a sunrise that already happened", () => {
  const now = new Date(2026, 7, 30, 14, 36, 0)
  const hours = Model.buildHourlyForecast(reportWithHours(hoursFrom(2026, 8, 30, 12, 12), {
    time: ["2026-08-30"],
    sunrise: ["2026-08-30T06:28"],
    sunset: ["2026-08-30T20:04"]
  }), now, 1, 8)

  assert.equal(hours.some(h => h.kind === "sunrise"), false)
})

test("hourly forecast continues overnight to fill the row", () => {
  const now = new Date(2026, 7, 30, 21, 10, 0)
  const hours = Model.buildHourlyForecast(reportWithHours(hoursFrom(2026, 8, 30, 20, 12), {
    time: ["2026-08-30", "2026-08-31"],
    sunrise: ["2026-08-30T06:28", "2026-08-31T06:30"],
    sunset: ["2026-08-30T20:04", "2026-08-31T20:02"]
  }), now, 1, 8)

  assert.deepEqual(hours.map(h => [h.timeLabel, h.kind]), [
    ["21", "hour"],
    ["22", "hour"],
    ["23", "hour"],
    ["0", "hour"],
    ["1", "hour"],
    ["2", "hour"],
    ["3", "hour"],
    ["4", "hour"]
  ])
})

test("hourly forecast inserts tomorrow's sunrise when it falls in the row", () => {
  const now = new Date(2026, 7, 31, 0, 10, 0)
  const hours = Model.buildHourlyForecast(reportWithHours(hoursFrom(2026, 8, 31, 0, 10), {
    time: ["2026-08-31"],
    sunrise: ["2026-08-31T06:30"],
    sunset: ["2026-08-31T20:02"]
  }), now, 1, 8)

  assert.deepEqual(hours.map(h => [h.timeLabel, h.kind]), [
    ["0", "hour"],
    ["1", "hour"],
    ["2", "hour"],
    ["3", "hour"],
    ["4", "hour"],
    ["5", "hour"],
    ["6", "hour"],
    ["6:30", "sunrise"]
  ])
  assert.equal(Model.hourlySlotIcon(hours[7]), "")
})

test("hourly forecast drops hours that have already ended", () => {
  const now = new Date(2026, 7, 30, 16, 0, 0)
  const hours = Model.buildHourlyForecast(reportWithHours([
    { time: localStamp(2026, 8, 30, 14, 0), temp: 20 },
    { time: localStamp(2026, 8, 30, 15, 0), temp: 21 },
    { time: localStamp(2026, 8, 30, 16, 0), temp: 22 }
  ]), now, 1, 8)

  assert.deepEqual(hours.map(h => h.timeLabel), ["16"])
  assert.equal(hours[0].isNow, true)
})

test("hourly forecast returns nothing without hourly data", () => {
  assert.deepEqual(Model.buildHourlyForecast(null, new Date(2026, 7, 30, 10, 0, 0), 1, 8), [])
  assert.deepEqual(Model.buildHourlyForecast({ daily: {} }, new Date(2026, 7, 30, 10, 0, 0), 1, 8), [])
})

test("bareTempForHour follows the panel unit", () => {
  const hour = { tempC: "18", tempF: "64" }
  assert.equal(Model.bareTempForHour(hour, false), "18°")
  assert.equal(Model.bareTempForHour(hour, true), "64°")
  assert.equal(Model.bareTempForHour(null, false), "")
})

test("hourlySlotIcon uses weather icons and sun glyphs", () => {
  assert.equal(Model.hourlySlotIcon({ kind: "sunrise" }), "")
  assert.equal(Model.hourlySlotIcon({ kind: "sunset" }), "")
  assert.equal(
    Model.hourlySlotIcon({ kind: "hour", openMeteoWeatherCode: 0, isDay: 1 }),
    Model.iconForOpenMeteoCode(0, false)
  )
})
