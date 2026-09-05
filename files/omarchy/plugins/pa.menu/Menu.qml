import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel

Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Plugin lifecycle hooks. The host calls open(payloadJson) after
  // `omarchy-shell shell summon omarchy.menu ...` and close() when hidden.
  property string pendingInitialMenu: "root"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    if (payload.mode === "select" || payload.mode === "input") {
      root.openDmenu(payload)
    } else {
      root.openRoute(payload.initialMenu || payload.menu || "root")
    }
  }

  function close() {
    root.cancel()
  }

  function refresh() {
    defaultMenuFile.reload()
    userMenuFile.reload()
    return "ok"
  }

  function ping() { return "ok" }

  property string fontFamily: Style.font.menuFamily
  // JSONC menu definitions. The shell parses both at startup and merges
  // the user file on top of the defaults, so the keybind → IPC → visible
  // path doesn't have to shell out to bash + jq on every open.
  property string defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  property var defaultMenuItems: []
  property var userMenuItems: []
  property bool opened: false
  property string mode: "menu"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string dmenuPrompt: ""
  property var dmenuOptions: []
  property string selectionFile: ""
  property string doneFile: ""
  property int dmenuWidth: 300
  property int dmenuMaxHeight: 0
  property bool requestActive: false
  property bool rowsLoaded: false
  property string activeMenu: "root"
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property int requestSerial: 0
  property int applySerial: 0
  property var items: ({})
  property var itemOrder: []
  property var navStack: []
  property var providersLoaded: ({})
  property var providerQueue: []
  property int providerRevision: 0

  // Shared application engine (entries, hidden filters, icons, launch,
  // removal), owned by the shell and also used by the standalone launcher.
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  onOpenedChanged: if (!opened) { deleteConfirmOpen = false; deleteTarget = null }
  // Zone list from timedatectl, offsets from `date +%z`. Cached so typing
  // "time in tokyo" does not fork on every extra letter.
  property var timeZones: []
  property bool timeZonesLoaded: false
  property var zoneOffsets: ({})
  // Bound to the central [menu] section in shell.toml via Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  readonly property real rowReservedBorderRight: Border.right(selectedBorderSpec)
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int baseRowHeight: Math.max(Style.space(50), Style.font.body + Style.spacing.rowPaddingX * 2)
  property int detailRowHeight: Math.max(Style.space(58), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  // How much of the first hidden row stays visible at the fold — enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(baseRowHeight * 0.55)
  property int rowSpacing: Style.spacing.xs
  property int dividerHeight: Style.space(17)
  property bool searchDivider: false
  property int layoutSerial: 0
  property int cardWidth: Math.min(root.dmenuActive ? Style.space(root.dmenuWidth) : ((root.activeMenu === "trigger.capture.screenrecord" || root.activeMenu === "style.font") ? Style.space(520) : Style.space(300)), panel.width - Style.gapsOut * 2)
  property int visibleRowsHeight: root.dmenuActive ? dmenuRowListHeight(layoutSerial, displayModel.count, filterText) : rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
  property int cardHeight: root.dmenuActive
    ? Math.min(contentMargin * 2 + headerHeight + (mode === "input" ? 0 : contentSpacing + visibleRowsHeight), panel.height - Style.gapsOut * 2)
    : Math.min(contentMargin * 2 + headerHeight + contentSpacing + visibleRowsHeight, panel.height - Style.gapsOut * 2)

  function finishRequest(selection) {
    if (!root.requestActive || !root.doneFile) {
      root.opened = false
      return
    }

    var activeSelectionFile = root.selectionFile
    var activeDoneFile = root.doneFile
    root.requestActive = false
    root.selectionFile = ""
    root.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    } else {
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    }
    resultProc.running = true
  }

  function runAction(action) {
    var command = String(action || "")
    if (!command) return

    Util.execDetached(command)
  }

  // Menu rows only surface their detail while a search is narrowing them;
  // dmenu rows carry caller-supplied subtext that must always be visible.
  function rowHeightForDetail(detail) {
    return (root.filterText || root.dmenuActive) && detail ? root.detailRowHeight : root.baseRowHeight
  }

  // Height the card can devote to rows before running off the screen — or
  // past the frozen top edge once a search has pinned the card in place.
  // Uses panel.cardTop rather than effectiveCardTop: the centered top is
  // derived from the card height, which this value feeds.
  function availableRowsHeight() {
    var top = panel.cardTop >= 0 ? panel.cardTop : Style.gapsOut
    var available = panel.height - top - Style.gapsOut - root.contentMargin * 2 - root.headerHeight - root.contentSpacing
    // The starting menu sets the ceiling along with the offset: drilling into
    // a longer submenu scrolls behind the fold instead of growing the card.
    if (panel.maxRowsHeight >= 0) available = Math.min(available, panel.maxRowsHeight)
    // A card that swallows the whole screen reads as a page, not a menu.
    return Math.min(available, Math.round(panel.height * 0.7))
  }

  // When every row fits, the list gets its full height. When they don't,
  // the card must end mid-row: a clipped row is what tells the eye there is
  // more below the fold, so never come out even on a row boundary.
  function foldedListHeight(totals, available) {
    var count = totals.length
    if (count === 0) return root.baseRowHeight
    if (totals[count - 1] <= available) return totals[count - 1]

    var peek = root.rowPeek
    var full = 0
    while (full < count && totals[full] <= available) full++
    while (full > 1 && totals[full - 1] + root.rowSpacing + peek > available) full--
    if (full < 1) return Math.max(available, root.baseRowHeight)

    return totals[full - 1] + root.rowSpacing + peek
  }

  function rowListHeight(_serial, _count, _filter, _divider) {
    if (displayModel.count === 0) return root.baseRowHeight

    var totals = []
    var total = 0
    var previousSection = ""

    for (var i = 0; i < displayModel.count; i++) {
      var row = displayModel.get(i)
      if (i > 0) total += root.rowSpacing
      if (row.section === "drilldown" && previousSection !== "drilldown") total += root.dividerHeight
      total += root.rowHeightForDetail(row.detail)
      previousSection = row.section
      totals.push(total)
    }

    return foldedListHeight(totals, availableRowsHeight())
  }

  function dmenuRowListHeight(_serial, _count, _filter) {
    if (root.mode === "input") return 0
    if (displayModel.count === 0) return root.baseRowHeight

    var available = availableRowsHeight()
    if (root.dmenuMaxHeight > 0) available = Math.min(available, Style.space(root.dmenuMaxHeight))

    var totals = []
    var total = 0
    for (var i = 0; i < displayModel.count; i++) {
      if (i > 0) total += root.rowSpacing
      total += root.rowHeightForDetail(displayModel.get(i).detail)
      totals.push(total)
    }

    return foldedListHeight(totals, available)
  }

  function item(id) {
    return root.items[id] || null
  }

  // ------------------------------------------------------------------
  // JSONC → normalized item array. Mirrors the bash bin's jq pipeline so
  // the on-disk authoring format stays untouched.
  // ------------------------------------------------------------------

  function stripJsonc(raw) {
    return MenuModel.stripJsonc(raw)
  }

  function normalizeAliases(value) {
    return MenuModel.normalizeAliases(value)
  }

  function normalizeItem(id, raw) {
    return MenuModel.normalizeItem(id, raw)
  }

  function parseMenuJsonc(raw) {
    return MenuModel.parseMenuJsonc(raw)
  }

  // Merge defaults + user extension. Later entries override earlier ones
  // on a per-key basis (so the user can tweak label/icon/action without
  // re-declaring the whole row).
  function rebuildItemsFromSources() {
    var mergedMenu = MenuModel.mergeMenuSources(root.defaultMenuItems, root.userMenuItems)
    root.providerRevision += 1
    root.providersLoaded = ({})
    root.providerQueue = []
    root.items = mergedMenu.items
    root.itemOrder = mergedMenu.itemOrder
    root.rowsLoaded = true
    root.evaluateGuards()
    if (root.opened) {
      root.rebuildDisplay()
      if (!root.dmenuActive) {
        if (root.filterText.trim()) root.loadProvidersForSearch()
        else root.loadProviderForMenu(root.activeMenu)
      }
    }
  }

  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it.
  readonly property var providers: ({
    "fonts": {
      script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
      icon: "",
      volatile: true,
      actionFor: function(value) { return "omarchy-font-set " + Util.shellQuote(value) }
    },
    "power-profiles": {
      script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
      icon: "\udb81\udc0b",
      actionFor: function(value) { return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value) }
    }
  })

  function slugify(value) {
    return MenuModel.slugify(value)
  }

  // The apps provider is QML-native: rows come from the shared AppLibrary
  // (DesktopEntries) instead of a bash enumeration, so they carry image
  // icons, launch feedback, and uninstall support like the launcher.
  function mergeAppRows() {
    if (!root.appLibrary) return

    var rows = root.appLibrary.sortedEntries("")
    var appRows = []
    for (var j = 0; j < rows.length; j++) {
      var entry = rows[j].entry
      var appId = String(entry.id || "")
      if (!appId) continue
      var subtext = root.appLibrary.entrySubtext(entry)
      var aliases = subtext ? [subtext] : []
      try {
        if (entry.keywords && typeof entry.keywords.join === "function") aliases = aliases.concat(entry.keywords)
      } catch (e) { }
      appRows.push({
        id: "apps." + appId,
        parent: "apps",
        kind: "app",
        icon: "",
        appIcon: String(entry.icon || ""),
        appId: appId,
        label: root.appLibrary.entryName(entry),
        title: "",
        target: "",
        description: subtext,
        action: "",
        provider: "",
        aliases: aliases,
        when: "",
        checked: "",
        order: 0
      })
    }

    var merged = MenuModel.mergeAppRows(root.items, root.itemOrder, appRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return
    if (entry.provider === "apps") {
      root.providersLoaded[id] = true
      root.mergeAppRows()
      return
    }
    var spec = root.providers[entry.provider]
    if (!spec) return

    root.providersLoaded[id] = true
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = root.providerRevision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  function mergeProviderRows(rows, menuId, providerKey) {
    var spec = root.providers[providerKey]
    if (!spec) return
    var lines = String(rows || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line) continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label) continue
      // Distinct values can slugify alike — Fira Code and Fira-Code both give
      // fira-code — and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + root.slugify(value)
      while (takenIds[rowId]) rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        order: 0
      })
    }
    var merged = MenuModel.swapProviderRows(root.items, root.itemOrder, menuId, providerRows)
    root.items = merged.items
    root.itemOrder = merged.itemOrder
    if (root.opened) root.rebuildDisplay()
  }

  function startNextProvider() {
    if (providerProc.running) return

    while (root.providerQueue.length > 0) {
      var id = root.providerQueue.shift()
      var entry = root.item(id)
      if (!entry || !entry.provider || root.providersLoaded[id]) continue

      root.startProviderForMenu(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatileProvider(id) {
    var entry = root.item(id)
    var spec = entry && entry.provider ? root.providers[entry.provider] : null
    if (spec && spec.volatile) root.providersLoaded[id] = false
  }

  function loadProviderForMenu(id) {
    var entry = root.item(id)
    if (!entry || !entry.provider || root.providersLoaded[id]) return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      root.startProviderForMenu(id)
      return
    }

    if (providerProc.running) {
      if (root.providerQueue.indexOf(id) < 0) root.providerQueue = root.providerQueue.concat([id])
      return
    }

    root.startProviderForMenu(id)
  }

  function loadProvidersForSearch() {
    var active = root.item(root.activeMenu) ? root.activeMenu : "root"

    for (var i = 0; i < root.itemOrder.length; i++) {
      var entry = root.item(root.itemOrder[i])
      if (!entry || !entry.provider || root.providersLoaded[entry.id]) continue
      if (active !== "root" && entry.id !== active && !root.isDescendantOf(entry.id, active)) continue

      root.loadProviderForMenu(entry.id)
    }
  }

  function depthFor(id) {
    return MenuModel.depthFor(root.items, id)
  }

  function pathFor(id) {
    return MenuModel.pathFor(root.items, id)
  }

  function parentPathFor(id) {
    return MenuModel.parentPathFor(root.items, id)
  }

  function isDescendantOf(id, ancestorId) {
    return MenuModel.isDescendantOf(root.items, id, ancestorId)
  }

  function childCount(id) {
    return MenuModel.childCount(root.items, root.itemOrder, id)
  }

  // Guarded items are hidden when their `when:` evaluates false. Static
  // submenus are also hidden when none of their descendants are visible;
  // provider-backed menus stay visible because their rows load on demand.
  function isVisible(entry) {
    return MenuModel.isVisible(root.items, root.itemOrder, root.whenResults, entry)
  }

  // Label with the ✓ marker baked in when `checked:` evaluated truthy.
  function labelFor(entry) {
    return MenuModel.labelFor(entry, root.checkedResults)
  }

  function searchableToken(value) {
    return MenuModel.searchableToken(value)
  }

  function leafIdFor(id) {
    return MenuModel.leafIdFor(id)
  }

  function nameSearchText(entry) {
    return MenuModel.nameSearchText(entry)
  }

  function termInSearchWords(term, text) {
    return MenuModel.termInSearchWords(term, text)
  }

  function descriptionTextMatches(query, text) {
    return MenuModel.descriptionTextMatches(query, text)
  }

  function matchesQuery(entry, query) {
    return MenuModel.matchesQuery(entry, query, root.isVisible(entry))
  }

  function searchScore(entry, query) {
    return MenuModel.searchScore(root.items, entry, query)
  }

  // Safely evaluate a math expression typed into the search box. Only digits,
  // spaces, decimal points, and + - * / % ( ) pass the whitelist, so the input
  // can never escape into code. Uses a small recursive-descent parser rather
  // than eval/Function, which Qt's QML JS engine does not reliably support.
  // Returns a formatted result or "" when the text is not a complete
  // calculation.
  function calcResult(input) {
    var text = String(input || "").trim()
    if (!text || text.length > 200) return ""

    // Constants and the sqrt shorthand are substituted before the whitelist so
    // the letters never reach it. π/pi -> pi value, sqrt -> √.
    text = text.replace(/π/g, " 3.141592653589793 ")
    text = text.replace(/(^|[^a-z0-9])pi([^a-z0-9]|$)/gi, "$1 3.141592653589793 $2")
    text = text.replace(/sqrt/gi, "√")

    if (!/^[0-9+\-*/().% \^π√!]+$/.test(text)) return ""
    // A trailing % (at the end or before an operator) means "divide by 100";
    // between two numbers it stays the modulo operator.
    text = text.replace(/%(?=\s*(?:[+\-*/^)!]|$))/g, "/100")
    if (!/[+\-*/%\^√!]/.test(text)) return ""

    var tokens = []
    var i = 0
    var n = text.length
    while (i < n) {
      var ch = text.charAt(i)
      if (ch === " ") { i++; continue }
      if ("+-*/%()^√!".indexOf(ch) >= 0) { tokens.push({ t: "op", v: ch }); i++; continue }
      var num = ""
      while (i < n && "0123456789.".indexOf(text.charAt(i)) >= 0) { num += text.charAt(i); i++ }
      if (!num) return ""
      tokens.push({ t: "num", v: parseFloat(num) })
    }

    var pos = 0
    function peek() { return pos < tokens.length ? tokens[pos] : null }
    function take() { return pos < tokens.length ? tokens[pos++] : null }

    function parseExpr() {
      var v = parseTerm()
      for (;;) {
        var op = peek()
        if (op && op.t === "op" && (op.v === "+" || op.v === "-")) {
          take()
          var r = parseTerm()
          v = op.v === "+" ? v + r : v - r
        } else break
      }
      return v
    }

    function parseTerm() {
      var v = parsePower()
      for (;;) {
        var op = peek()
        if (op && op.t === "op" && (op.v === "*" || op.v === "/" || op.v === "%")) {
          take()
          var r = parsePower()
          if (op.v === "*") v = v * r
          else if (op.v === "/") v = v / r
          else v = v % r
        } else break
      }
      return v
    }

    // Exponentiation binds tighter than * / and is right-associative: 2^3^2 = 2^9.
    function parsePower() {
      var v = parseFactor()
      var op = peek()
      if (op && op.t === "op" && op.v === "^") {
        take()
        v = Math.pow(v, parsePower())
      }
      return v
    }

    function parseFactor() {
      var op = peek()
      if (op && op.t === "op" && op.v === "-") { take(); return -parseFactor() }
      if (op && op.t === "op" && op.v === "+") { take(); return parseFactor() }
      if (op && op.t === "op" && op.v === "√") { take(); return Math.sqrt(parseFactor()) }
      var value
      if (op && op.t === "op" && op.v === "(") {
        take()
        value = parseExpr()
        var close = take()
        if (!close || close.t !== "op" || close.v !== ")") throw new Error("mismatch")
      } else {
        var tok = take()
        if (!tok || tok.t !== "num") throw new Error("expected number")
        value = tok.v
      }
      // Postfix factorial: 5! = 120.
      var fac = peek()
      if (fac && fac.t === "op" && fac.v === "!") {
        take()
        if (value < 0 || Math.floor(value) !== value) throw new Error("bad factorial")
        var f = 1
        for (var fk = 2; fk <= value; fk++) f *= fk
        value = f
      }
      return value
    }

    var value
    try {
      value = parseExpr()
      if (peek() !== null) return ""
    } catch (e) {
      return ""
    }
    if (typeof value !== "number" || !isFinite(value)) return ""
    return root.formatNumber(value)
  }

  // ------------------------------------------------- unit & time conversion
  //
  // Queries like "10 km to miles", "5ft in cm", "2 hours to minutes", or
  // "100°f to c" get a conversion row. Each unit maps to its base-unit factor
  // per category; temperature uses its own formulas. Pure arithmetic still
  // falls through to calcResult().

  // category -> [name, factor-of-base]. Temperature has no factor; convertTemp
  // handles it. Keys are lowercase and stripped of any "°" before lookup.
  readonly property var unitTable: ({
    // length (base: metre)
    "mm": ["length", 0.001], "millimeter": ["length", 0.001], "millimeters": ["length", 0.001], "millimetre": ["length", 0.001],
    "cm": ["length", 0.01], "centimeter": ["length", 0.01], "centimeters": ["length", 0.01],
    "m": ["length", 1], "meter": ["length", 1], "meters": ["length", 1], "metre": ["length", 1], "metres": ["length", 1],
    "km": ["length", 1000], "kilometer": ["length", 1000], "kilometers": ["length", 1000],
    "in": ["length", 0.0254], "inch": ["length", 0.0254], "inches": ["length", 0.0254],
    "ft": ["length", 0.3048], "foot": ["length", 0.3048], "feet": ["length", 0.3048],
    "yd": ["length", 0.9144], "yard": ["length", 0.9144], "yards": ["length", 0.9144],
    "mi": ["length", 1609.344], "mile": ["length", 1609.344], "miles": ["length", 1609.344],
    "nmi": ["length", 1852], "nautical mile": ["length", 1852], "nautical miles": ["length", 1852],
    "nm": ["length", 1e-9], "nanometer": ["length", 1e-9], "nanometers": ["length", 1e-9], "nanometre": ["length", 1e-9],
    "micron": ["length", 1e-6], "micrometer": ["length", 1e-6], "micrometers": ["length", 1e-6],
    "angstrom": ["length", 1e-10], "angstroms": ["length", 1e-10],
    "mil": ["length", 2.54e-5], "thou": ["length", 2.54e-5],
    "au": ["length", 149597870700], "astronomical unit": ["length", 149597870700],
    "ly": ["length", 9.4607304725808e15], "light-year": ["length", 9.4607304725808e15], "light year": ["length", 9.4607304725808e15], "light years": ["length", 9.4607304725808e15],
    // mass (base: kilogram)
    "mg": ["mass", 1e-6], "milligram": ["mass", 1e-6], "milligrams": ["mass", 1e-6],
    "g": ["mass", 0.001], "gram": ["mass", 0.001], "grams": ["mass", 0.001], "gramme": ["mass", 0.001],
    "kg": ["mass", 1], "kilogram": ["mass", 1], "kilograms": ["mass", 1],
    "t": ["mass", 1000], "tonne": ["mass", 1000], "tonnes": ["mass", 1000], "ton": ["mass", 1000], "tons": ["mass", 1000],
    "oz": ["mass", 0.028349523125], "ounce": ["mass", 0.028349523125], "ounces": ["mass", 0.028349523125],
    "lb": ["mass", 0.45359237], "pound": ["mass", 0.45359237], "pounds": ["mass", 0.45359237],
    "st": ["mass", 6.35029318], "stone": ["mass", 6.35029318], "stones": ["mass", 6.35029318],
    "kt": ["mass", 1000000], "kiloton": ["mass", 1000000], "kilotonne": ["mass", 1000000], "kilotonnes": ["mass", 1000000],
    "mt": ["mass", 1000000000], "megaton": ["mass", 1000000000], "megatonne": ["mass", 1000000000], "megatonnes": ["mass", 1000000000],
    "gt": ["mass", 1000000000000], "gigaton": ["mass", 1000000000000], "gigatonne": ["mass", 1000000000000],
    "lt": ["mass", 1016.0469088], "long ton": ["mass", 1016.0469088], "long tons": ["mass", 1016.0469088],
    "short ton": ["mass", 907.18474], "short tons": ["mass", 907.18474],
    "grain": ["mass", 0.00006479891], "grains": ["mass", 0.00006479891], "gr": ["mass", 0.00006479891],
    "carat": ["mass", 0.0002], "carats": ["mass", 0.0002], "ct": ["mass", 0.0002],
    "slug": ["mass", 14.59390294], "slugs": ["mass", 14.59390294],
    "ozt": ["mass", 0.0311034768], "troy ounce": ["mass", 0.0311034768], "troy ounces": ["mass", 0.0311034768],
    "dram": ["mass", 0.0017718451953125], "drams": ["mass", 0.0017718451953125],
    // volume (base: litre)
    "ml": ["volume", 0.001], "milliliter": ["volume", 0.001], "milliliters": ["volume", 0.001], "millilitre": ["volume", 0.001],
    "cl": ["volume", 0.01], "centiliter": ["volume", 0.01],
    "l": ["volume", 1], "liter": ["volume", 1], "liters": ["volume", 1], "litre": ["volume", 1], "litres": ["volume", 1],
    "fl oz": ["volume", 0.0295735295625], "fluid ounce": ["volume", 0.0295735295625], "fluid ounces": ["volume", 0.0295735295625],
    "cup": ["volume", 0.2365882365], "cups": ["volume", 0.2365882365],
    "pt": ["volume", 0.473176473], "pint": ["volume", 0.473176473], "pints": ["volume", 0.473176473],
    "qt": ["volume", 0.946352946], "quart": ["volume", 0.946352946], "quarts": ["volume", 0.946352946],
    "gal": ["volume", 3.785411784], "gallon": ["volume", 3.785411784], "gallons": ["volume", 3.785411784],
    "tbsp": ["volume", 0.01478676478125], "tablespoon": ["volume", 0.01478676478125], "tablespoons": ["volume", 0.01478676478125],
    "tsp": ["volume", 0.00492892159375], "teaspoon": ["volume", 0.00492892159375], "teaspoons": ["volume", 0.00492892159375],
    "m3": ["volume", 1000], "m³": ["volume", 1000], "cubic meter": ["volume", 1000], "cubic meters": ["volume", 1000], "cubic metre": ["volume", 1000],
    "cm3": ["volume", 0.001], "cm³": ["volume", 0.001],
    "ft3": ["volume", 28.316846592], "ft³": ["volume", 28.316846592], "cubic foot": ["volume", 28.316846592], "cubic feet": ["volume", 28.316846592], "cuft": ["volume", 28.316846592],
    "in3": ["volume", 0.016387064], "in³": ["volume", 0.016387064], "cubic inch": ["volume", 0.016387064], "cubic inches": ["volume", 0.016387064],
    "bbl": ["volume", 158.987294928], "barrel": ["volume", 158.987294928], "barrels": ["volume", 158.987294928],
    // data (base: byte). kb/mb/gb/tb are decimal; KiB/MiB/GiB/TiB are binary.
    "bit": ["data", 0.125], "bits": ["data", 0.125],
    "b": ["data", 1], "byte": ["data", 1], "bytes": ["data", 1],
    "kb": ["data", 1000], "kilobyte": ["data", 1000], "kilobytes": ["data", 1000],
    "mb": ["data", 1000000], "megabyte": ["data", 1000000], "megabytes": ["data", 1000000],
    "gb": ["data", 1000000000], "gigabyte": ["data", 1000000000], "gigabytes": ["data", 1000000000],
    "tb": ["data", 1000000000000], "terabyte": ["data", 1000000000000], "terabytes": ["data", 1000000000000],
    "pb": ["data", 1000000000000000], "petabyte": ["data", 1000000000000000], "petabytes": ["data", 1000000000000000],
    "kbit": ["data", 125], "kilobit": ["data", 125], "kilobits": ["data", 125],
    "mbit": ["data", 125000], "megabit": ["data", 125000], "megabits": ["data", 125000],
    "gbit": ["data", 125000000], "gigabit": ["data", 125000000], "gigabits": ["data", 125000000],
    "tbit": ["data", 125000000000], "terabit": ["data", 125000000000], "terabits": ["data", 125000000000],
    "kib": ["data", 1024], "kibibyte": ["data", 1024],
    "mib": ["data", 1048576], "mebibyte": ["data", 1048576],
    "gib": ["data", 1073741824], "gibibyte": ["data", 1073741824],
    "tib": ["data", 1099511627776], "tibibyte": ["data", 1099511627776],
    "eb": ["data", 1e18], "exabyte": ["data", 1e18], "exabytes": ["data", 1e18],
    "zb": ["data", 1e21], "zettabyte": ["data", 1e21], "zettabytes": ["data", 1e21],
    // time (base: second). month/year are calendar approximations (30d / 365d).
    "ms": ["time", 0.001], "millisecond": ["time", 0.001], "milliseconds": ["time", 0.001],
    "s": ["time", 1], "sec": ["time", 1], "secs": ["time", 1], "second": ["time", 1], "seconds": ["time", 1],
    "min": ["time", 60], "mins": ["time", 60], "minute": ["time", 60], "minutes": ["time", 60],
    "h": ["time", 3600], "hr": ["time", 3600], "hrs": ["time", 3600], "hour": ["time", 3600], "hours": ["time", 3600],
    "d": ["time", 86400], "day": ["time", 86400], "days": ["time", 86400],
    "wk": ["time", 604800], "week": ["time", 604800], "weeks": ["time", 604800],
    "mo": ["time", 2592000], "month": ["time", 2592000], "months": ["time", 2592000],
    "yr": ["time", 31536000], "y": ["time", 31536000], "year": ["time", 31536000], "years": ["time", 31536000],
    "fortnight": ["time", 1209600], "fortnights": ["time", 1209600],
    "decade": ["time", 315360000], "decades": ["time", 315360000],
    "century": ["time", 3153600000], "centuries": ["time", 3153600000],
    "millennium": ["time", 31536000000], "millennia": ["time", 31536000000],
    // speed (base: metre/second)
    "m/s": ["speed", 1], "mps": ["speed", 1],
    "km/h": ["speed", 0.2777777777777778], "kmh": ["speed", 0.2777777777777778], "kph": ["speed", 0.2777777777777778],
    "mph": ["speed", 0.44704],
    "knot": ["speed", 0.5144444444444445], "knots": ["speed", 0.5144444444444445], "kts": ["speed", 0.5144444444444445],
    "ft/s": ["speed", 0.3048], "fps": ["speed", 0.3048],
    // area (base: square metre)
    "m2": ["area", 1], "m²": ["area", 1], "sqm": ["area", 1], "square meter": ["area", 1], "square meters": ["area", 1], "square metre": ["area", 1],
    "km2": ["area", 1e6], "km²": ["area", 1e6], "sqkm": ["area", 1e6], "square kilometer": ["area", 1e6], "square kilometre": ["area", 1e6],
    "cm2": ["area", 1e-4], "cm²": ["area", 1e-4],
    "mm2": ["area", 1e-6], "mm²": ["area", 1e-6],
    "ha": ["area", 10000], "hectare": ["area", 10000], "hectares": ["area", 10000],
    "acre": ["area", 4046.8564224], "acres": ["area", 4046.8564224],
    "ft2": ["area", 0.09290304], "ft²": ["area", 0.09290304], "sqft": ["area", 0.09290304], "square foot": ["area", 0.09290304], "square feet": ["area", 0.09290304],
    "yd2": ["area", 0.83612736], "yd²": ["area", 0.83612736], "sqyd": ["area", 0.83612736], "square yard": ["area", 0.83612736], "square yards": ["area", 0.83612736],
    "in2": ["area", 0.00064516], "in²": ["area", 0.00064516], "sqin": ["area", 0.00064516], "square inch": ["area", 0.00064516],
    "mi2": ["area", 2589988.110336], "mi²": ["area", 2589988.110336], "sqmi": ["area", 2589988.110336], "square mile": ["area", 2589988.110336], "square miles": ["area", 2589988.110336],
    // energy (base: joule)
    "j": ["energy", 1], "joule": ["energy", 1], "joules": ["energy", 1],
    "kj": ["energy", 1000], "kilojoule": ["energy", 1000], "kilojoules": ["energy", 1000],
    "mj": ["energy", 1e6], "megajoule": ["energy", 1e6],
    "gj": ["energy", 1e9], "gigajoule": ["energy", 1e9],
    "cal": ["energy", 4.184], "calorie": ["energy", 4.184], "calories": ["energy", 4.184],
    "kcal": ["energy", 4184], "kilocalorie": ["energy", 4184], "kilocalories": ["energy", 4184],
    "wh": ["energy", 3600], "watthour": ["energy", 3600], "watthours": ["energy", 3600],
    "kwh": ["energy", 3.6e6], "kilowatthour": ["energy", 3.6e6], "kilowatthours": ["energy", 3.6e6],
    "mwh": ["energy", 3.6e9], "megawatthour": ["energy", 3.6e9],
    "btu": ["energy", 1055.05585262], "btus": ["energy", 1055.05585262], "british thermal unit": ["energy", 1055.05585262],
    "ev": ["energy", 1.602176634e-19], "electronvolt": ["energy", 1.602176634e-19],
    // power (base: watt)
    "w": ["power", 1], "watt": ["power", 1], "watts": ["power", 1],
    "kw": ["power", 1000], "kilowatt": ["power", 1000], "kilowatts": ["power", 1000],
    "mw": ["power", 1e6], "megawatt": ["power", 1e6], "megawatts": ["power", 1e6],
    "gw": ["power", 1e9], "gigawatt": ["power", 1e9],
    "hp": ["power", 745.699872], "horsepower": ["power", 745.699872],
    "ps": ["power", 735.49875],
    // pressure (base: pascal)
    "pa": ["pressure", 1], "pascal": ["pressure", 1], "pascals": ["pressure", 1],
    "hpa": ["pressure", 100], "kpa": ["pressure", 1000], "mpa": ["pressure", 1e6],
    "bar": ["pressure", 1e5], "bars": ["pressure", 1e5],
    "psi": ["pressure", 6894.757293168],
    "atm": ["pressure", 101325], "atmosphere": ["pressure", 101325], "atmospheres": ["pressure", 101325],
    "mmhg": ["pressure", 133.322387415], "torr": ["pressure", 133.322368421],
    // force (base: newton)
    "n": ["force", 1], "newton": ["force", 1], "newtons": ["force", 1],
    "kn": ["force", 1000], "kilonewton": ["force", 1000], "kilonewtons": ["force", 1000],
    "kgf": ["force", 9.80665], "kilogram-force": ["force", 9.80665],
    "lbf": ["force", 4.4482216152605], "pound-force": ["force", 4.4482216152605],
    // frequency (base: hertz)
    "hz": ["frequency", 1], "hertz": ["frequency", 1],
    "khz": ["frequency", 1000], "mhz": ["frequency", 1e6], "ghz": ["frequency", 1e9],
    "rpm": ["frequency", 1 / 60], "rps": ["frequency", 1],
    // voltage (base: volt)
    "v": ["voltage", 1], "volt": ["voltage", 1], "volts": ["voltage", 1],
    "kv": ["voltage", 1000], "kilovolt": ["voltage", 1000], "kilovolts": ["voltage", 1000],
    "mv": ["voltage", 0.001], "millivolt": ["voltage", 0.001],
    // current (base: ampere)
    "a": ["current", 1], "amp": ["current", 1], "amps": ["current", 1], "ampere": ["current", 1], "amperes": ["current", 1],
    "ma": ["current", 0.001], "milliamp": ["current", 0.001], "milliamps": ["current", 0.001],
    "ka": ["current", 1000], "kiloamp": ["current", 1000],
    // resistance (base: ohm)
    "ohm": ["resistance", 1], "ohms": ["resistance", 1], "ω": ["resistance", 1], "Ω": ["resistance", 1],
    "kω": ["resistance", 1000], "kohm": ["resistance", 1000], "mω": ["resistance", 1e6], "mohm": ["resistance", 1e6],
    // angle (base: radian)
    "rad": ["angle", 1], "radian": ["angle", 1], "radians": ["angle", 1],
    "deg": ["angle", 0.017453292519943295], "degree": ["angle", 0.017453292519943295], "degrees": ["angle", 0.017453292519943295], "°": ["angle", 0.017453292519943295],
    "grad": ["angle", 0.015707963267948967], "gon": ["angle", 0.015707963267948967],
    // temperature (special formulas, no factor)
    "c": ["temp"], "celsius": ["temp"],
    "f": ["temp"], "fahrenheit": ["temp"],
    "k": ["temp"], "kelvin": ["temp"]
  })

  // Currency uses live rates when reachable, falling back to these
  // approximate USD-anchored rates (units of currency per 1 USD) when the
  // live fetch is unavailable. Rows built on these are flagged approximate.
  readonly property var staticCurrencyRates: ({
    "usd": 1, "eur": 0.92, "gbp": 0.79, "jpy": 149, "cny": 7.2, "inr": 83,
    "cad": 1.37, "aud": 1.52, "chf": 0.88, "sek": 10.6, "nok": 10.8, "dkk": 6.9,
    "nzd": 1.67, "sgd": 1.34, "hkd": 7.8, "krw": 1340, "brl": 5.5, "mxn": 18.5,
    "rub": 92, "try": 35, "zar": 18.5, "aed": 3.67, "sar": 3.75, "qar": 3.64,
    "pln": 4.05, "czk": 23.5, "huf": 362, "ils": 3.7, "thb": 36, "myr": 4.4,
    "idr": 15800, "php": 57, "vnd": 25500, "egp": 49, "ngn": 1550, "kwd": 0.31,
    "bdt": 110, "pkr": 278, "lkr": 300, "uzs": 12600, "kes": 130,
    "uah": 41, "kzt": 470, "gel": 2.7, "crc": 520, "khr": 4050, "bob": 6.9,
    "clp": 920, "cop": 4100, "pen": 3.7, "uyu": 40, "mnt": 3350, "mmk": 2100,
    "afn": 70, "iqd": 1310, "lbp": 15000, "mad": 10, "dzd": 135
  })

  property var liveCurrencyRates: ({})
  property bool currencyRatesLoaded: false
  // int (32-bit) cannot hold a Date.now() epoch, so this must be double.
  property double currencyRatesFetchedAt: 0
  property bool currencyRatesFetching: false
  property string fxApiKey: ""

  // Currency symbols map to ISO codes so "100$ to €" behaves like "100 usd to eur".
  readonly property var currencySymbols: ({
    "$": "usd", "€": "eur", "£": "gbp", "¥": "jpy", "₹": "inr", "₽": "rub",
    "₩": "krw", "₺": "try", "₴": "uah", "₫": "vnd", "฿": "thb", "₦": "ngn",
    "₱": "php", "₪": "ils", "₸": "kzt", "₾": "gel", "₡": "crc", "r$": "brl"
  })

  // User config file: {"apiKey": "<exchangerate-api.com key>"}. Read live so an
  // edit takes effect without restarting the shell. See the README.
  readonly property string fxConfigPath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/pa.menu.json"
  readonly property string fxStatePath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/pa.menu.fx.json"
  readonly property int fxDailyMs: 24 * 3600 * 1000

  // ---- bounded local reads -------------------------------------------------
  //
  // Config and persisted-rate files are read through a single bash helper that
  // refuses symlinks, requires a regular file owned by the current user, and
  // caps how many bytes reach QML (descriptor-bound, no-follow). Content is
  // then parsed with per-field limits so only a bounded API key and bounded
  // currency-code/value entries ever reach the shell.

  readonly property int fxMaxLocalBytes: 8192
  readonly property int fxMaxApiKeyLength: 64
  readonly property int fxMaxRateEntries: 200
  readonly property int fxMaxRateBytes: 65536

  function queueLocalRead(target, path) {
    if (localReadProc.running) {
      localReadProc.pending = localReadProc.pending.concat([{ target: target, path: path }])
      return
    }
    localReadProc.target = target
    localReadProc.collected = ""
    localReadProc.command = ["bash", "-c", root.boundedReadCommand(path)]
    localReadProc.running = true
  }

  function boundedReadCommand(path) {
    var f = Util.shellQuote(path)
    // -L/-f/-O reject symlinks and require an owned regular file; `timeout`
    // bounds the read in case the path is raced to a FIFO after the checks.
    return "f=" + f + "; [ -L \"$f\" ] && exit 1; [ -f \"$f\" ] || exit 1; [ -O \"$f\" ] || exit 1; timeout 1 head -c " + root.fxMaxLocalBytes + " \"$f\""
  }

  function applyLocalRead(target, raw) {
    var content = String(raw || "").trim()
    if (content.length > root.fxMaxLocalBytes) content = content.substring(0, root.fxMaxLocalBytes)
    if (target === "config") root.applyConfigContent(content)
    else root.applyStateContent(content)
  }

  function applyConfigContent(raw) {
    var key = ""
    try {
      var cfg = JSON.parse(raw)
      if (cfg && typeof cfg.apiKey === "string") key = cfg.apiKey.trim()
    } catch (e) { }
    // Only a bounded, alphanumeric key reaches the shell (it is embedded in a
    // curl URL).
    if (!key || key.length > root.fxMaxApiKeyLength || !/^[a-zA-Z0-9]+$/.test(key)) key = ""
    root.fxApiKey = key
  }

  function applyStateContent(raw) {
    try {
      var st = JSON.parse(raw)
      var at = st && typeof st.fetchedAt === "number" && isFinite(st.fetchedAt) ? st.fetchedAt : 0
      var normalized = root.normalizeRates(st && st.rates)
      if (normalized && at > 0 && Date.now() - at < root.fxDailyMs) {
        root.liveCurrencyRates = normalized
        root.currencyRatesLoaded = true
        root.currencyRatesFetchedAt = at
      } else if (at > 0) {
        root.currencyRatesFetchedAt = at
      }
    } catch (e) { }
  }

  // Keep only bounded, sane currency-code/value pairs: a short code and a
  // positive finite rate. Cap the total so a malicious feed cannot balloon the
  // shell's memory.
  function normalizeRates(rates) {
    if (!rates || typeof rates !== "object") return null
    var out = ({})
    var count = 0
    for (var code in rates) {
      if (count >= root.fxMaxRateEntries) break
      var c = String(code)
      if (!c || c.length > 8) continue
      var v = Number(rates[code])
      if (typeof v !== "number" || !isFinite(v) || v <= 0 || v > 1e15) continue
      out[c.toLowerCase()] = v
      count++
    }
    return count > 0 ? out : null
  }

  function currencyFactor(name) {
    var key = String(name || "").toLowerCase()
    var code = root.currencySymbols[key] || key
    if (root.liveCurrencyRates[code] !== undefined) return Number(root.liveCurrencyRates[code])
    var staticRate = root.staticCurrencyRates[code]
    return staticRate !== undefined ? Number(staticRate) : undefined
  }

  function unitLookup(name) {
    var key = String(name || "").toLowerCase()
    var stripped = key.replace(/°/g, "")
    var entry = root.unitTable[stripped]
    if (!entry) entry = root.unitTable[key]
    if (entry) {
      if (entry[0] === "temp") return { category: "temp", key: stripped }
      return { category: entry[0], factor: entry[1], key: key }
    }
    var factor = root.currencyFactor(key)
    if (factor !== undefined) return { category: "currency", factor: factor, key: key }
    return null
  }

  function tempKey(name) {
    var key = String(name || "").toLowerCase().replace(/°/g, "")
    if (key === "c" || key === "celsius") return "c"
    if (key === "f" || key === "fahrenheit") return "f"
    if (key === "k" || key === "kelvin") return "k"
    return ""
  }

  function convertTemp(value, fromUnit, toUnit) {
    var from = root.tempKey(fromUnit)
    var to = root.tempKey(toUnit)
    if (!from || !to || from === to) return value
    var celsius
    if (from === "c") celsius = value
    else if (from === "f") celsius = (value - 32) * 5 / 9
    else celsius = value - 273.15
    if (to === "c") return celsius
    if (to === "f") return celsius * 9 / 5 + 32
    return celsius + 273.15
  }

  // Format a result for display. Whole numbers stay exact; anything else is
  // rounded to two decimals (trailing zeros dropped) like money. Values too
  // small for two decimals, and very large magnitudes, fall back to a compact
  // exponential form rather than showing a misleading "0".
  function formatNumber(value) {
    if (value === 0) return "0"
    if (!isFinite(value)) return ""
    var abs = Math.abs(value)
    if (Math.floor(value) === value && abs < 1e21) return String(value)
    if (abs >= 1e21 || (abs > 0 && abs < 0.005)) return value.toExponential(2).replace(/\.?0+e/, "e")
    return String(Number(value.toFixed(2)))
  }

  // Precomputed once so the per-keystroke search path never rebuilds it.
  readonly property string conversionUnitChars: "[a-z°/²³0-9Ω$€£¥₹₽₩₺₴₫฿₦₱₪₸₾₡-]+"
  readonly property var conversionRegex: (function() {
    var u = root.conversionUnitChars
    return new RegExp("^(?:convert\\s+)?(-?[0-9]+(?:\\.[0-9]+)?)\\s*(" + u + "(?:\\s" + u + ")?)\\s+(?:to|in)\\s+(" + u + "(?:\\s" + u + ")?)$")
  })()

  // Parse "<amount> <from-unit> to|in <to-unit>" (units may touch the number,
  // e.g. "5ft in cm"). Returns { label, copy, approx } for a row, or null when
  // the text is not a conversion. approx is set when currency used the static
  // fallback rate; a live fetch (if due) replaces it shortly after.
  function convertResult(input) {
    var text = String(input || "").toLowerCase().trim()
    if (!text || text.length > 200) return null
    // Move a leading currency symbol behind the amount ("£100" -> "100£")
    // so the amount-first grammar below handles it like "100£".
    text = text.replace(/^([$€£¥₹₽₩₺₴₫฿₦₱₪₸₾₡])([0-9][0-9.]*)/, "$2$1")
    var m = text.match(root.conversionRegex)
    if (!m) return null

    var amount = Number(m[1])
    var fromUnit = m[2].trim()
    var toUnit = m[3].trim()
    var from = root.unitLookup(fromUnit)
    var to = root.unitLookup(toUnit)
    if (!from || !to || from.category !== to.category) return null

    var result
    var approx = false
    if (from.category === "temp") {
      result = root.convertTemp(amount, fromUnit, toUnit)
    } else if (from.category === "currency") {
      // Rates are "units of currency per 1 USD", so the conversion inverts
      // relative to physical units. Kick off a live refresh if one is due.
      result = amount * to.factor / from.factor
      approx = !root.currencyRatesLoaded
      root.ensureCurrencyRates()
    } else {
      result = amount * from.factor / to.factor
    }
    if (typeof result !== "number" || !isFinite(result)) return null

    var displayAmount = String(amount)
    if (Math.round(amount) !== amount) displayAmount = String(Number(amount))
    var displayFrom = fromUnit
    var displayTo = toUnit
    if (from.category === "currency") {
      displayFrom = fromUnit.toUpperCase()
      displayTo = toUnit.toUpperCase()
    }
    return {
      label: displayAmount + " " + displayFrom + " → " + root.formatNumber(result) + " " + displayTo,
      copy: root.formatNumber(result) + " " + displayTo,
      approx: approx
    }
  }

  // Fetch USD-anchored exchange rates at most once per day, persisted across
  // shell restarts (see fxStateFile), so the default keyless endpoint — or a
  // configured exchangerate-api.com key on its 1,500 req/month free tier — is
  // never hit more than ~31 times a month. A failed fetch is also remembered
  // so it is not retried within the same day; static fallback rates keep
  // currency working offline in the meantime.
  function ensureCurrencyRates() {
    if (root.currencyRatesFetching) return
    var age = Date.now() - root.currencyRatesFetchedAt
    if (age < root.fxDailyMs) return
    root.currencyRatesFetching = true
    var url = "https://open.er-api.com/v6/latest/USD"
    if (root.fxApiKey) url = "https://v6.exchangerate-api.com/v6/" + root.fxApiKey + "/latest/USD"
    ratesProc.collected = ""
    // --max-filesize bounds buffered output; --max-time bounds wall time.
    ratesProc.command = ["bash", "-lc", "curl -fsSL --max-time 8 --max-filesize " + root.fxMaxRateBytes + " " + Util.shellQuote(url)]
    ratesProc.running = true
  }

  // Persist {fetchedAt, rates} to disk so a restart doesn't refetch within the
  // day. Written through a same-directory temporary file with private
  // permissions and atomically renamed, so the predictable state path never
  // follows a pre-existing symlink or truncates another target.
  function saveRatesState() {
    var payload = JSON.stringify({ fetchedAt: root.currencyRatesFetchedAt, rates: root.liveCurrencyRates })
    if (!payload || payload.length > root.fxMaxLocalBytes) return
    var dir = root.fxStatePath.replace(/\/[^/]*$/, "")
    var cmd = "d=" + Util.shellQuote(dir) + "; f=" + Util.shellQuote(root.fxStatePath)
      + "; mkdir -p \"$d\" || exit 1"
      + "; tmp=$(mktemp \"$d/.fx.XXXXXX\") || exit 1"
      + "; chmod 600 \"$tmp\""
      + "; printf '%s\\n' " + Util.shellQuote(payload) + " > \"$tmp\" || { rm -f \"$tmp\"; exit 1; }"
      + "; mv -f \"$tmp\" \"$f\" || { rm -f \"$tmp\"; exit 1; }"
    ratesStateProc.command = ["bash", "-c", cmd]
    ratesStateProc.running = true
  }

  function markRatesAttempted() {
    root.currencyRatesFetchedAt = Date.now()
    root.saveRatesState()
  }

  // A search-time row that shows the result of a calculation or conversion and
  // copies it to the clipboard on Enter. score is far below any real match so
  // it always surfaces first.
  function calcRow(query) {
    var time = root.timeRow(query)
    if (time) return time

    var conv = root.convertResult(query)
    if (conv) {
      return {
        itemId: "calc.result",
        kind: "calc",
        icon: "≈",
        iconFont: "",
        appIcon: "",
        appId: "",
        label: conv.label,
        target: "",
        detail: conv.approx ? "Approx rate · Enter to copy" : "Convert · Enter to copy",
        path: "",
        childCount: 0,
        action: "printf '%s' " + Util.shellQuote(conv.copy) + " | wl-copy",
        provider: "",
        score: -1000000,
        section: ""
      }
    }
    var result = root.calcResult(query)
    if (result === "") return null
    return {
      itemId: "calc.result",
      kind: "calc",
      icon: "=",
      iconFont: "",
      appIcon: "",
      appId: "",
      label: String(query).trim() + " = " + result,
      target: "",
      detail: "Result · Enter to copy",
      path: "",
      childCount: 0,
      action: "printf '%s' " + Util.shellQuote(result) + " | wl-copy",
      provider: "",
      score: -1000000,
      section: ""
    }
  }

  // "time in tokyo", "now in utc", "clock at pst". Aliases answer without
  // waiting on the zone list; city names wait for timedatectl. Enter copies
  // the wall time. A query that is not a place the system knows falls through
  // as an ordinary search ("now playing").
  function timeRow(query) {
    var place = MenuModel.parseTimeQuery(query)
    if (place === null) return null

    var zone = MenuModel.resolveZone(place, root.timeZones)
    if (!zone) {
      if (!root.ensureTimeZones()) return root.timePendingRow(place)
      return null
    }

    if (!root.ensureZoneOffset(zone)) return root.timePendingRow(place)

    var offset = root.zoneOffsets[zone].offset
    var localOffset = -new Date().getTimezoneOffset() * 60
    var there = MenuModel.zoneClock(Date.now(), offset)
    var here = MenuModel.zoneClock(Date.now(), localOffset)
    var sameDay = there.date === here.date && there.month === here.month && there.year === here.year
    var weekday = MenuModel.zoneWeekdayName(there.weekday).slice(0, 3)
    var clock = sameDay ? there.time : there.time + " " + weekday

    return {
      itemId: "time.result",
      kind: "time",
      icon: "󰅐",
      iconFont: "",
      appIcon: "",
      appId: "",
      label: clock,
      target: "",
      detail: zone + " · " + MenuModel.zoneDifference(offset, localOffset) + " · Enter to copy",
      path: "",
      childCount: 0,
      action: "printf '%s' " + Util.shellQuote(there.time) + " | wl-copy",
      provider: "",
      score: -1000000,
      section: ""
    }
  }

  function timePendingRow(place) {
    return {
      itemId: "time.result",
      kind: "time",
      icon: "󰅐",
      iconFont: "",
      appIcon: "",
      appId: "",
      label: place,
      target: "",
      detail: "Looking up time zone…",
      path: "",
      childCount: 0,
      action: "",
      provider: "",
      score: -1000000,
      section: ""
    }
  }

  function ensureTimeZones() {
    if (root.timeZonesLoaded || root.timeZones.length > 0) return true
    if (zoneListProc.running) return false
    zoneListProc.collected = ""
    zoneListProc.command = ["bash", "-c", "timeout 5 timedatectl list-timezones | head -c 65536"]
    zoneListProc.running = true
    return false
  }

  // Offsets are re-read after half an hour so a shell that has been up across
  // a DST change is not still an hour out.
  function ensureZoneOffset(zone) {
    if (!MenuModel.isIanaZoneName(zone)) return false
    var known = root.zoneOffsets[zone]
    var now = Math.floor(Date.now() / 1000)
    if (known && now - known.readAt < 1800) return true
    if (zoneOffsetProc.running) return false

    zoneOffsetProc.zone = zone
    zoneOffsetProc.collected = ""
    zoneOffsetProc.command = ["bash", "-c",
      "timeout 5 env TZ=" + Util.shellQuote(zone) + " date +%z"]
    zoneOffsetProc.running = true
    return false
  }

  function displayRow(entry, detail, score, section) {
    return MenuModel.displayRow(root.items, root.itemOrder, root.checkedResults, entry, detail, score, section)
  }

  function rebuildDmenuDisplay() {
    displayModel.clear()
    root.searchDivider = false

    if (root.mode === "input") {
      layoutSerial += 1
      return
    }

    var query = root.filterText.trim().toLowerCase()
    for (var i = 0; i < root.dmenuOptions.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(root.dmenuOptions[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0
          && detail.toLowerCase().indexOf(query) < 0) continue
      displayModel.append({
        itemId: "dmenu." + i,
        kind: "dmenu",
        icon: icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: ""
      })
    }

    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  function rebuildDisplay() {
    if (root.dmenuActive) {
      root.rebuildDmenuDisplay()
      return
    }

    displayModel.clear()

    if (!root.rowsLoaded) return

    var active = root.item(root.activeMenu) ? root.activeMenu : "root"
    root.activeMenu = active
    var rows = []
    var query = root.filterText.trim()
    root.searchDivider = false

    if (query) {
      var currentRows = []
      var drilldownRows = []

      for (var i = 0; i < root.itemOrder.length; i++) {
        var entry = root.item(root.itemOrder[i])
        if (!entry || entry.id === "root") continue
        if (!root.isDescendantOf(entry.id, active)) continue
        if (!root.matchesQuery(entry, query)) continue

        var detail = root.parentPathFor(entry.id)
        var row = root.displayRow(entry, detail, root.searchScore(entry, query))
        if (entry.parent === active) currentRows.push(row)
        else drilldownRows.push(row)
      }

      var calc = root.calcRow(query)
      if (calc) currentRows.push(calc)

      var searchSort = function(a, b) {
        if (a.score !== b.score) return a.score - b.score
        return a.path.localeCompare(b.path)
      }

      currentRows.sort(searchSort)
      drilldownRows.sort(searchSort)
      root.searchDivider = currentRows.length > 0 && drilldownRows.length > 0
      if (root.searchDivider) {
        for (var d = 0; d < drilldownRows.length; d++) drilldownRows[d].section = "drilldown"
      }
      rows = currentRows.concat(drilldownRows)
    } else {
      for (var j = 0; j < root.itemOrder.length; j++) {
        var child = root.item(root.itemOrder[j])
        if (!child || child.parent !== active) continue
        if (!root.isVisible(child)) continue
        rows.push(root.displayRow(child, child.description, child.order))
      }

      // DesktopEntries can reorder its values when an application starts.
      // Keep the Apps menu alphabetical independently of provider refreshes.
      if (active === "apps") {
        rows.sort(function(a, b) {
          var aLabel = String(a.label || "").toLowerCase()
          var bLabel = String(b.label || "").toLowerCase()
          if (aLabel < bLabel) return -1
          if (aLabel > bLabel) return 1
          var aId = String(a.itemId || "")
          var bId = String(b.itemId || "")
          if (aId < bId) return -1
          if (aId > bId) return 1
          return 0
        })
      }
    }

    for (var k = 0; k < rows.length; k++) displayModel.append(rows[k])
    layoutSerial += 1

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) root.revealCursor()
    })
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel.
  function revealCursor() {
    if (displayModel.count === 0) return
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

    var item = resultList.itemAtIndex(root.selectedIndex)
    if (!item) return

    var reach = root.rowPeek + root.rowSpacing
    if (root.selectedIndex < displayModel.count - 1) {
      var maxY = Math.max(resultList.originY, resultList.originY + resultList.contentHeight - resultList.height)
      var overhang = item.y + item.height + reach - (resultList.contentY + resultList.height)
      if (overhang > 0) resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
    }
    if (root.selectedIndex > 0) {
      var underhang = resultList.contentY - (item.y - reach)
      if (underhang > 0) resultList.contentY = Math.max(resultList.contentY - underhang, resultList.originY)
    }
  }

  function select(delta) {
    if (displayModel.count === 0) return

    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    revealCursor()
  }

  function setFilter(nextFilter) {
    panel.freezeCardTop()
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = root.mode !== "input"
    root.disarmPointer()
    if (!root.dmenuActive && root.filterText.trim()) root.loadProvidersForSearch()
    root.rebuildDisplay()
  }

  function setActiveMenu(id, pushHistory, fromPointer) {
    panel.freezeCardTop()
    if (!root.item(id)) id = "root"
    if (pushHistory && id !== root.activeMenu) root.navStack = root.navStack.concat([root.activeMenu])
    root.activeMenu = id
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    if (fromPointer) pointerGate.allowInitialSample()
    else root.disarmPointer()
    root.rebuildDisplay()
    root.invalidateVolatileProvider(id)
    root.loadProviderForMenu(id)
  }

  function goBack() {
    if (root.activeMenu === "root") return false

    if (root.navStack.length > 0) {
      var previous = root.navStack[root.navStack.length - 1]
      root.navStack = root.navStack.slice(0, root.navStack.length - 1)
      root.setActiveMenu(previous, false)
      return true
    }

    var active = root.item(root.activeMenu)
    root.setActiveMenu((active && active.parent) ? active.parent : "root", false)
    return true
  }

  function activateIndex(index, fromPointer) {
    if (root.deleteConfirmOpen) return
    if (root.dmenuActive) {
      if (root.mode === "input") {
        root.applyDmenuSelection(root.filterText)
        return
      }
      if (index < 0 || index >= displayModel.count) return
      var picked = displayModel.get(index)
      root.applyDmenuSelection(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      return
    }

    if (index < 0 || index >= displayModel.count) return

    var row = displayModel.get(index)
    if (row.kind === "menu" || row.kind === "link") {
      root.setActiveMenu(row.target || row.itemId, true, fromPointer)
    } else if (row.kind === "app") {
      var appId = row.appId
      var label = row.label
      applySerial = requestSerial
      opened = false
      filterText = ""
      if (root.appLibrary) root.appLibrary.launch(appId, label)
    } else if (row.kind === "time" && !row.action) {
      return
    } else {
      root.applySelected(row.itemId, row.action)
    }
  }

  function requestDeleteSelected() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return
    var row = displayModel.get(root.selectedIndex)
    if (!row || row.kind !== "app") return
    root.deleteTarget = { appId: row.appId, label: row.label }
    deleteConfirm.selectedIndex = 1
    root.deleteConfirmOpen = true
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    deleteConfirm.selectedIndex = 1
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDelete() {
    var target = root.deleteTarget
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    if (!target) return
    root.cancel()
    if (root.appLibrary) root.appLibrary.remove(target.appId, target.label)
  }

  function applyDmenuSelection(value) {
    applySerial = requestSerial
    opened = false
    filterText = ""
    root.finishRequest(value)
  }

  function applySelected(id, action) {
    if (!id) { cancel(); return }

    applySerial = requestSerial
    opened = false
    filterText = ""
    root.runAction(action)
  }

  function cancel() {
    if (root.dmenuActive) root.finishRequest(null)
    opened = false
    filterText = ""
  }

  function openExistingMenu(initialMenu) {
    requestSerial += 1
    mode = "menu"
    requestActive = false
    selectionFile = ""
    doneFile = ""
    activeMenu = root.item(initialMenu) ? initialMenu : "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = true
    root.disarmPointer()
    root.evaluateGuards()
    opened = true
    root.ensureTimeZones()
    rebuildDisplay()
    invalidateVolatileProvider(activeMenu)
    loadProviderForMenu(activeMenu)
    // The shell may start before first-install packages have finished placing
    // their icons. Refresh here even when the desktop entry list did not change.
    if (root.appLibrary) root.appLibrary.refreshIcons()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function openDmenu(payload) {
    requestSerial += 1
    mode = payload.mode === "input" ? "input" : "select"
    dmenuPrompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenuOptions = Array.isArray(payload.options) ? payload.options : []
    selectionFile = String(payload.selectionFile || "")
    doneFile = String(payload.doneFile || "")
    requestActive = !!doneFile
    dmenuWidth = Math.max(1, Number(payload.width || 300))
    dmenuMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    activeMenu = "root"
    navStack = []
    filterText = ""
    selectedIndex = 0
    cursorActive = mode !== "input"
    root.disarmPointer()
    opened = true
    rebuildDisplay()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  ListModel { id: displayModel }

  // ----------------------------------------------------------- route surface
  //
  // The menu is opened through the standard plugin lifecycle:
  // `omarchy-shell shell summon omarchy.menu '{"menu":"system"}'`.
  // Callers may pass a real id (`system`, `setup.power`) or an alias declared
  // in JSONC (`power`, `reminder-set`). Unknown strings fall through to the
  // id-as-route behavior so misspellings still attempt to open the literal id.
  function resolveRoute(input) {
    return MenuModel.resolveRoute(root.items, root.itemOrder, input)
  }

  function openRoute(initialMenu) {
    var id = root.resolveRoute(initialMenu)
    var entry = root.items[id]
    // If the resolved id is an action (i.e. the user invoked an alias for
    // a leaf, e.g. `omarchy menu summon screenrecord-stop`), run it directly
    // instead of opening an action with no children.
    if (entry && entry.kind === "action" && entry.action) {
      root.cancel()
      root.runAction(entry.action)
      return "ok"
    }
    // If it's a link (a redirect to another menu), follow the link.
    if (entry && entry.kind === "link" && entry.target) id = entry.target
    root.pendingInitialMenu = id
    root.openExistingMenu(id)
    return "ok"
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function(data) { providerProc.collected += data + "\n" }
    }
    onExited: {
      if (providerProc.revision === root.providerRevision) {
        root.mergeProviderRows(providerProc.collected, providerProc.menuId, providerProc.providerKey)
        if (root.filterText.trim()) root.loadProvidersForSearch()
      }
      root.startNextProvider()
    }
  }

  Process {
    id: resultProc
    onExited: {
      if (root.applySerial === root.requestSerial)
        root.opened = false
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Connections {
    target: root.appLibrary
    function onAppsChanged() {
      if (root.providersLoaded["apps"]) root.mergeAppRows()
    }
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: defaultMenuFile
    path: root.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.defaultMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.userMenuItems = root.parseMenuJsonc(text()); root.rebuildItemsFromSources() }
    onLoadFailed: { root.userMenuItems = []; root.rebuildItemsFromSources() }
    onFileChanged: reload()
  }

  // ---------------------------------------------------------------- guards
  //
  // `when:` (visibility) and `checked:` (✓ marker) are bash expressions the
  // shell wasn't allowed to evaluate before the perf rewrite. Now the shell
  // batches them into one bash subprocess per (re)load so the open path
  // never has to wait on them.

  property var whenResults: ({})       // id → true|false (allow visibility)
  property var checkedResults: ({})    // id → true|false (show ✓)
  property bool guardsPending: false

  function evaluateGuards() {
    // Process ignores a command change while it is running, and `collected`
    // belongs to the run in flight, so a second evaluation cannot overwrite
    // the first: it would throw away the lines already read and never start.
    // The surviving tail then lands as the whole answer, and every id lost
    // with it goes back to showing, since a `when:` only hides on an explicit
    // false. Wait for the run in flight and evaluate once it lands instead.
    if (guardProc.running) {
      root.guardsPending = true
      return
    }
    root.guardsPending = false

    var script = MenuModel.guardScript(root.items)
    if (!script) {
      root.whenResults = ({})
      root.checkedResults = ({})
      return
    }
    guardProc.collected = ""
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: guardProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) { guardProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      // A batch that was killed rather than finished has only told us about
      // the rows it reached, and a row whose `when:` went unanswered shows.
      // Keep the last complete set rather than let a half-read one through.
      // A signal leaves the exit code at 0, so the status is what tells us.
      if (exitCode !== 0 || exitStatus !== 0) {
        if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
        return
      }

      var nextWhen = ({})
      var nextChecked = ({})
      var lines = guardProc.collected.split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        var colon = line.lastIndexOf(":")
        if (colon < 0) continue
        var value = line.substring(colon + 1) === "1"
        var rest = line.substring(0, colon)
        var tagAt = rest.lastIndexOf(":")
        if (tagAt < 0) continue
        var id = rest.substring(0, tagAt)
        var tag = rest.substring(tagAt + 1)
        if (tag === "w") nextWhen[id] = value
        else if (tag === "c") nextChecked[id] = value
      }
      root.whenResults = nextWhen
      root.checkedResults = nextChecked
      if (root.opened) root.rebuildDisplay()
      // Run the evaluation that had to stand aside. Deferred by a turn so the
      // process is settled before its command is set again.
if (root.guardsPending) Qt.callLater(function() { root.evaluateGuards() })
    }
  }

  Process {
    id: ratesProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) {
        // Byte ceiling on the HTTP response before it ever reaches JSON.parse.
        if (ratesProc.collected.length < root.fxMaxRateBytes)
          ratesProc.collected = (ratesProc.collected + data + "\n").substring(0, root.fxMaxRateBytes)
      }
    }
    onExited: function(exitCode, exitStatus) {
      root.currencyRatesFetching = false
      if (exitCode !== 0 || exitStatus !== 0) {
        root.markRatesAttempted()
        return
      }
      try {
        var parsed = JSON.parse(ratesProc.collected)
        // open.er-api.com answers under "rates"; exchangerate-api.com under
        // "conversion_rates". Both are USD-anchored. Entries are bounded.
        var raw = parsed && (parsed.conversion_rates || parsed.rates)
        var normalized = root.normalizeRates(raw)
        if (parsed && normalized) {
          root.liveCurrencyRates = normalized
          root.currencyRatesLoaded = true
          root.currencyRatesFetchedAt = Date.now()
          root.saveRatesState()
          if (root.opened) root.rebuildDisplay()
          return
        }
      } catch (e) { }
      root.markRatesAttempted()
    }
  }

  Process {
    id: ratesStateProc
    running: false
  }

  Process {
    id: zoneListProc
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) {
        if (zoneListProc.collected.length < 65536)
          zoneListProc.collected = (zoneListProc.collected + data + "\n").substring(0, 65536)
      }
    }
    onExited: function() {
      var lines = zoneListProc.collected.split("\n")
      var kept = []
      for (var i = 0; i < lines.length; i++) {
        var zone = lines[i].trim()
        if (MenuModel.isIanaZoneName(zone)) kept.push(zone)
      }
      root.timeZones = kept
      root.timeZonesLoaded = true
      if (root.opened && root.filterText.trim()) root.rebuildDisplay()
    }
  }

  Process {
    id: zoneOffsetProc
    property string zone: ""
    property string collected: ""
    stdout: SplitParser {
      onRead: function(data) {
        if (zoneOffsetProc.collected.length < 64)
          zoneOffsetProc.collected = (zoneOffsetProc.collected + data).substring(0, 64)
      }
    }
    onExited: function() {
      var offset = MenuModel.parseZoneOffset(zoneOffsetProc.collected)
      if (offset === null || !zoneOffsetProc.zone) return
      var next = ({})
      var src = root.zoneOffsets
      for (var k in src) next[k] = src[k]
      next[zoneOffsetProc.zone] = { offset: offset, readAt: Math.floor(Date.now() / 1000) }
      root.zoneOffsets = next
      if (root.opened && root.filterText.trim()) root.rebuildDisplay()
    }
  }

  // Bounded, no-follow local file reads (config + persisted rates state).
  Process {
    id: localReadProc
    property string target: ""
    property string collected: ""
    property var pending: []
    stdout: SplitParser {
      onRead: function(data) { localReadProc.collected += data + "\n" }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0 && exitStatus === 0) {
        root.applyLocalRead(localReadProc.target, localReadProc.collected)
      } else if (localReadProc.target === "config") {
        root.fxApiKey = ""
      }
      if (localReadProc.pending.length > 0) {
        var next = localReadProc.pending.shift()
        localReadProc.target = next.target
        localReadProc.collected = ""
        localReadProc.command = ["bash", "-c", root.boundedReadCommand(next.path)]
        localReadProc.running = true
      }
    }
  }

  // Config (API key) is re-read every few seconds; the persisted rates state is
  // read once shortly after startup. Both queue through localReadProc.
  Timer {
    id: fxConfigTimer
    interval: 3000
    running: true
    repeat: true
    onTriggered: root.queueLocalRead("config", root.fxConfigPath)
  }

  Timer {
    id: fxStateTimer
    interval: 1000
    running: true
    onTriggered: root.queueLocalRead("state", root.fxStatePath)
  }

  PanelWindow {
    id: panel
    visible: root.opened && root.rowsLoaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // The card opens centered exactly as always. The first search keystroke
    // or submenu move freezes the top line where it currently sits — from
    // then on the card grows and shrinks downward instead of re-centering
    // on every resize, which made the menu jump around. The rows height is
    // frozen at the same moment, so the starting menu also caps how tall the
    // card may grow from there. Closing unfreezes both.
    property int cardTop: -1
    property int maxRowsHeight: -1
    readonly property int centeredTop: Math.max(Style.gapsOut, Math.round((height - root.cardHeight) / 2))
    readonly property int effectiveCardTop: cardTop >= 0 ? cardTop : centeredTop
    function freezeCardTop() {
      if (visible && cardTop < 0) {
        cardTop = effectiveCardTop
        maxRowsHeight = root.visibleRowsHeight
      }
    }
    onVisibleChanged: if (!visible) { cardTop = -1; maxRowsHeight = -1 }

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.cancel()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: Math.min(root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)
      radius: root.cornerRadius
      anchors.horizontalCenter: parent.horizontalCenter
      y: panel.effectiveCardTop
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.deleteConfirmOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.deleteConfirmOpen) {
            if (deleteConfirm.handleKey(event)) event.accepted = true
            return
          }

          if (event.key === Qt.Key_Delete) {
            root.requestDeleteSelected()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.cancel()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Left) && !root.filterText) {
            root.goBack()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
            if (root.dmenuActive) {
              if (root.mode === "input") root.applyDmenuSelection(root.filterText)
              else if (displayModel.count > 0) root.activateIndex(root.cursorActive ? root.selectedIndex : 0)
            } else if (root.cursorActive) root.activateIndex(root.selectedIndex)
            else if (displayModel.count > 0) root.cursorActive = true
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: deleteConfirm

          anchors.fill: parent
          opened: root.deleteConfirmOpen
          z: 10
          message: "Do you want to uninstall " + ((root.deleteTarget && root.deleteTarget.label) || "") + "?"
          confirmText: "Uninstall"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.confirmDelete()
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Rectangle {
          width: parent.width
          height: root.headerHeight
          radius: root.cornerRadius
          color: "transparent"

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || (root.dmenuActive ? (root.dmenuPrompt + "…") : ((root.item(root.activeMenu) ? (root.item(root.activeMenu).title || root.item(root.activeMenu).label) : "Go") + "…"))
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

        }

        Item {
          width: parent.width
          height: root.visibleRowsHeight

          ListView {
            id: resultList
            anchors.fill: parent
            model: displayModel
            clip: true
            spacing: root.rowSpacing
            boundsBehavior: Flickable.StopAtBounds

            section.property: "section"
            section.criteria: ViewSection.FullString
            section.delegate: Item {
              required property string section

              width: ListView.view.width
              height: section === "drilldown" ? root.dividerHeight : 0
              visible: section === "drilldown"

              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(4)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(4)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.spacing.hairline
                color: Util.alpha(root.foreground, 0.2)
              }
            }

            delegate: BorderSurface {
              id: row
              required property int index
              required property string itemId
              required property string kind
              required property string icon
              required property string iconFont
              required property string appIcon
              required property string appId
              required property string label
              required property string target
              required property string detail
              required property string path
              required property string action
              required property int childCount

              readonly property bool hasCursor: root.cursorActive && row.index === root.selectedIndex
              readonly property bool isApp: row.kind === "app"
              readonly property bool hasIcon: row.icon.length > 0 || row.isApp

              width: ListView.view.width
              height: root.rowHeightForDetail(row.detail)
              radius: root.cornerRadius
              color: row.hasCursor ? root.selectedBackground : "transparent"
              borderSpec: row.hasCursor ? root.selectedBorderSpec : Border.none()

              Rectangle {
                visible: false
                width: Style.space(4)
                height: parent.height - Style.space(18)
                radius: Math.min(root.cornerRadius, Style.space(4))
                color: root.selectedBackground
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: iconText
                visible: row.hasIcon && !row.isApp
                text: row.icon
                color: row.hasCursor ? root.selectedText : root.foreground
                font.family: row.iconFont.length > 0 ? row.iconFont : root.fontFamily
                font.pixelSize: Style.font.iconLarge
                width: Style.space(36)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Image {
                id: appIconImage
                visible: row.isApp
                width: Style.font.iconLarge
                height: Style.font.iconLarge
                fillMode: Image.PreserveAspectFit
                // Decode at physical pixels — a logical-size decode leaves
                // PNG icons upscaled and blurry on HiDPI displays.
                sourceSize.width: width * Screen.devicePixelRatio
                sourceSize.height: height * Screen.devicePixelRatio
                source: row.isApp && root.appLibrary ? root.appLibrary.iconSource(row.appIcon) : ""
                asynchronous: true
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(8) + (Style.space(36) - width) / 2
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              }

              Column {
                id: contentColumn
                anchors.left: row.hasIcon ? iconText.right : parent.left
                anchors.leftMargin: row.hasIcon ? Style.space(6) : root.rowReservedBorderLeft + Style.space(18)
                anchors.right: trail.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Text {
                  id: labelText
                  width: parent.width
                  text: row.label
                  color: row.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: row.detail
                  visible: (root.filterText || row.kind === "dmenu") && row.detail.length > 0
                  color: root.foreground
                  opacity: 0.52
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              Row {
                id: trail
                width: Style.space(14)
                anchors.right: parent.right
                anchors.rightMargin: root.rowReservedBorderRight + Style.space(8)
                y: contentColumn.y + labelText.y + (labelText.height - height) / 2
                spacing: 0

                Text {
                  visible: false
                  text: row.childCount
                  color: root.foreground
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: row.kind === "menu" || row.kind === "link" ? "›" : ""
                  color: row.hasCursor ? root.selectedText : root.foreground
                  opacity: row.kind === "menu" || row.kind === "link" ? 0.36 : 0
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Normal
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: mouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectFromPointer(row.index, row, {
                  x: mouseArea.mouseX,
                  y: mouseArea.mouseY
                })
                onPositionChanged: function(mouse) {
                  root.selectFromPointer(row.index, row, mouse)
                }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activateIndex(row.index, true)
                }
              }
            }
          }

          // Scroll scrims. The clipped row already marks the fold at rest;
          // these keep both edges honest once the list has been scrolled,
          // when content hides above the card top as well as below. Strength
          // tracks the distance still hidden past each edge rather than
          // animating on a clock, so a programmatic jump — wrapping from the
          // last row back to the first — lands with the fade already applied.
          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.contentY - resultList.originY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: root.background }
              GradientStop { position: 1; color: Util.alpha(root.background, 0) }
            }
          }

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.min(Style.space(28), parent.height / 2)
            visible: opacity > 0
            opacity: resultList.contentHeight > resultList.height
              ? Math.max(0, Math.min(1, (resultList.originY + resultList.contentHeight - resultList.height - resultList.contentY) / height))
              : 0
            gradient: Gradient {
              GradientStop { position: 0; color: Util.alpha(root.background, 0) }
              GradientStop { position: 1; color: root.background }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: displayModel.count === 0 && root.mode !== "input"

            Text {
              text: "󰈉"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }

            Text {
              text: root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: Style.space(320)
            }
          }
        }

        Item {
          width: parent.width
          height: 0
        }
      }
    }
  }
}
