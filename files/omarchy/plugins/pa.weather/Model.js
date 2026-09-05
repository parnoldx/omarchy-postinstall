// weather.json holds {"name": ..., "latitude": ..., "longitude": ...} (see
// omarchy-weather-location, which owns the format). Missing, blank, or
// unparseable means the location is auto-detected from the IP address.
function parseLocationFile(raw) {
  var unset = { name: "", latitude: null, longitude: null }
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return unset

    var latitude = parseFloat(data.latitude)
    var longitude = parseFloat(data.longitude)
    var hasCoordinates = !isNaN(latitude) && !isNaN(longitude)
    return {
      name: typeof data.name === "string" ? data.name.replace(/^\s+|\s+$/g, "") : "",
      latitude: hasCoordinates ? latitude : null,
      longitude: hasCoordinates ? longitude : null
    }
  } catch (e) {
    return unset
  }
}

// wttr.in path segment for a configured location: exact coordinates when
// both are present, the URL-encoded name as a fallback (hand-edited
// weather.loc files may only carry a name), empty for IP auto-detect.
function wttrLocationQuery(location, latitude, longitude) {
  var lat = parseFloat(String(latitude))
  var lon = parseFloat(String(longitude))
  if (!isNaN(lat) && !isNaN(lon)) return lat + "," + lon

  var name = String(location || "").replace(/^\s+|\s+$/g, "")
  return name === "" ? "" : encodeURIComponent(name)
}

// Open-Meteo geocoding response → suggestion rows for the location picker.
function parseGeocodingResults(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var results = data.results
    if (!results || !results.length) return []

    var out = []
    for (var i = 0; i < results.length; i++) {
      var r = results[i]
      if (!r || !r.name || r.latitude === undefined || r.longitude === undefined) continue
      var region = [r.admin1, r.country].filter(function(part) { return !!part }).join(", ")
      out.push({
        name: String(r.name),
        description: region,
        latitude: r.latitude,
        longitude: r.longitude
      })
    }
    return out
  } catch (e) {
    return []
  }
}

function locationCommit(text, suggestions, selectedIndex) {
  var name = String(text || "").replace(/^\s+|\s+$/g, "")
  if (name === "") return { name: "", latitude: null, longitude: null }

  var choices = suggestions || []
  var index = Math.max(0, Math.min(parseInt(selectedIndex, 10) || 0, choices.length - 1))
  var suggestion = choices[index]
  if (suggestion) return suggestion

  return { name: name, latitude: null, longitude: null }
}

function isFutureForecastDate(dateString, todayString) {
  if (!dateString) return false
  return String(dateString).slice(0, 10) > String(todayString || "")
}

function roundedTemp(value) {
  if (value === undefined || value === null || value === "") return ""
  var n = parseFloat(String(value))
  return isNaN(n) ? "" : String(Math.round(n))
}

function celsiusToFahrenheit(value) {
  if (value === undefined || value === null || value === "") return ""
  var n = parseFloat(String(value))
  return isNaN(n) ? "" : (n * 9 / 5) + 32
}

function formatTemp(value, useImperial) {
  if (value === undefined || value === null || value === "") return ""
  return value + "°" + (useImperial ? "F" : "C")
}

function parseHomeAssistantTemperature(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return null

    var n = parseFloat(String(data.state))
    if (isNaN(n)) return null

    var attrs = data.attributes || {}
    return {
      value: n,
      unit: String(attrs.unit_of_measurement || "°C"),
      name: String(attrs.friendly_name || ""),
      entityId: String(data.entity_id || "")
    }
  } catch (e) {
    return null
  }
}

function homeAssistantTempIsFahrenheit(unit) {
  return /f/i.test(String(unit || ""))
}

function formatHomeAssistantTemp(state, useImperial) {
  if (!state) return ""
  var celsius = homeAssistantTempIsFahrenheit(state.unit)
    ? (state.value - 32) * 5 / 9
    : state.value
  var display = useImperial ? celsiusToFahrenheit(celsius) : celsius
  return formatTemp(roundedTemp(display), useImperial)
}

function parseHomeAssistantTimestamp(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!data || typeof data !== "object") return null

    var ms = Date.parse(String(data.state || ""))
    if (isNaN(ms)) return null

    var attrs = data.attributes || {}
    return {
      at: ms,
      name: String(attrs.friendly_name || ""),
      entityId: String(data.entity_id || "")
    }
  } catch (e) {
    return null
  }
}

// Countdown to an HA timestamp: whole hours while >= 1h, whole minutes under that.
function formatCountdown(state, now) {
  if (!state || !state.at) return ""
  var nowMs = now instanceof Date ? now.getTime() : Date.parse(String(now || ""))
  if (isNaN(nowMs)) nowMs = Date.now()

  var delta = state.at - nowMs
  if (delta < 0) delta = 0

  var hourMs = 60 * 60 * 1000
  if (delta >= hourMs) return Math.round(delta / hourMs) + "h"
  return Math.max(delta > 0 ? 1 : 0, Math.round(delta / (60 * 1000))) + "m"
}

function normalizedUnit(value) {
  return String(value || "").replace(/^\s+|\s+$/g, "").toLowerCase()
}

function localeUsesImperial(localeName) {
  var name = String(localeName || "").replace(".", "_")
  return /^en[_-]US($|[_.-])/.test(name) || /^en[_-]LR($|[_.-])/.test(name) || /^my($|[_.-])/.test(name)
}

function countryUsesImperial(countryName) {
  var country = String(countryName || "")
    .replace(/^\s+|\s+$/g, "")
    .replace(/[._-]+/g, " ")
    .toLowerCase()
  if (!country) return null
  if (country === "us" || country === "usa" || country === "united states" || country === "united states of america") return true
  if (country === "liberia" || country === "myanmar" || country === "burma") return true
  return false
}

function shouldUseImperial(unitOverride, localeName, countryName) {
  var unit = normalizedUnit(unitOverride)
  if (unit === "imperial") return true
  if (unit === "metric") return false

  var countryPreference = countryUsesImperial(countryName)
  if (countryPreference !== null) return countryPreference

  return localeUsesImperial(localeName)
}

function dayName(dateString, formatter) {
  if (!dateString) return ""
  var d = new Date(dateString + "T12:00:00")
  if (isNaN(d.getTime())) return ""
  if (formatter) return formatter(d)
  return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][d.getDay()]
}

function openMeteoForecastDays(dailyForecastReport, todayString) {
  var daily = dailyForecastReport && dailyForecastReport.daily ? dailyForecastReport.daily : null
  if (!daily || !daily.time) return []

  var result = []
  for (var i = 0; i < daily.time.length && result.length < 3; ++i) {
    var date = daily.time[i]
    if (!isFutureForecastDate(date, todayString)) continue

    var maxC = daily.temperature_2m_max ? daily.temperature_2m_max[i] : ""
    var minC = daily.temperature_2m_min ? daily.temperature_2m_min[i] : ""
    result.push({
      date: date,
      maxtempC: roundedTemp(maxC),
      mintempC: roundedTemp(minC),
      maxtempF: roundedTemp(celsiusToFahrenheit(maxC)),
      mintempF: roundedTemp(celsiusToFahrenheit(minC)),
      openMeteoWeatherCode: daily.weather_code ? daily.weather_code[i] : null
    })
  }
  return result
}

// Open-Meteo bundles current conditions with the daily forecast request and
// answers far faster than wttr.in. Normalize them to wttr's
// current_condition shape so the panel can use either source
// interchangeably. Open-Meteo reports metric (°C, km/h).
function openMeteoCurrentCondition(dailyForecastReport) {
  var current = dailyForecastReport && dailyForecastReport.current ? dailyForecastReport.current : null
  if (!current || current.temperature_2m === undefined || current.temperature_2m === null) return null
  return {
    temp_C: roundedTemp(current.temperature_2m),
    temp_F: roundedTemp(celsiusToFahrenheit(current.temperature_2m)),
    FeelsLikeC: roundedTemp(current.apparent_temperature),
    FeelsLikeF: roundedTemp(celsiusToFahrenheit(current.apparent_temperature)),
    windspeedKmph: roundedTemp(current.wind_speed_10m),
    windspeedMiles: roundedTemp(current.wind_speed_10m * 0.621371),
    humidity: roundedTemp(current.relative_humidity_2m),
    precipMM: current.precipitation,
    precipitation: current.precipitation,
    openMeteoWeatherCode: current.weather_code,
    isDay: current.is_day
  }
}

// Open-Meteo WMO codes: 0-3 clear/cloud, 45/48 fog, 51+ precipitation
// (drizzle, rain, snow, showers, thunder).
function isOpenMeteoPrecipitation(code) {
  var c = parseInt(String(code), 10)
  return !isNaN(c) && c >= 51
}

// wttr.in codes that are not rain, snow, sleet, or thunder: sun, cloud, fog.
function isWttrPrecipitation(code) {
  var c = parseInt(String(code), 10)
  if (isNaN(c) || c <= 0) return false
  return c !== 113 && c !== 116 && c !== 119 && c !== 122 && c !== 143 && c !== 248 && c !== 260
}

function precipitationAmount(current) {
  if (!current) return 0
  var raw = current.precipitation
  if (raw === undefined || raw === null || raw === "") raw = current.precipMM
  var n = parseFloat(String(raw))
  return isNaN(n) ? 0 : n
}

// True when current conditions already have rain, snow, showers, or thunder.
function isPrecipitationPresent(current) {
  if (!current) return false
  if (precipitationAmount(current) > 0) return true
  if (current.openMeteoWeatherCode !== undefined && current.openMeteoWeatherCode !== null)
    return isOpenMeteoPrecipitation(current.openMeteoWeatherCode)
  if (current.weatherCode !== undefined && current.weatherCode !== null)
    return isWttrPrecipitation(current.weatherCode)
  return false
}

function isPrecipitationForecastToday(dailyForecastReport, todayString) {
  var daily = dailyForecastReport && dailyForecastReport.daily ? dailyForecastReport.daily : null
  if (!daily || !daily.time) return false

  var today = String(todayString || "").slice(0, 10)
  for (var i = 0; i < daily.time.length; i++) {
    if (String(daily.time[i]).slice(0, 10) !== today) continue
    return isOpenMeteoPrecipitation(daily.weather_code ? daily.weather_code[i] : null)
  }
  return false
}

// Radar belongs in the popup only when rain is falling here or forecast today.
function shouldShowRadar(current, dailyForecastReport, todayString) {
  return isPrecipitationPresent(current) || isPrecipitationForecastToday(dailyForecastReport, todayString)
}

function currentIcon(current, fallback) {
  if (!current) return fallback || ""
  if (current.openMeteoWeatherCode !== undefined && current.openMeteoWeatherCode !== null)
    return iconForOpenMeteoCode(current.openMeteoWeatherCode, Number(current.isDay) === 0)
  if (current.weatherCode !== undefined && current.weatherCode !== null)
    return iconForCode(current.weatherCode, false)
  return fallback || ""
}

// wttr.in has no day/night flag. Use its icon only to fill an empty initial
// state, never to replace a day/night-aware icon resolved by Open-Meteo.
function provisionalCurrentIcon(current, resolvedIcon) {
  return resolvedIcon || currentIcon(current, "")
}

function weatherResponseCompletesSave(hasConfiguredCoordinates, source) {
  return hasConfiguredCoordinates ? source === "open-meteo" : source === "wttr"
}

function wttrNextForecastDays(report, todayString) {
  var days = report && report.weather ? report.weather : []
  var result = []
  for (var i = 0; i < days.length && result.length < 3; ++i) {
    if (isFutureForecastDate(days[i].date, todayString)) result.push(days[i])
  }
  return result
}

function buildForecastDays(report, dailyForecastReport, todayString) {
  var days = openMeteoForecastDays(dailyForecastReport, todayString)
  return days.length > 0 ? days : wttrNextForecastDays(report, todayString)
}

function parseLocalDateTime(iso) {
  var match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(String(iso || ""))
  if (!match) return null

  var hour = parseInt(match[4], 10)
  var minute = parseInt(match[5], 10)
  return {
    date: match[1] + "-" + match[2] + "-" + match[3],
    hour: hour,
    minute: minute,
    ms: new Date(
      parseInt(match[1], 10),
      parseInt(match[2], 10) - 1,
      parseInt(match[3], 10),
      hour,
      minute,
      0
    ).getTime()
  }
}

function nowMs(now) {
  if (now && typeof now.getTime === "function") {
    var ms = now.getTime()
    if (!isNaN(ms)) return ms
  }
  if (typeof now === "number" && !isNaN(now)) return now
  var parsed = Date.parse(String(now || ""))
  return isNaN(parsed) ? Date.now() : parsed
}

var HOUR_MS = 60 * 60 * 1000
var SUNRISE_ICON = ""
var SUNSET_ICON = ""

function pad2(n) {
  return (n < 10 ? "0" : "") + String(n)
}

function clockLabel(hour, minute) {
  if (!minute) return String(hour)
  return hour + ":" + pad2(minute)
}

function hourlyTempAt(hourly, eventMs) {
  var bestTemp = ""
  var bestMs = -Infinity
  var afterTemp = ""
  var afterMs = Infinity
  if (!hourly || !hourly.time) return ""

  for (var i = 0; i < hourly.time.length; i++) {
    var parsed = parseLocalDateTime(hourly.time[i])
    if (!parsed) continue
    var temp = hourly.temperature_2m ? hourly.temperature_2m[i] : ""
    if (parsed.ms <= eventMs && parsed.ms >= bestMs) {
      bestMs = parsed.ms
      bestTemp = temp
    } else if (parsed.ms > eventMs && parsed.ms < afterMs) {
      afterMs = parsed.ms
      afterTemp = temp
    }
  }
  return bestMs !== -Infinity ? bestTemp : afterTemp
}

function sunEventsFromDaily(daily, currentMs, windowEnd) {
  var events = []
  if (!daily) return events

  var kinds = [
    { key: "sunrise", kind: "sunrise" },
    { key: "sunset", kind: "sunset" }
  ]
  for (var k = 0; k < kinds.length; k++) {
    var arr = daily[kinds[k].key]
    if (!arr) continue
    for (var i = 0; i < arr.length; i++) {
      var parsed = parseLocalDateTime(arr[i])
      if (!parsed) continue
      if (parsed.ms < currentMs || parsed.ms > windowEnd) continue
      events.push({
        kind: kinds[k].kind,
        date: parsed.date,
        hour: parsed.hour,
        minute: parsed.minute,
        ms: parsed.ms,
        timeLabel: clockLabel(parsed.hour, parsed.minute)
      })
    }
  }
  return events
}

function hourSlot(hourly, index, parsed, currentMs) {
  var tempC = hourly.temperature_2m ? hourly.temperature_2m[index] : ""
  var hourEnd = parsed.ms + HOUR_MS
  return {
    kind: "hour",
    date: parsed.date,
    hour: parsed.hour,
    minute: parsed.minute,
    ms: parsed.ms,
    isNow: parsed.ms <= currentMs && currentMs < hourEnd,
    timeLabel: clockLabel(parsed.hour, parsed.minute),
    tempC: roundedTemp(tempC),
    tempF: roundedTemp(celsiusToFahrenheit(tempC)),
    openMeteoWeatherCode: hourly.weather_code ? hourly.weather_code[index] : null,
    isDay: hourly.is_day ? hourly.is_day[index] : 1
  }
}

// Upcoming hours plus sunrise/sunset, one row. The hour that is still
// in progress stays (Apple starts the strip there); anything already
// over is dropped. Sun events slot in at their real time.
function buildHourlyForecast(dailyForecastReport, now, stepHours, maxCount) {
  var hourly = dailyForecastReport && dailyForecastReport.hourly ? dailyForecastReport.hourly : null
  if (!hourly || !hourly.time || !hourly.time.length) return []

  var currentMs = nowMs(now)
  var step = parseInt(stepHours, 10)
  if (isNaN(step) || step < 1) step = 1
  var limit = parseInt(maxCount, 10)
  if (isNaN(limit) || limit < 1) limit = 12
  var windowEnd = currentMs + (limit + 4) * step * HOUR_MS

  var hours = []
  for (var i = 0; i < hourly.time.length; i++) {
    var parsed = parseLocalDateTime(hourly.time[i])
    if (!parsed) continue
    if (parsed.hour % step !== 0) continue
    if (parsed.ms + HOUR_MS <= currentMs) continue
    if (parsed.ms > windowEnd) continue
    hours.push(hourSlot(hourly, i, parsed, currentMs))
  }

  var suns = sunEventsFromDaily(
    dailyForecastReport && dailyForecastReport.daily,
    currentMs,
    windowEnd
  )
  var sunAt = {}
  for (var s = 0; s < suns.length; s++) {
    var temp = hourlyTempAt(hourly, suns[s].ms)
    suns[s].isNow = false
    suns[s].tempC = roundedTemp(temp)
    suns[s].tempF = roundedTemp(celsiusToFahrenheit(temp))
    suns[s].openMeteoWeatherCode = null
    suns[s].isDay = suns[s].kind === "sunrise" ? 1 : 0
    sunAt[suns[s].ms] = true
  }

  var merged = []
  for (var h = 0; h < hours.length; h++) {
    if (!sunAt[hours[h].ms]) merged.push(hours[h])
  }
  for (s = 0; s < suns.length; s++) merged.push(suns[s])
  merged.sort(function(a, b) { return a.ms - b.ms })
  if (merged.length > limit) merged = merged.slice(0, limit)
  return merged
}

function hourlySlotIcon(slot) {
  if (!slot) return ""
  if (slot.kind === "sunrise") return SUNRISE_ICON
  if (slot.kind === "sunset") return SUNSET_ICON
  return iconForOpenMeteoCode(slot.openMeteoWeatherCode, Number(slot.isDay) === 0)
}

function bareTempForDay(day, kind, useImperial) {
  if (!day) return ""
  var v = useImperial
    ? (kind === "max" ? day.maxtempF : day.mintempF)
    : (kind === "max" ? day.maxtempC : day.mintempC)
  if (v === undefined || v === null || v === "") return ""
  return v + "°"
}

function bareTempForHour(hour, useImperial) {
  if (!hour) return ""
  var v = useImperial ? hour.tempF : hour.tempC
  if (v === undefined || v === null || v === "") return ""
  return v + "°"
}

function dayIcon(day) {
  if (!day) return ""
  if (day.openMeteoWeatherCode !== undefined && day.openMeteoWeatherCode !== null)
    return iconForOpenMeteoCode(day.openMeteoWeatherCode)
  if (!day.hourly || day.hourly.length === 0) return ""

  var best = day.hourly[0]
  var bestDist = 9999
  for (var i = 0; i < day.hourly.length; ++i) {
    var t = parseInt(String(day.hourly[i].time || "0"), 10)
    var dist = Math.abs(t - 1200)
    if (dist < bestDist) {
      bestDist = dist
      best = day.hourly[i]
    }
  }
  return iconForCode(best.weatherCode, false)
}

function iconForOpenMeteoCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  if (c === 0) return iconForCode(113, night)
  if (c === 1 || c === 2) return iconForCode(116, night)
  if (c === 3) return iconForCode(119, night)
  if (c === 45 || c === 48) return iconForCode(143, night)
  if (c === 51 || c === 53 || c === 55 || c === 56 || c === 57 || c === 61) return iconForCode(266, night)
  if (c === 63 || c === 65 || c === 66 || c === 67 || c === 80 || c === 81 || c === 82) return iconForCode(308, night)
  if (c === 71 || c === 73 || c === 75 || c === 77 || c === 85 || c === 86) return iconForCode(338, night)
  if (c === 95 || c === 96 || c === 99) return iconForCode(389, night)
  return iconForCode(119, night)
}

function iconForCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  switch (c) {
    case 113: return night ? "" : ""
    case 116: return night ? "" : ""
    case 119: case 122: return ""
    case 143: case 248: case 260: return night ? "\ue346" : "\ue313"
    case 176: case 263: case 353: return night ? "" : ""
    case 179: case 227: case 230: case 323: case 326: case 368: return night ? "" : ""
    case 182: case 185: case 281: case 284: case 311: case 314:
    case 317: case 320: case 350: case 362: case 365: case 374: case 377: return ""
    case 200: case 386: case 389: case 392: case 395: return ""
    case 266: case 293: case 296: case 299: case 302: case 305: case 308: case 356: case 359: return ""
    case 329: case 332: case 335: case 338: case 371: return ""
    default: return ""
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseLocationFile: parseLocationFile,
    wttrLocationQuery: wttrLocationQuery,
    parseGeocodingResults: parseGeocodingResults,
    locationCommit: locationCommit,
    isFutureForecastDate: isFutureForecastDate,
    roundedTemp: roundedTemp,
    celsiusToFahrenheit: celsiusToFahrenheit,
    formatTemp: formatTemp,
    parseHomeAssistantTemperature: parseHomeAssistantTemperature,
    homeAssistantTempIsFahrenheit: homeAssistantTempIsFahrenheit,
    formatHomeAssistantTemp: formatHomeAssistantTemp,
    parseHomeAssistantTimestamp: parseHomeAssistantTimestamp,
    formatCountdown: formatCountdown,
    normalizedUnit: normalizedUnit,
    localeUsesImperial: localeUsesImperial,
    countryUsesImperial: countryUsesImperial,
    shouldUseImperial: shouldUseImperial,
    dayName: dayName,
    openMeteoForecastDays: openMeteoForecastDays,
    openMeteoCurrentCondition: openMeteoCurrentCondition,
    isOpenMeteoPrecipitation: isOpenMeteoPrecipitation,
    isWttrPrecipitation: isWttrPrecipitation,
    precipitationAmount: precipitationAmount,
    isPrecipitationPresent: isPrecipitationPresent,
    isPrecipitationForecastToday: isPrecipitationForecastToday,
    shouldShowRadar: shouldShowRadar,
    currentIcon: currentIcon,
    provisionalCurrentIcon: provisionalCurrentIcon,
    weatherResponseCompletesSave: weatherResponseCompletesSave,
    wttrNextForecastDays: wttrNextForecastDays,
    buildForecastDays: buildForecastDays,
    buildHourlyForecast: buildHourlyForecast,
    hourlySlotIcon: hourlySlotIcon,
    bareTempForDay: bareTempForDay,
    bareTempForHour: bareTempForHour,
    dayIcon: dayIcon,
    iconForOpenMeteoCode: iconForOpenMeteoCode,
    iconForCode: iconForCode
  }
}
