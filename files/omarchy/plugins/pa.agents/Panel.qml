import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var providers: usage.enabledProviders

  // Personal display preference, not a data-quality omission: both
  // providers' daily numbers are real, just not something this panel's
  // per-provider section shows. The underlying record keeps recentDays
  // intact for sync/other consumers and for the Expand button's combined
  // trend chart (which ignores this list) — only the stacked section below
  // is skipped.
  readonly property var dailyChartHiddenProviderIds: ["claude", "grok"]
  function dailyChartHidden(providerId) {
    return dailyChartHiddenProviderIds.indexOf(providerId) >= 0
  }

  // Countdowns and "updated" read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  // Every provider is on screen at once now, so the bar icon flags "any
  // subscription is close to its limit" rather than reporting on whichever
  // one happened to be selected.
  readonly property bool alarming: {
    for (var i = 0; i < providers.length; i++) {
      var p = providers[i]
      var headline = bindingWindow(p)
      if (headline && headline.percent >= 0.9) return true
      if (isBalanceAlarming(p.balance || null)) return true
    }
    return false
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function refreshNow() {
    usage.refreshAll(true)
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters and the hero speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title) {
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || "")
    }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  // The window that decides how much room is left — the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  function isBalanceAlarming(balance) {
    return !!balance && balance.funded > 0 && balance.remaining / balance.funded <= 0.1
  }

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    var text = formatMoney(b.spent, b.currency) + " spent of " + formatMoney(b.funded, b.currency) + " funded"
    if (b.estimated) text += " · estimated"
    return text
  }

  // ---------------------------------------------------------------- content

  // The plan you pay for, under the name of the tool it pays for. Limits live
  // in their own section; the hero just says what this is.
  function heroMeta(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    var tier = String(p.tierLabel || "")
    if (tier === "") return "Subscription"
    return tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    return dayName(date)
  }

  function dayTooltip(day, today, p) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    // Prompt and session counts only exist for today, so they ride along here
    // instead of taking a section of their own. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (today && p && p.hasPromptStats !== false)
      text += " · " + Number(p.todayPrompts || 0) + " prompts · "
        + Number(p.todaySessions || 0) + " sessions"
    return text
  }

  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  function modelRows(p) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      rows.push({
        name: usage.friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function modelTooltip(row) {
    if (!row) return ""
    // The dashboard's "today" tab only has a per-model token total (see
    // dashboardTodayModelRows) — no input/output/cache split exists yet for
    // today, so a fabricated all-zero breakdown would just be misleading.
    if (row.hasBreakdown === false) return usage.formatTokenCount(row.total) + " tokens"
    return "In " + usage.formatTokenCount(row.input)
      + " · out " + usage.formatTokenCount(row.output)
      + " · cache read " + usage.formatTokenCount(row.cacheRead)
      + " · cache write " + usage.formatTokenCount(row.cacheWrite)
  }

  // ------------------------------------------------------------ dashboard
  //
  // The expand button swaps the stacked per-provider sections for one wider
  // view: a combined total across every subscription, a Today/7d range, a
  // day-by-day trend, and a merged model breakdown. No per-provider tab —
  // each subscription's own numbers are already one scroll away in the
  // stacked sections above; the one thing those can't show is the combined
  // total, so that's the only thing this adds. Reads the same records the
  // stacked sections already use: no new collectors, no schema change, and
  // no 30d/90d/Year because recentDays only ever carries the last 7 days.
  property bool expanded: false
  property string dashboardRange: "today"

  function dashboardTodayTotal(list) {
    var total = 0
    for (var i = 0; i < list.length; i++) total += usage.numberValue(list[i].todayTotalTokens)
    return total
  }

  // Merges recentDays across every enabled provider by date. Unlike the
  // stacked view, this does NOT drop dailyChartHidden providers: that
  // preference hides Claude's own day-by-day list there, but this is a
  // combined total, not Claude's chart, and excluding Claude's real numbers
  // would just make the headline read zero on a machine where Claude is the
  // only provider with daily data.
  function dashboardTrendDays(list) {
    var byDate = {}
    var order = []
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      var days = p.recentDays || []
      for (var d = 0; d < days.length; d++) {
        var date = String(days[d].date || "")
        if (date === "") continue
        if (byDate[date] === undefined) { byDate[date] = 0; order.push(date) }
        byDate[date] += usage.numberValue(days[d].messageCount)
      }
    }
    order.sort()
    var out = []
    for (var j = 0; j < order.length; j++) out.push({ date: order[j], messageCount: byDate[order[j]] })
    return out
  }

  function dashboardWeekTotal(days) {
    var total = 0
    for (var i = 0; i < days.length; i++) total += usage.numberValue(days[i].messageCount)
    return total
  }

  // A small fixed categorical palette for telling providers apart in the
  // trend chart. Deliberately independent of the theme's monochrome
  // foreground/accent tokens — a comparison chart needs colors that differ
  // from each other, not colors that match the desktop theme. Qt.rgba (not
  // hex strings) so the result is a real color value: root.alpha() and the
  // Canvas context both need `.r`/`.g`/`.b`, which a plain string lacks.
  readonly property var chartPalette: [
    Qt.rgba(0.37, 0.78, 0.85, 1),
    Qt.rgba(0.91, 0.46, 0.56, 1),
    Qt.rgba(0.91, 0.76, 0.37, 1),
    Qt.rgba(0.56, 0.81, 0.49, 1),
    Qt.rgba(0.73, 0.56, 0.91, 1),
    Qt.rgba(0.91, 0.58, 0.37, 1)
  ]
  function providerColor(index) {
    return chartPalette[index % chartPalette.length]
  }

  // One provider's recentDays remapped onto the combined trend's date list.
  // Dates come from dashboardTrendDays(root.providers), so this fills 0 for
  // any date the provider has no record for rather than assuming its own
  // recentDays already lines up date-for-date with every other provider.
  function dashboardProviderTrend(provider, dates) {
    var byDate = {}
    var days = provider.recentDays || []
    for (var d = 0; d < days.length; d++) byDate[String(days[d].date || "")] = usage.numberValue(days[d].messageCount)
    var values = []
    var hasData = false
    for (var i = 0; i < dates.length; i++) {
      var v = byDate[String(dates[i].date || "")] || 0
      if (v > 0) hasData = true
      values.push(v)
    }
    return { values: values, hasData: hasData }
  }

  function weekPeakFor(days) {
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, usage.numberValue(days[i].messageCount))
    return peak
  }

  // Today's per-model split only exists as a flat token total per model
  // (todayTokensByModel), not the richer input/output/cache buckets — see
  // modelTooltip's hasBreakdown guard above.
  function dashboardTodayModelRows(list) {
    var merged = {}
    for (var i = 0; i < list.length; i++) {
      var byModel = list[i].todayTokensByModel || {}
      for (var id in byModel) merged[id] = (merged[id] || 0) + usage.numberValue(byModel[id])
    }
    var rows = []
    for (var modelId in merged)
      rows.push({ name: usage.friendlyModelName(modelId), total: merged[modelId], hasBreakdown: false })
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function dashboardAllTimeModelRows(list) {
    var merged = {}
    for (var i = 0; i < list.length; i++) {
      var byModel = list[i].modelUsage || {}
      for (var id in byModel) {
        var bucket = merged[id]
        if (!bucket) bucket = merged[id] = usage.emptyTokenBucket()
        var source = byModel[id] || {}
        bucket.inputTokens += usage.numberValue(source.inputTokens)
        bucket.outputTokens += usage.numberValue(source.outputTokens)
        bucket.cacheReadInputTokens += usage.numberValue(source.cacheReadInputTokens)
        bucket.cacheCreationInputTokens += usage.numberValue(source.cacheCreationInputTokens)
      }
    }
    var rows = []
    for (var modelId in merged) {
      var b = merged[modelId]
      rows.push({
        name: usage.friendlyModelName(modelId),
        total: b.inputTokens + b.outputTokens + b.cacheReadInputTokens + b.cacheCreationInputTokens,
        input: b.inputTokens,
        output: b.outputTokens,
        cacheRead: b.cacheReadInputTokens,
        cacheWrite: b.cacheCreationInputTokens
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    return usage.syncStatusText
  }

  // Per-provider sync note: each subscription's own record says whether it
  // merged in other machines' snapshots, so this rides under that provider's
  // section rather than the panel-wide footer.
  function providerFooterText(p) {
    if (!p || !p.syncEnabled || !(p.syncDeviceCount > 0)) return ""
    return "Merged from " + p.syncDeviceCount + " device" + (p.syncDeviceCount === 1 ? "" : "s")
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p) return []
    var candidates = []
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run either CLI.
  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    // Every open starts collapsed: expanded is a look-something-up mode for
    // the session it's opened in, not a state worth remembering into the next.
    expanded = false
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  onExpandedChanged: if (panelFlick) panelFlick.contentY = 0

  Main {
    id: usage
    settings: root.settings
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
    active: root.alarming
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchAgent()
      else if (buttonCode === Qt.MiddleButton) root.refreshNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.expanded ? Style.space(560) : Style.space(380))
    // Taller than the control panels on purpose: this one is a dashboard, and
    // the whole point is reading limits and history without scrolling.
    contentHeight: panel.fittedContentHeight(column.implicitHeight, root.expanded ? Style.space(760) : Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshNow() }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(20)

          Text {
            visible: root.providers.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.providers.length > 0
            width: parent.width
            horizontalAlignment: Text.AlignRight
            text: root.expanded ? "⤡ Collapse" : "⤢ Expand"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.expanded = !root.expanded
            }
          }

          // ---------- One stacked section per subscription ----------
          Column {
            id: stackedSections
            visible: !root.expanded
            width: column.width
            spacing: Style.space(20)

            Repeater {
              model: root.providers

              ProviderSection {
                required property var modelData
                required property int index

                width: stackedSections.width
                provider: modelData
                first: index === 0
              }
            }
          }

          Dashboard {
            visible: root.expanded
            width: column.width
          }

          Text {
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // Everything the panel shows for one subscription: mark, plan, limits or
  // balance, the daily chart, and the model breakdown. Stacking one of these
  // per provider is what replaced the old tab switcher — every agent is on
  // screen at once instead of one at a time behind a click.
  component ProviderSection: Column {
    id: section
    property var provider: null
    property bool first: false

    readonly property var limits: root.limitWindows(provider)
    readonly property var models: root.modelRows(provider)
    readonly property var balance: provider ? (provider.balance || null) : null
    readonly property bool balanceAlarming: root.isBalanceAlarming(balance)
    readonly property var days: provider ? (provider.recentDays || []) : []
    readonly property real peak: Math.max(1, root.weekPeak(provider))
    readonly property string syncNote: root.providerFooterText(provider)

    width: parent.width
    spacing: Style.space(12)

    PanelSeparator {
      visible: !section.first
      foreground: root.foreground
    }

    // ---------- Hero: provider mark · name · plan ----------
    PanelHero {
      width: parent.width
      title: section.provider ? section.provider.providerName : ""
      meta: root.heroMeta(section.provider)
      foreground: root.foreground
      fontFamily: root.fontFamily

      iconComponent: Component {
        Item {
          id: heroMark
          property var candidates: root.iconCandidatesForProvider(section.provider, root.surface)
          // Provider objects are rebuilt on every refresh, which churns the
          // array's identity without changing its content. Restart the fallback
          // walk only when the URLs change: re-pointing source at a URL whose
          // load already failed emits no statusChanged, so an identity-only
          // reset would strand the walker on a missing -light twin.
          property string candidatesKey: candidates.join("\n")
          property int candidateIndex: 0
          onCandidatesKeyChanged: candidateIndex = 0

          width: Style.font.display
          height: Style.font.display

          Image {
            id: heroMarkImage
            anchors.fill: parent
            source: heroMark.candidateIndex < heroMark.candidates.length ? heroMark.candidates[heroMark.candidateIndex] : ""
            sourceSize.width: Style.font.display * 2
            sourceSize.height: Style.font.display * 2
            fillMode: Image.PreserveAspectFit
            // Advancing source from inside its own status change trips the
            // binding-loop detector; defer the step one tick.
            onStatusChanged: if (status === Image.Error && heroMark.candidateIndex < heroMark.candidates.length)
              Qt.callLater(function() { heroMark.candidateIndex++ })
          }

          Text {
            anchors.centerIn: parent
            visible: heroMarkImage.status !== Image.Ready
            text: button.text
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
          }
        }
      }
    }

    // ---------- Status ----------
    BorderSurface {
      visible: !!section.provider && String(section.provider.usageStatusText || "") !== ""
      width: parent.width
      implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
      color: root.alpha(root.urgent, 0.10)
      borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
      radius: Style.cornerRadius

      Text {
        id: statusText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        text: section.provider ? String(section.provider.authHelpText || "") : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }

    // ---------- Balance / limits ----------
    PanelSeparator {
      visible: balanceSection.visible || limitsSection.visible
      foreground: root.foreground
    }

    Column {
      id: balanceSection
      visible: !!section.balance
      width: parent.width
      spacing: Style.space(10)

      // The meter shows what is left, not what is used: a prepaid
      // account drains toward empty rather than filling toward a cap.
      readonly property real ratio: section.balance && section.balance.funded > 0
        ? root.clamp(section.balance.remaining / section.balance.funded, 0, 1)
        : -1

      PanelSectionHeader {
        width: parent.width
        text: "BALANCE"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Item {
        width: parent.width
        implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)

        Text {
          id: balanceLabel
          text: "Prepaid credits"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          id: balanceValue
          text: section.balance ? root.formatMoney(section.balance.remaining, section.balance.currency) : ""
          color: section.balanceAlarming ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Meter {
        visible: balanceSection.ratio >= 0
        width: parent.width
        value: balanceSection.ratio
        alarming: section.balanceAlarming
      }

      Text {
        visible: text !== ""
        width: parent.width
        text: root.balanceDetailText(section.balance)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      id: limitsSection
      visible: section.limits.length > 0
      width: parent.width
      spacing: Style.space(10)

      PanelSectionHeader {
        text: "LIMITS"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: section.limits

        LimitRow {
          required property var modelData
          width: limitsSection.width
          window: modelData
        }
      }
    }

    // ---------- Usage ----------
    PanelSeparator {
      visible: usageSection.visible
      foreground: root.foreground
    }

    Column {
      id: usageSection
      visible: section.days.length > 0
        && !root.dailyChartHidden(section.provider ? section.provider.providerId : "")
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader {
        width: parent.width
        text: "TOKENS BY DAY"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: section.days

        DayRow {
          required property var modelData
          required property int index

          width: usageSection.width
          day: modelData
          ratio: Number(modelData.messageCount || 0) / section.peak
          // By date, not by position: the Claude stats-cache fallback can
          // hand us a window that stops short of today.
          today: String(modelData.date || "") === root.todayDate()
          provider: section.provider
        }
      }
    }

    // ---------- Models ----------
    PanelSeparator {
      visible: modelSection.visible
      foreground: root.foreground
    }

    Column {
      id: modelSection
      visible: section.models.length > 0
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader {
        width: parent.width
        text: "TOKENS BY MODEL"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: section.models

        ModelRow {
          required property var modelData
          width: modelSection.width
          row: modelData
          // Scaled to the heaviest model, so the top row is always full —
          // the same scale-to-peak the weekly chart uses for its busiest day.
          share: modelData.total / Math.max(1, section.models[0].total)
        }
      }
    }

    Text {
      visible: text !== ""
      width: parent.width
      text: section.syncNote
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
    }
  }

  // A limit window: label and percentage, meter, and reset countdown.
  component LimitRow: Column {
    id: limitRow
    property var window: null

    readonly property bool alarming: window && window.percent >= 0.9

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        // A model-scoped window is titled after its model, and those names run
        // long enough to reach the percentage, so the title gives way first.
        text: limitRow.window ? limitRow.window.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: limitValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: limitValue
        text: limitRow.window && limitRow.window.percent >= 0
          ? Math.round(limitRow.window.percent * 100) + "%"
          : "—"
        color: limitRow.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: limitRow.window ? limitRow.window.percent : -1
      alarming: limitRow.alarming
    }

    Text {
      id: resetText
      width: parent.width
      text: {
        var remainingMs = root.resetMsFor(limitRow.window)
        return remainingMs > 0 ? "Resets in " + root.formatDuration(remainingMs) : ""
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Rounded track showing the percentage of the allowance used.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

  }

  // One row per day: label, bar, tokens. Today is picked out in full
  // foreground so the week reads as a run-up to right now.
  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false
    property var provider: null

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: dayValue
      text: usage.formatTokenCount(dayRow.day ? Number(dayRow.day.messageCount || 0) : 0)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day, dayRow.today, dayRow.provider)
      fontFamily: root.fontFamily
    }
  }

  // Model rows read as a table: the share bar fills the row behind the label
  // instead of stacking under it, which keeps the whole dashboard on one screen.
  component ModelRow: Item {
    id: modelRow
    property var row: null
    property real share: 0

    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: modelName
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: modelTokens
      text: modelRow.row ? usage.formatTokenCount(modelRow.row.total) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse
      text: root.modelTooltip(modelRow.row)
      fontFamily: root.fontFamily
    }
  }

  // The expanded view behind the "Expand" toggle: a tab per provider (plus
  // a combined total across every subscription), a Today/7d range, a
  // headline total, a day-by-day trend, and a merged model breakdown. Same
  // vocabulary as the stacked sections (Meter, ModelRow, day bars) so it
  // doesn't read as a bolted-on screen.
  component Dashboard: Column {
    id: dashboard
    spacing: Style.space(14)

    readonly property bool isToday: root.dashboardRange === "today"
    readonly property var trendDays: root.dashboardTrendDays(root.providers)
    readonly property real trendPeak: Math.max(1, root.weekPeakFor(dashboard.trendDays))
    readonly property var modelRows: dashboard.isToday
      ? root.dashboardTodayModelRows(root.providers)
      : root.dashboardAllTimeModelRows(root.providers)

    // ---------- Range: Today or 7d (recentDays never carries more) ----------
    Row {
      spacing: Style.space(12)

      Repeater {
        model: [{ id: "today", label: "Today" }, { id: "week", label: "7d" }]

        Text {
          required property var modelData
          text: modelData.label
          color: modelData.id === root.dashboardRange ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: modelData.id === root.dashboardRange

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.dashboardRange = modelData.id
          }
        }
      }
    }

    // ---------- Headline total ----------
    Column {
      width: parent.width
      spacing: Style.space(4)

      PanelSectionHeader {
        width: parent.width
        text: dashboard.isToday ? "TOKENS TODAY" : "TOKENS THIS WEEK"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        text: usage.formatTokenCount(dashboard.isToday
          ? root.dashboardTodayTotal(root.providers)
          : root.dashboardWeekTotal(dashboard.trendDays))
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }
    }

    // ---------- Trend: bars for each day's magnitude, plus a line tracing
    // the week so the run-up to today reads at a glance the way the
    // reference dashboard's graph does — additive, not a replacement.
    Column {
      visible: !dashboard.isToday && dashboard.trendDays.length > 0
      width: parent.width
      spacing: Style.space(8)

      PanelSectionHeader {
        width: parent.width
        text: "TOKENS BY DAY"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Item {
        id: trendChart
        width: parent.width
        height: Style.space(96)

        readonly property int count: dashboard.trendDays.length
        readonly property real colWidth: (width - Math.max(0, count - 1) * Style.space(10)) / Math.max(1, count)
        function colCenterX(i) { return i * (colWidth + Style.space(10)) + colWidth / 2 }

        Row {
          anchors.fill: parent
          spacing: Style.space(10)

          Repeater {
            model: dashboard.trendDays

            Item {
              required property var modelData
              readonly property bool today: String(modelData.date || "") === root.todayDate()

              width: trendChart.colWidth
              height: parent.height

              Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(Style.space(6), parent.width * 0.5)
                height: Math.max(2, parent.height * root.clamp(Number(modelData.messageCount || 0) / dashboard.trendPeak, 0, 1))
                radius: Style.cornerRadius
                color: today ? root.foreground : root.alpha(root.foreground, 0.55)

                Behavior on height {
                  NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
              }
            }
          }
        }

        // One colored line per provider on top of the bars, so the combined
        // total (the bars) and each subscription's share of it (the lines)
        // read at the same time — the comparison the reference dashboard's
        // multi-line chart makes. Qt Quick has no chart widget, so this
        // draws it directly.
        Canvas {
          id: trendCanvas
          anchors.fill: parent
          property var dates: dashboard.trendDays
          property var providers: root.providers
          property real peak: dashboard.trendPeak
          onDatesChanged: requestPaint()
          onProvidersChanged: requestPaint()
          onPeakChanged: requestPaint()
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          Component.onCompleted: requestPaint()

          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var dates = trendCanvas.dates
            var n = dates ? dates.length : 0
            if (n === 0) return
            var providers = trendCanvas.providers || []
            for (var p = 0; p < providers.length; p++) {
              var trend = root.dashboardProviderTrend(providers[p], dates)
              if (!trend.hasData) continue
              var pts = []
              for (var i = 0; i < n; i++) {
                var ratio = root.clamp(trend.values[i] / trendCanvas.peak, 0, 1)
                pts.push(Qt.point(trendChart.colCenterX(i), height - ratio * height))
              }
              var color = root.providerColor(p)
              ctx.beginPath()
              ctx.moveTo(pts[0].x, pts[0].y)
              for (i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y)
              ctx.strokeStyle = color
              ctx.lineWidth = 2
              ctx.lineJoin = "round"
              ctx.lineCap = "round"
              ctx.stroke()
              for (i = 0; i < pts.length; i++) {
                ctx.beginPath()
                ctx.arc(pts[i].x, pts[i].y, 3, 0, Math.PI * 2)
                ctx.fillStyle = color
                ctx.fill()
              }
            }
          }
        }
      }

      // ---------- Legend: one swatch per line actually drawn above ----------
      Row {
        width: parent.width
        spacing: Style.space(14)

        Repeater {
          model: root.providers

          Row {
            required property var modelData
            required property int index
            readonly property bool hasData: root.dashboardProviderTrend(modelData, dashboard.trendDays).hasData

            visible: hasData
            spacing: Style.space(6)

            Rectangle {
              width: Style.space(8)
              height: Style.space(8)
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: root.providerColor(index)
            }

            Text {
              text: modelData.providerName
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(10)

        Repeater {
          model: dashboard.trendDays

          Text {
            required property var modelData
            readonly property bool today: String(modelData.date || "") === root.todayDate()

            width: trendChart.colWidth
            text: root.dayLabel(modelData.date, today)
            color: today ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: today
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }

    // ---------- Models ----------
    Column {
      visible: dashboard.modelRows.length > 0
      width: parent.width
      spacing: Style.spacing.md

      PanelSectionHeader {
        width: parent.width
        text: dashboard.isToday ? "TODAY BY MODEL" : "TOKENS BY MODEL"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Repeater {
        model: dashboard.modelRows

        ModelRow {
          required property var modelData
          width: parent.width
          row: modelData
          share: modelData.total / Math.max(1, dashboard.modelRows[0].total)
        }
      }
    }

  }
}
