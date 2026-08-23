import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel — same hero-over-detail composition, same
// spacing scale, same small-caps labels.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "omarchy.clock"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  readonly property string nextWeekStartLabel: Qt.locale().dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  property int eventRevision: 0
  readonly property var weeks: {
    eventRevision
    return Model.monthGrid(viewYear, viewMonth, weekStart, todayKey, eventIndex)
  }

  property var eventDoc: null
  property var eventIndex: ({})
  property var visibleEventList: []
  property string selectedDayKey: todayKey
  readonly property var selectedEvents: Model.eventsForDateKey(eventIndex, selectedDayKey)
  readonly property date selectedDate: Model.dateFromKey(selectedDayKey, today)
  readonly property string clockPluginDir: (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/pa.clock"
  readonly property string focusThunderbirdScript: clockPluginDir + "/focus-thunderbird-calendar"
  readonly property string syncThunderbirdScript: clockPluginDir + "/sync-thunderbird-calendar"
  readonly property string quickAddScript: clockPluginDir + "/quick-add-thunderbird"

  // ---- Quick-add entry pane. Right-click a day to slide this in; Esc
  //      slides back. Create writes a silent-create request the add-on
  //      consumes without focusing Thunderbird.
  property bool entryOpen: false
  property string entryKind: "event"
  property string nlText: ""
  property string entryStatus: ""
  property var lastBuiltRequest: null
  property var tbCalendars: []
  property string formTitle: ""
  property string formDate: ""
  property string formStart: ""
  property string formEnd: ""
  property string formEndDate: ""
  property bool formEndNextDay: false
  // No toggle: an event with no start time is an all-day event, which is
  // what a phrase without a time means anyway. Clearing the time chip is how
  // an event goes back to all-day.
  readonly property bool formAllDay: root.entryKind === "event" && root.formStart === ""
  property string formLocation: ""
  property string formDescription: ""
  property string formCalendar: ""
  property string formLink: ""
  // True once this entry's calendar was deliberately chosen (dropdown,
  // free text or parsed from the phrase); kind switches then keep it.
  property bool formCalendarChosen: false
  // Which summary value is currently an inline editor ("" = display mode).
  property string editingSegment: ""
  // Roles the parser found in the phrase, as offsets into it.
  property var nlSegments: []
  // The calendar the phrase named, kept apart from the one in force: when
  // the phrase names a list this kind cannot be written to, the pane says so
  // rather than quietly filing the entry somewhere else.
  property string nlCalendarName: ""
  // Optional parts the user opened by hand. A part the phrase filled in is
  // open because it has a value, so it never needs to be listed here.
  property var openRows: []
  // What the last parse put into each part. The phrase owns what it says;
  // this is how the pane can tell a value the phrase put there — and has
  // since dropped — from one typed into a row by hand, which another word in
  // the phrase must not wipe.
  property var nlApplied: ({})

  // One value in the entry summary — the title, or a day or a time in the
  // when-card. Display mode is the value over a hairline; a click swaps it
  // for an inline field that takes the same words the phrase does.
  component SlotEdit: Item {
    id: slot
    property string slotName: ""
    property string display: ""
    property string editValue: ""
    property bool hero: false
    property bool strong: false
    property bool dim: false
    property color tint: root.contentForeground
    property int align: Text.AlignLeft
    signal commitText(string text)

    readonly property bool editing: root.editingSegment === slotName

    implicitWidth: Math.max(slotText.implicitWidth + Style.space(8), Style.space(48))
    implicitHeight: slotText.implicitHeight + Style.space(6)
    width: implicitWidth
    height: implicitHeight

    Text {
      id: slotText
      visible: !slot.editing
      anchors.fill: parent
      anchors.bottomMargin: Style.space(4)
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: slot.align
      elide: Text.ElideRight
      text: slot.display
      color: slot.dim ? Qt.darker(slot.tint, 1.7) : slot.tint
      font.family: root.contentFontFamily
      font.pixelSize: slot.hero ? Style.font.title : (slot.strong ? Style.font.heading : Style.font.body)
      font.bold: slot.hero || slot.strong
    }

    // Hairline under the value: the form-field look of the reference, and
    // the only hint that a value can be clicked.
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Math.max(1, Style.space(1))
      color: slot.editing
        ? Color.accent
        : (slotHover.containsMouse ? slot.tint : Qt.darker(slot.tint, 2.6))
    }

    TextField {
      id: slotEdit
      visible: slot.editing
      anchors.fill: parent
      verticalPadding: 0
      foreground: root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: slotText.font.pixelSize
      font.bold: slotText.font.bold
      text: slot.editValue
      onAccepted: {
        slot.commitText(text)
        root.editingSegment = ""
      }
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.editingSegment = ""
          event.accepted = true
        }
      }
      onActiveFocusChanged: if (!activeFocus && slot.editing) {
        slot.commitText(text)
        root.editingSegment = ""
      }
    }

    MouseArea {
      id: slotHover
      anchors.fill: parent
      enabled: !slot.editing
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        root.editingSegment = slot.slotName
        slotEdit.text = slot.editValue
        slotEdit.forceActiveFocus()
        slotEdit.selectAll()
      }
    }
  }

  // The phrase field. A plain TextEdit does the editing but paints nothing;
  // a styled Text with identical font, width and wrapping sits exactly on
  // top of it and paints each parsed part in its own colour. Both run the
  // same layout, so the two stay glyph-for-glyph aligned — which is why the
  // editor's own text and cursor are transparent and drawn by us instead.
  component PhraseField: Item {
    id: field
    property string phrase: ""
    property string html: ""
    property string placeholderText: ""
    property real extraRightPadding: 0
    signal edited(string text)
    signal submitted()
    signal cancelled()

    readonly property real padX: Style.spacing.controlPaddingX
    readonly property real padY: Style.spacing.inputPaddingY
    readonly property bool hot: fieldHover.containsMouse
    readonly property var spec: Border.controlSpec(
      edit.activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"),
      root.contentForeground, Color.accent)

    implicitHeight: edit.contentHeight + 2 * padY + Border.top(spec) + Border.bottom(spec)
    height: implicitHeight

    function focusInput() {
      edit.forceActiveFocus()
      edit.selectAll()
    }

    // Typing breaks the binding to `phrase`, so a reset from code has to
    // write the editor directly rather than trust it to follow.
    function setPhrase(text) {
      edit.text = text
    }

    BorderSurface {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Style.controlFill(edit.activeFocus, field.hot, root.contentForeground, Color.accent)
      borderSpec: field.spec
    }

    TextEdit {
      id: edit
      anchors.fill: parent
      anchors.leftMargin: field.padX + Border.left(field.spec)
      anchors.rightMargin: field.padX + Border.right(field.spec) + field.extraRightPadding
      anchors.topMargin: field.padY + Border.top(field.spec)
      anchors.bottomMargin: field.padY + Border.bottom(field.spec)
      textFormat: TextEdit.PlainText
      wrapMode: TextEdit.Wrap
      // Invisible on purpose: the overlay above paints these same glyphs in
      // the colours of the parts they were parsed as.
      color: "transparent"
      selectionColor: Style.selectionFillFor(root.contentForeground, Color.accent)
      selectedTextColor: "transparent"
      selectByMouse: true
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.title
      text: field.phrase
      onTextChanged: if (text !== field.phrase) field.edited(text)

      // The default cursor takes its colour from `color`, which is
      // transparent here, so it has to be drawn.
      cursorDelegate: Rectangle {
        width: Math.max(1, Style.space(2))
        color: root.contentForeground
        visible: edit.activeFocus
        SequentialAnimation on opacity {
          running: edit.activeFocus
          loops: Animation.Infinite
          NumberAnimation { to: 0; duration: 500; easing.type: Easing.OutQuad }
          NumberAnimation { to: 1; duration: 500; easing.type: Easing.InQuad }
        }
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          field.cancelled()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          field.submitted()
          event.accepted = true
        }
      }
    }

    Text {
      anchors.fill: edit
      visible: edit.text !== ""
      textFormat: Text.StyledText
      wrapMode: Text.Wrap
      font: edit.font
      color: root.contentForeground
      text: field.html
    }

    Text {
      anchors.fill: edit
      visible: edit.text === ""
      wrapMode: Text.Wrap
      font: edit.font
      color: Qt.darker(root.contentForeground, 1.8)
      text: field.placeholderText
      elide: Text.ElideRight
    }

    MouseArea {
      id: fieldHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      cursorShape: Qt.IBeamCursor
    }
  }

  // Notes are the one part that runs past a line, so they get a box rather
  // than a field: five lines tall, scrolling once it is full. Enter puts in
  // a newline here — Ctrl+Enter is what creates, since Enter everywhere else
  // in the pane means "create".
  component NotesField: Item {
    id: notes
    property string value: ""
    property string placeholderText: ""
    property int lines: 5
    signal edited(string text)
    signal cancelled()
    signal submitted()

    readonly property real padX: Style.spacing.controlPaddingX
    readonly property real padY: Style.spacing.inputPaddingY
    readonly property bool hot: notesHover.containsMouse
    readonly property var spec: Border.controlSpec(
      area.activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"),
      root.contentForeground, Color.accent)

    implicitHeight: notes.lines * notesMetrics.height + 2 * padY
      + Border.top(spec) + Border.bottom(spec)
    height: implicitHeight

    function focusInput() {
      area.forceActiveFocus()
      area.cursorPosition = area.length
    }

    FontMetrics {
      id: notesMetrics
      font: area.font
    }

    BorderSurface {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Style.controlFill(area.activeFocus, notes.hot, root.contentForeground, Color.accent)
      borderSpec: notes.spec
    }

    Flickable {
      id: notesScroll
      anchors.fill: parent
      anchors.leftMargin: notes.padX + Border.left(notes.spec)
      anchors.rightMargin: notes.padX + Border.right(notes.spec)
      anchors.topMargin: notes.padY + Border.top(notes.spec)
      anchors.bottomMargin: notes.padY + Border.bottom(notes.spec)
      contentWidth: width
      contentHeight: area.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      TextEdit {
        id: area
        width: notesScroll.width
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.Wrap
        selectByMouse: true
        color: root.contentForeground
        selectionColor: Style.selectionFillFor(root.contentForeground, Color.accent)
        selectedTextColor: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        text: notes.value
        onTextChanged: if (text !== notes.value) notes.edited(text)

        // Keep the caret in view as the note grows past the box.
        onCursorRectangleChanged: {
          if (cursorRectangle.y < notesScroll.contentY)
            notesScroll.contentY = cursorRectangle.y
          else if (cursorRectangle.y + cursorRectangle.height > notesScroll.contentY + notesScroll.height)
            notesScroll.contentY = cursorRectangle.y + cursorRectangle.height - notesScroll.height
        }

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            notes.cancelled()
            event.accepted = true
          } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                     && (event.modifiers & Qt.ControlModifier)) {
            notes.submitted()
            event.accepted = true
          }
        }
      }
    }

    Text {
      anchors.fill: notesScroll
      visible: area.text === ""
      wrapMode: Text.Wrap
      color: Qt.darker(root.contentForeground, 1.8)
      font.family: area.font.family
      font.pixelSize: area.font.pixelSize
      text: notes.placeholderText
    }

    MouseArea {
      id: notesHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      cursorShape: Qt.IBeamCursor
    }
  }

  // Event or task, as a pair of tabs rather than a shortcut nobody sees.
  component KindTab: Item {
    id: tab
    property string label: ""
    property bool active: false
    signal activated()

    implicitWidth: tabText.implicitWidth
    implicitHeight: tabText.implicitHeight + Style.space(6)

    Text {
      id: tabText
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      text: tab.label
      color: tab.active ? Color.accent
        : (tabHover.containsMouse ? root.contentForeground : Qt.darker(root.contentForeground, 1.6))
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: tab.active
    }

    Rectangle {
      anchors.bottom: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      width: tabText.width
      height: Math.max(1, Style.space(2))
      visible: tab.active
      color: Color.accent
    }

    MouseArea {
      id: tabHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tab.activated()
    }
  }

  // One optional part of the entry — location, notes, alert, repeat,
  // priority. The pill above opens it, the phrase opens it by mentioning
  // it, and the × takes the part back off the entry.
  component EntryRow: Item {
    id: entryRow
    property string rowName: ""
    property string icon: ""
    default property alias content: rowHolder.data

    width: parent ? parent.width : 0
    visible: root.rowOpen(rowName)
    height: visible ? Math.max(Style.spacing.controlHeight, rowHolder.childrenRect.height) : 0

    // Icon and × centre on the first line rather than on the row, so a tall
    // box (notes) does not push them into its middle.
    Text {
      id: rowIcon
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.topMargin: Math.round((Style.spacing.controlHeight - height) / 2)
      text: entryRow.icon
      color: Qt.darker(root.contentForeground, 1.4)
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
    }

    Item {
      id: rowHolder
      anchors.left: rowIcon.right
      anchors.leftMargin: Style.space(8)
      anchors.right: rowClear.left
      anchors.rightMargin: Style.space(6)
      anchors.top: parent.top
      height: childrenRect.height
    }

    PanelActionButton {
      id: rowClear
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: Math.round((Style.spacing.controlHeight - height) / 2)
      iconText: "󰅖"
      tooltipText: "Remove"
      foreground: root.contentForeground
      fontFamily: root.contentFontFamily
      onClicked: root.clearRow(entryRow.rowName)
    }
  }

  property int formDuration: 0
  property int formAlertMinutes: 0
  property var formRecurrence: null
  property string formPriority: ""
  readonly property var calendarChoices: Model.calendarOptions(tbCalendars, entryKind)
  readonly property var calendarColorMap: Model.calendarColors(visibleEventList)

  // ---- Phrase colours. Omarchy themes are near-monochrome, so the parts of
  //      a phrase get hues of their own rather than shades of the accent —
  //      the whole point is telling a date from a time from a calendar at a
  //      glance. Lightness follows the popup surface so both dark and light
  //      themes stay readable, and the calendar part borrows the colour
  //      Thunderbird already paints that calendar in.
  readonly property bool darkSurface: Color.popups.background.hslLightness < 0.5
  function roleTint(hue, saturation) {
    return Qt.hsla(hue, saturation === undefined ? 0.62 : saturation,
                   root.darkSurface ? 0.70 : 0.38, 1.0)
  }
  readonly property color roleDateColor: roleTint(0.78)
  readonly property color roleTimeColor: roleTint(0.86)
  readonly property color roleDurationColor: roleTint(0.92)
  readonly property color roleAlertColor: roleTint(0.12)
  readonly property color roleRepeatColor: roleTint(0.50)
  readonly property color rolePriorityColor: roleTint(0.99)
  readonly property color roleLocationColor: roleTint(0.42)
  readonly property color roleLinkColor: roleTint(0.60, 0.85)
  readonly property color roleCalendarColor: {
    var own = root.formCalendar ? root.calendarColorMap[root.formCalendar] : ""
    return own ? own : roleTint(0.97, 0.55)
  }

  // StyledText wants "#rrggbb"; a QML colour stringifies with its alpha.
  function hexColor(value) {
    function part(v) {
      var text = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)
      return text.length < 2 ? "0" + text : text
    }
    return "#" + part(value.r) + part(value.g) + part(value.b)
  }

  readonly property var phraseColors: ({
    title: hexColor(root.contentForeground),
    date: hexColor(root.roleDateColor),
    time: hexColor(root.roleTimeColor),
    duration: hexColor(root.roleDurationColor),
    alert: hexColor(root.roleAlertColor),
    repeat: hexColor(root.roleRepeatColor),
    priority: hexColor(root.rolePriorityColor),
    location: hexColor(root.roleLocationColor),
    link: hexColor(root.roleLinkColor),
    calendar: hexColor(root.roleCalendarColor)
  })
  readonly property string phraseMarkup: Model.phraseHtml(root.nlText, root.nlSegments, root.phraseColors)

  // ---- Optional parts. A part is on screen when the phrase gave it a value
  //      or its pill was clicked; the pill and the row's × are the same
  //      switch seen from two places.
  function segmentValue(name) {
    if (name === "link") return root.formLink
    if (name === "location") return root.formLocation
    if (name === "notes") return root.formDescription
    if (name === "alert") return root.formAlertMinutes > 0 ? root.alertLabel() : ""
    if (name === "repeat") return root.formRecurrenceValue
    if (name === "priority") return root.formPriority
    return ""
  }

  function rowOpen(name) {
    return root.openRows.indexOf(name) !== -1 || root.segmentValue(name) !== ""
  }

  function openRow(name) {
    if (root.openRows.indexOf(name) !== -1) return
    var next = root.openRows.slice()
    next.push(name)
    root.openRows = next
  }

  function closeRow(name) {
    var next = []
    for (var i = 0; i < root.openRows.length; i++)
      if (root.openRows[i] !== name) next.push(root.openRows[i])
    root.openRows = next
  }

  function clearRow(name) {
    if (name === "link") root.formLink = ""
    else if (name === "location") root.formLocation = ""
    else if (name === "notes") root.formDescription = ""
    else if (name === "alert") root.formAlertMinutes = 0
    else if (name === "repeat") root.formRecurrence = null
    else if (name === "priority") root.formPriority = ""
    root.closeRow(name)
  }

  // Clicking a pill that already holds a value takes the part off again —
  // one switch, both directions.
  function toggleRow(name) {
    if (root.segmentValue(name) !== "") root.clearRow(name)
    else if (root.openRows.indexOf(name) !== -1) root.closeRow(name)
    else root.openRow(name)
  }

  // ---- Calendars. The event roster and the task roster are different lists
  //      even where Thunderbird lets one storage hold both, so every path
  //      that can set a calendar — the chooser, the phrase, a kind switch,
  //      reopening the pane — runs the choice past the current kind.
  function calendarValidForKind(name) {
    if (!root.calendarChoices.length) return true
    for (var i = 0; i < root.calendarChoices.length; i++)
      if (root.calendarChoices[i].value === name) return true
    return false
  }

  function ensureCalendarForKind() {
    if (root.formCalendar !== "" && root.calendarValidForKind(root.formCalendar)) return
    root.formCalendar = root.calendarChoices.length ? root.calendarChoices[0].value : ""
    root.formCalendarChosen = false
  }

  // ---- The when-card. End day is only stored when it differs from the
  //      start day, so the card works out what to show.

  // Qt's date formatting rather than JavaScript's: the QML engine ignores
  // toLocaleDateString's options object, so the month name and the weekday
  // come from Qt.formatDate and the locale.
  function dayLabel(dateKey) {
    var d = Model.dateFromKey(dateKey, null)
    if (!d) return String(dateKey || "")
    var body = Qt.formatDate(d, d.getFullYear() === root.today.getFullYear() ? "d MMM" : "d MMM yyyy")
    var kind = Model.relativeDayKind(dateKey, root.todayKey)
    if (kind === "today") return "Today, " + body
    if (kind === "tomorrow") return "Tomorrow, " + body
    if (kind === "yesterday") return "Yesterday, " + body
    if (kind === "weekday") return Qt.locale().dayName(d.getDay(), Locale.LongFormat) + ", " + body
    return body
  }

  function entryEndDateKey() {
    if (root.formEndDate) return root.formEndDate
    if (root.formEndNextDay && !root.formAllDay) {
      var d = Model.dateFromKey(root.formDate, null)
      if (d) {
        d.setDate(d.getDate() + 1)
        return Model.keyForDate(d)
      }
    }
    return root.formDate
  }

  function commitStartDate(text) {
    var key = Model.parseDateInput(text, root.selectedDayKey, Date.now())
    if (key) root.formDate = key
  }

  function commitEndDate(text) {
    var key = Model.parseDateInput(text, root.formDate || root.selectedDayKey, Date.now())
    if (!key) return
    root.formEndNextDay = false
    root.formEndDate = key === root.formDate ? "" : key
  }

  function commitStartTime(text) {
    var value = Model.parseTimeInput(text)
    if (!value) {
      // Emptying the start empties the span with it: an end alone would be
      // an event that finishes without starting.
      if (String(text || "").replace(/^\s+|\s+$/g, "") === "") {
        root.formStart = ""
        root.formEnd = ""
        root.formEndNextDay = false
      }
      return
    }
    root.formStart = value
  }

  function commitEndTime(text) {
    // The first time typed into either chip is the start — an end on its own
    // has nothing to end.
    if (root.formStart === "") {
      root.commitStartTime(text)
      return
    }
    var value = Model.parseTimeInput(text)
    if (!value) {
      if (String(text || "").replace(/^\s+|\s+$/g, "") === "") root.formEnd = ""
      return
    }
    root.formEnd = value
  }
  readonly property string formRecurrenceValue: {
    var r = formRecurrence
    return r && r.freq ? r.freq + ":" + (r.interval || 1) : ""
  }

  function alertLabel() {
    var v = root.formAlertMinutes
    if (!v) return ""
    if (v % 1440 === 0) return (v / 1440) + "d"
    if (v % 60 === 0) return (v / 60) + "h"
    return v + "m"
  }

  function applyEvents(raw) {
    var doc = Model.parseEventDocument(raw)
    root.eventDoc = doc
    root.visibleEventList = doc && doc.events ? doc.events : []
    root.eventIndex = Model.indexEventsByDate(root.visibleEventList)
    root.eventRevision += 1
  }

  function selectDay(key) {
    root.selectedDayKey = String(key)
  }

  function openThunderbirdCalendar() {
    root.close()
    if (root.bar && root.bar.run) root.bar.run(root.focusThunderbirdScript)
  }

  function openEntry(dayKey) {
    if (dayKey) root.selectedDayKey = String(dayKey)
    root.entryKind = "event"
    root.nlText = ""
    root.nlSegments = []
    root.nlCalendarName = ""
    root.openRows = []
    root.editingSegment = ""
    root.entryStatus = ""
    root.lastBuiltRequest = null
    // A calendar chosen last time must not outlive the pane: it may belong
    // to the other kind entirely.
    root.formCalendar = ""
    root.formCalendarChosen = false
    root.nlApplied = ({})
    root.formStart = ""
    root.formEnd = ""
    root.formEndDate = ""
    root.formLocation = ""
    root.formDescription = ""
    root.formLink = ""
    root.formAlertMinutes = 0
    root.formRecurrence = null
    root.formPriority = ""
    root.applyDraft(Model.fallbackDraft("", root.selectedDayKey, "event"))
    root.entryOpen = true
    Qt.callLater(function() {
      if (nlField) {
        nlField.setPhrase("")
        nlField.focusInput()
      }
    })
  }

  function closeEntry() {
    root.entryOpen = false
    root.entryStatus = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // The parse merged into what is on screen. Model.mergeEntryDraft owns the
  // rules — the phrase wins where it speaks, hand edits stand where it is
  // silent, and everything derived counts as the phrase's so the next parse
  // can move it. The calendar is settled here rather than there, because only
  // the pane knows which rosters Thunderbird offered.
  function applyDraft(d) {
    if (!d) return
    var merged = Model.mergeEntryDraft(d, {
      date: root.formDate,
      start: root.formStart,
      end: root.formEnd,
      endDate: root.formEndDate,
      location: root.formLocation,
      notes: root.formDescription,
      link: root.formLink,
      alert: root.formAlertMinutes,
      repeat: root.formRecurrenceValue,
      priority: root.formPriority
    }, root.nlApplied, root.entryKind)
    var v = merged.values

    root.formTitle = d.title || ""
    root.formDate = v.date || root.selectedDayKey
    root.formStart = v.start
    root.formEnd = v.end
    root.formEndDate = v.endDate
    root.formEndNextDay = v.endNextDay
    root.formLocation = v.location
    root.formDescription = v.notes
    root.formLink = v.link
    root.formDuration = d.durationMinutes || 0
    root.formAlertMinutes = v.alert
    root.setRecurrenceFrom(v.repeat)
    root.formPriority = v.priority
    root.nlApplied = merged.applied

    // A name out of the phrase still has to be a calendar this kind can be
    // written to: "/Aufgaben" on an event would land in a list that takes
    // tasks only, so it is ignored rather than silently mis-filed.
    if (d.calendarName && root.calendarValidForKind(d.calendarName)) {
      root.formCalendar = d.calendarName
      root.formCalendarChosen = true
    }
    root.ensureCalendarForKind()
  }

  function applyPhrase() {
    var known = []
    for (var i = 0; i < root.tbCalendars.length; i++)
      known.push(root.tbCalendars[i].name)
    var parsed = Model.parseEventPhrase(root.nlText, root.selectedDayKey, Date.now(), known)
    if (!parsed) parsed = Model.fallbackDraft(root.nlText, root.selectedDayKey, root.entryKind)
    parsed.kind = root.entryKind
    root.nlSegments = parsed.segments || []
    root.nlCalendarName = parsed.calendarName || ""
    root.applyDraft(parsed)
  }

  function assembleDraft() {
    var start = String(root.formStart || "").replace(/^\s+|\s+$/g, "")
    var end = String(root.formEnd || "").replace(/^\s+|\s+$/g, "")
    var wrap = root.formEndNextDay
    if (!wrap && start && end && end <= start) wrap = true
    return {
      kind: root.entryKind,
      title: root.formTitle,
      dateKey: root.formDate || root.selectedDayKey,
      endDateKey: root.formEndDate || null,
      startTime: start || null,
      endTime: end || null,
      endNextDay: wrap,
      durationMinutes: root.formDuration || null,
      allDay: root.formAllDay,
      location: root.formLocation || null,
      description: root.formDescription || null,
      calendarName: root.formCalendar || null,
      link: root.formLink || null,
      alertMinutes: root.formAlertMinutes || null,
      recurrence: root.formRecurrence,
      priority: root.formPriority || null
    }
  }

  function commitEntry() {
    var built = Model.buildQuickAddRequest(root.assembleDraft(), Date.now())
    if (!built.ok) {
      root.entryStatus = built.error || "could not create"
      return
    }
    root.lastBuiltRequest = built.request
    root.entryStatus = "Adding…"
    quickAddProc.command = [root.quickAddScript, JSON.stringify(built.request)]
    quickAddProc.running = true
  }

  function handleEntryKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.closeEntry()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      // Enter anywhere in the entry pane means Create — the form always
      // mirrors exactly what would be written.
      root.commitEntry()
      event.accepted = true
    }
  }

  function setEntryKind(kind) {
    root.entryKind = kind === "task" ? "task" : "event"
    if (root.nlText) root.applyPhrase()
    root.ensureCalendarForKind()
  }

  function applyCalendars(raw) {
    root.tbCalendars = Model.parseCalendarsDocument(raw)
    if (!root.formCalendar && root.calendarChoices.length)
      root.formCalendar = root.calendarChoices[0].value
  }

  function setRecurrenceFrom(value) {
    var text = String(value || "")
    if (!text) { root.formRecurrence = null; return }
    var parts = text.split(":")
    root.formRecurrence = { freq: parts[0], interval: parseInt(parts[1] || "1", 10) || 1 }
  }

  // Qt.openUrlExternally rather than the shell helper on purpose. That helper
  // runs `bash -lc`, and a meeting link is supplied by whoever sent the
  // invitation, so putting it through a shell would be a command injection.
  // Model.safeUrl also refuses anything that is not plain https.
  function openExternally(url) {
    if (!url) return
    Qt.openUrlExternally(url)
    root.close()
  }

  function openMeeting(event) {
    var url = Model.meetingUrlFor(event)
    if (!url) return
    if (root.hostWidget && typeof root.hostWidget.dismissReminder === "function")
      root.hostWidget.dismissReminder(event)
    root.openExternally(url)
  }

  function formatSelectedHeroLabel() {
    return Qt.formatDate(root.selectedDate, "MMMM d")
  }


  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function syncCalendars() {
    if (syncProc.running) return
    syncProc.running = true
  }

  function open() {
    eventsFile.reload()
    calendarsFile.reload()
    refresh()
    root.syncCalendars()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    if (root.entryOpen) root.closeEntry()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
    root.selectedDayKey = root.todayKey
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
    if (next.year === today.getFullYear() && next.month === today.getMonth())
      root.selectedDayKey = root.todayKey
    else
      root.selectedDayKey = Model.dateKey(next.year, next.month, 1)
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // Locale short day names, trimmed of the trailing period some locales
  // carry ("man." -> "MAN") so the header row stays a clean band of caps.
  function weekdayLabel(weekday) {
    return String(Qt.locale().dayName(weekday, Locale.ShortFormat)).replace(/\.$/, "").toUpperCase()
  }

  Process {
    id: syncProc
    command: [root.syncThunderbirdScript]
    running: false
  }

  Process {
    id: quickAddProc
    running: false
    onExited: function(exitCode) {
      if (exitCode === 0) {
        var summary = root.lastBuiltRequest ? Model.formatEntrySummary(root.lastBuiltRequest) : root.formTitle
        root.entryStatus = "✓  " + summary
        root.syncCalendars()
      } else {
        root.entryStatus = "could not write the request"
      }
    }
  }

  FileView {
    id: calendarsFile
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/thunderbird-calendars.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyCalendars(text())
    onLoadFailed: root.applyCalendars("")
    onFileChanged: reload()
  }

  FileView {
    id: eventsFile
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/calendar-events.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.applyEvents(text())
    onLoadFailed: root.applyEvents("")
    onFileChanged: reload()
  }

  Component.onCompleted: Qt.callLater(function() { eventsFile.reload() })

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(root.entryOpen ? entryColumn.implicitHeight : calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife || root.entryOpen
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.entryOpen ? root.closeEntry() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      Item {
        id: paneViewport
        anchors.fill: parent
        clip: true

      Item {
        id: overviewPane
        width: parent.width
        height: parent.height
        x: root.entryOpen ? -width : 0
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Hero: today, centered. Once the view has stepped back
          //      it is also the way home — clicking the date you are
          //      looking for beats hunting for a reset button.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                id: heroIcon
                // Baseline-aligned, not center-aligned: "July 26" carries a
                // descender, so centering the two boxes leaves the icon
                // sitting visibly low against the digits.
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroIconMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                // Decorative, and deliberately outside the Style.font.*
                // scale. Sized so the glyph reads at the cap height of the
                // date beside it rather than towering over it.
                font.pixelSize: 48
              }

              Text {
                id: heroDate
                anchors.verticalCenter: parent.verticalCenter
                text: root.formatSelectedHeroLabel()
                color: heroDateMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }
            }

            MouseArea {
              id: heroIconMouse
              x: heroRow.x + heroIcon.x
              y: heroRow.y + heroIcon.y
              width: heroIcon.width
              height: heroIcon.height
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.openThunderbirdCalendar()

              PanelToolTip {
                visible: heroIconMouse.containsMouse
                text: "Open Thunderbird calendar"
                fontFamily: root.contentFontFamily
              }
            }

            MouseArea {
              id: heroDateMouse
              x: heroRow.x + heroDate.x
              y: heroRow.y + heroDate.y
              width: heroDate.width
              height: heroDate.height
              enabled: root.selectedDayKey !== root.todayKey || !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroDateMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero:
          //      a plain hairline said nothing, and whole days done
          //      over days in the year says the same thing louder.
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "BORN"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "year"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 0
                  leftPadding: Style.space(6)
                  text: "LIVE TO"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento mori. Only here once someone has gone looking and
          //      given an age; the same rail as the year above it, measured
          //      against a nominal lifetime.
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LIFE"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.lifeDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: "Memento Mori"
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid: week numbers down a gutter on the left, then
          //      the seven day columns. Always six rows, so the popup is
          //      exactly as tall in February as it is in August.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              // The meter above is a solid rule; the grid needs room to
              // read as its own block rather than hanging off it.
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                // It is the one control in the panel whose meaning is not
                // self-evident, so it carries a tooltip naming the day the
                // click will switch to.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Item {
                      id: dayCell
                      required property var modelData
                      width: root.cellWidth
                      height: root.cellHeight

                      readonly property bool selected: modelData.key === root.selectedDayKey

                      // Thunderbird's own calendar colours, so work and personal
                      // days read apart here the way they do in Thunderbird. The
                      // dots carry that and nothing else: a cell washed in the
                      // calendar's colour would make "has something on it" a
                      // different shade every day, and that band is what the eye
                      // reads first when scanning the month.
                      readonly property var dayColors: modelData.colors || []

                      Rectangle {
                        anchors.fill: parent
                        radius: Style.cornerRadius
                        // Today outranks the selection, which starts on today
                        // anyway: the one cell you look for first gets the
                        // theme's strongest fill and a solid ring at double
                        // width, so it carries further than the translucent
                        // wash every day holding an event already has.
                        color: modelData.today
                          ? Style.selectionFillFor(root.contentForeground, Color.accent)
                          : parent.selected
                            ? Style.hoverFillFor(root.contentForeground, Color.accent)
                            : modelData.hasEvent
                              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
                              : "transparent"
                        border.width: modelData.today
                          ? Style.spacing.hairline * 2
                          : (parent.selected || modelData.hasEvent) ? Style.spacing.hairline : 0
                        border.color: modelData.today
                          ? Style.selectedBorderFor(root.contentForeground, Color.accent)
                          : parent.selected
                            ? Style.normalBorderFor(root.contentForeground, Color.accent)
                            : modelData.hasEvent
                              ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.5)
                              : Style.normalBorderFor(root.contentForeground, Color.accent)

                        Text {
                          anchors.centerIn: parent
                          anchors.verticalCenterOffset: modelData.hasEvent ? -Style.space(2) : 0
                          text: modelData.day
                          // Today is never dimmed, weekend or not: it sits on
                          // the brightest fill in the grid, and the muted
                          // weekend grey would leave the one date you came for
                          // the hardest to read.
                          color: modelData.today
                            ? root.contentForeground
                            : modelData.inMonth
                              ? (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground)
                              : Qt.darker(root.contentForeground, 2.2)
                          font.family: root.contentFontFamily
                          font.pixelSize: Style.font.body
                          font.bold: modelData.today
                        }

                        // One dot per calendar with something on that day. Three
                        // is what fits under a day number, so a fourth calendar
                        // goes without a dot rather than crowding the cell — the
                        // day list below still names everything.
                        Row {
                          anchors.horizontalCenter: parent.horizontalCenter
                          anchors.bottom: parent.bottom
                          anchors.bottomMargin: Style.space(3)
                          spacing: Style.space(2)
                          opacity: modelData.hasEvent ? 1 : 0

                          Repeater {
                            model: Math.min(Math.max(dayCell.dayColors.length, 1), 3)

                            Rectangle {
                              required property int index
                              width: Style.space(4)
                              height: Style.space(4)
                              radius: Style.space(2)
                              color: dayCell.dayColors[index] || Color.accent
                            }
                          }
                        }
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function(mouse) {
                          if (!modelData.inMonth) return
                          root.selectDay(modelData.key)
                          if (mouse.button === Qt.RightButton) root.openEntry(modelData.key)
                        }
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- Month stepping, spanning the grid it drives. The chevrons
          //      sit on the grid's outer bounds, the same edges the year
          //      rail above uses, so the row reads as the panel's other
          //      full-width rail instead of a cluster floating in space.
          //      The label is centered and fixed-width, so it holds still
          //      from "MAY" to "SEPTEMBER".
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the chevrons hold still between a
                // "MAY 2026" and a "SEPTEMBER 2026".
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                // Pulled out by the button's own padding so the glyph, not
                // its hit box, lines up with the "2026" on the year rail.
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          Column {
            visible: root.selectedEvents.length > 0 || !root.eventDoc
            width: gridColumn.width
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(6)

            Rectangle {
              width: parent.width
              height: Style.spacing.hairline
              color: root.contentForeground
              opacity: 0.12
            }

            Repeater {
              model: root.selectedEvents

              Item {
                id: eventRow
                required property var modelData
                readonly property string meetingUrl: Model.meetingUrlFor(modelData)
                readonly property bool joinable: meetingUrl !== ""
                readonly property int joinReserve: joinable ? joinButton.width + Style.space(8) : 0

                width: gridColumn.width
                height: Math.max(
                  eventTitle.implicitHeight + eventMeta.implicitHeight + Style.space(8),
                  joinable ? joinButton.height + Style.space(4) : 0
                )

                Rectangle {
                  width: Style.space(3)
                  height: parent.height - Style.space(4)
                  radius: 2
                  // The event's own calendar colour, matching the day dots above.
                  color: Model.eventColor(eventRow.modelData) || Color.accent
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  id: eventTitle
                  x: Style.space(10)
                  width: parent.width - Style.space(12) - eventRow.joinReserve
                  text: modelData.title || ""
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  id: eventMeta
                  x: Style.space(10)
                  y: eventTitle.implicitHeight + Style.space(2)
                  width: parent.width - Style.space(12) - eventRow.joinReserve
                  text: {
                    var time = Model.eventDisplayTime(modelData)
                    var loc = modelData.location || ""
                    if (eventRow.meetingUrl && loc.indexOf(eventRow.meetingUrl) !== -1) loc = ""
                    if (time && loc) return time + "  ·  " + loc
                    return time || loc
                  }
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                MouseArea {
                  anchors.fill: parent
                  anchors.rightMargin: eventRow.joinReserve
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openThunderbirdCalendar()
                }

                Rectangle {
                  id: joinButton
                  visible: eventRow.joinable
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: joinLabel.implicitWidth + Style.space(14)
                  height: joinLabel.implicitHeight + Style.space(7)
                  radius: height / 2
                  color: joinMouse.containsMouse
                    ? Style.selectedStateColor(root.contentForeground, Color.accent)
                    : "transparent"
                  border.width: Style.spacing.hairline
                  border.color: joinMouse.containsMouse
                    ? "transparent"
                    : Qt.darker(root.contentForeground, 2.0)

                  Text {
                    id: joinLabel
                    anchors.centerIn: parent
                    // Name the service: "Join Zoom" tells you what is about
                    // to open, and it is the same wording the bar uses for
                    // the next meeting.
                    text: Model.joinButtonLabel(eventRow.meetingUrl)
                    color: joinMouse.containsMouse
                      ? Color.background
                      : Qt.darker(root.contentForeground, 1.2)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  MouseArea {
                    id: joinMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openMeeting(eventRow.modelData)
                  }
                }
              }
            }

            Text {
              visible: !root.eventDoc
              text: "Waiting for Thunderbird calendar"
              color: Qt.darker(root.contentForeground, 1.8)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.italic: true
            }
          }
        }
      }
      }

      Item {
        id: entryPane
        width: parent.width
        height: parent.height
        x: root.entryOpen ? 0 : width
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Keys.onPressed: function(event) { root.handleEntryKey(event) }

        // Keys are owned by the entry pane only when no dropdown popup is
        // open — inside those, j/k/Enter belong to the option list.
        readonly property bool keysIdle:
          root.entryOpen && !calDropdown.popupOpen && !alertDropdown.popupOpen && !repeatDropdown.popupOpen && !priorityDropdown.popupOpen

        Shortcut {
          enabled: entryPane.keysIdle
          sequence: "Escape"
          onActivated: root.closeEntry()
        }

        Shortcut {
          enabled: entryPane.keysIdle
          sequence: "Ctrl+E"
          onActivated: root.setEntryKind("event")
        }

        Shortcut {
          enabled: entryPane.keysIdle
          sequence: "Ctrl+T"
          onActivated: root.setEntryKind("task")
        }

        Flickable {
          id: entryScroll
          anchors.fill: parent
          contentWidth: entryColumn.width
          contentHeight: entryColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          Column {
            id: entryColumn
            width: Math.max(entryScroll.width, gridColumn.width)
            spacing: Style.space(10)

            // Every row lines up on this. The entry pane runs wider than the
            // month grid it slid in over — the pills only sit on one line if
            // they get the pane's own width — so it takes the width back off
            // the pane rather than off the grid.
            readonly property real rowWidth: width - 2 * Style.space(40)

            // ---- Header: the way back on the left, what is being made in
            //      the middle, where it lands on the right.
            Item {
              width: entryColumn.rowWidth
              anchors.horizontalCenter: parent.horizontalCenter
              height: Math.max(backButton.height, kindTabs.height, calDropdown.height)

              PanelActionButton {
                id: backButton
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Back to calendar"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.closeEntry()
              }

              Row {
                id: kindTabs
                anchors.left: backButton.right
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(14)

                KindTab {
                  label: "EVENT"
                  active: root.entryKind === "event"
                  onActivated: root.setEntryKind("event")
                }

                KindTab {
                  label: "TASK"
                  active: root.entryKind === "task"
                  onActivated: root.setEntryKind("task")
                }
              }

              // The calendar the entry lands in, in the colour Thunderbird
              // gives it — the same dot the month grid paints on a day.
              Rectangle {
                visible: calDropdown.visible
                anchors.right: calDropdown.left
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(8)
                height: width
                radius: Style.cornerRadius > 0 ? width / 2 : 0
                color: root.roleCalendarColor
              }

              Dropdown {
                id: calDropdown
                visible: root.calendarChoices.length > 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(Style.space(150), parent.width * 0.36)
                showLabel: false
                label: root.entryKind === "task" ? "List" : "Calendar"
                value: root.formCalendar
                options: root.calendarChoices
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onChanged: function(v) { root.formCalendar = v; root.formCalendarChosen = true }
              }

              // No roster yet (add-on missing or old): a typed name still
              // gets matched at create time, so entry never blocks on it.
              TextField {
                visible: root.calendarChoices.length === 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(Style.space(150), parent.width * 0.36)
                placeholderText: root.entryKind === "task" ? "List" : "Calendar"
                foreground: root.contentForeground
                font.family: root.contentFontFamily
                text: root.formCalendar
                onTextEdited: { root.formCalendar = text; root.formCalendarChosen = true }
                Keys.onPressed: function(event) { root.handleEntryKey(event) }
              }
            }

            // ---- The phrase, painted as it is understood.
            Item {
              width: entryColumn.rowWidth
              anchors.horizontalCenter: parent.horizontalCenter
              height: nlField.height

              PhraseField {
                id: nlField
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                extraRightPadding: Style.space(18)
                phrase: root.nlText
                html: root.phraseMarkup
                placeholderText: root.entryKind === "task"
                  ? "buy groceries tomorrow !  /  einkaufen bis freitag"
                  : "lunch with Ana tomorrow 12:30 till 14:00  /  mittag 12:30 bis 14 Uhr"
                onEdited: function(text) {
                  root.nlText = text
                  root.applyPhrase()
                }
                onSubmitted: root.commitEntry()
                onCancelled: root.closeEntry()
              }

              // Hover examples: the whole grammar in one glance, since the
              // field itself only shows a single hint.
              Text {
                id: nlHelpIcon
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.top: parent.top
                anchors.topMargin: Style.space(8)
                text: "󰋗"
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body

                MouseArea {
                  id: nlHelpHover
                  anchors.fill: parent
                  anchors.margins: -Style.space(2)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                }

                PanelToolTip {
                  visible: nlHelpHover.containsMouse
                  text: root.entryKind === "task"
                    ? "Tasks · Aufgaben\n" +
                      "buy groceries tomorrow !            (low)\n" +
                      "finish report friday /Work !!       (medium)\n" +
                      "call mom sunday 6pm !!!             (high)\n" +
                      "water plants nächsten Montag -r1w  (weekly)\n" +
                      "einkaufen bis freitag               (due date)\n" +
                      "in Aufgaben  or  /Name              (list)"
                    : "Events · Termine\n" +
                      "lunch with Ana tomorrow 12:30 till 14:00\n" +
                      "mittag mit Ana morgen 12 bis 13 Uhr /Arbeit\n" +
                      "standup next monday 9am -a15m   (alert)\n" +
                      "flight 15.3. 7:00-9:30          (date + range)\n" +
                      "party today 21:00 till 2:00     (past midnight)\n" +
                      "retreat till 25.8.              (multi-day)\n" +
                      "workshop for 90m  /  -120       (duration)\n" +
                      "call https://zoom.us/j/9421     (meeting link)\n" +
                      "in Work  or  /Name              (calendar)"
                  fontFamily: root.contentFontFamily
                }
              }
            }

            Text {
              width: entryColumn.rowWidth
              anchors.horizontalCenter: parent.horizontalCenter
              visible: root.nlCalendarName !== "" && !root.calendarValidForKind(root.nlCalendarName)
              text: root.nlCalendarName
                + (root.entryKind === "task" ? " takes events only" : " takes tasks only")
                + (root.formCalendar !== "" ? " — using " + root.formCalendar : "")
              color: Qt.darker(root.contentForeground, 1.3)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }

            // ---- What the phrase came to. Click any value to correct just
            //      that value; the phrase above is left as it was typed.
            SlotEdit {
              slotName: "title"
              hero: true
              width: entryColumn.rowWidth
              anchors.horizontalCenter: parent.horizontalCenter
              display: root.formTitle !== "" ? root.formTitle : "Untitled"
              dim: root.formTitle === ""
              editValue: root.formTitle
              onCommitText: function(text) { root.formTitle = text }
            }

            // ---- When: start on the left, end on the right, the way the
            //      phrase reads. All-day collapses both times.
            BorderSurface {
              width: entryColumn.rowWidth
              anchors.horizontalCenter: parent.horizontalCenter
              radius: Style.cornerRadius
              color: Style.normalFillFor(root.contentForeground, Color.accent)
              borderSpec: Border.controlSpec("normal", root.contentForeground, Color.accent)
              implicitHeight: whenColumn.implicitHeight + 2 * Style.space(12)

              Column {
                id: whenColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(12)
                spacing: Style.space(10)

                Item {
                  width: parent.width
                  height: Math.max(startSide.height, endSide.height)

                  Column {
                    id: startSide
                    anchors.left: parent.left
                    anchors.top: parent.top
                    width: (parent.width - Style.space(28)) / 2
                    spacing: Style.space(2)

                    SlotEdit {
                      slotName: "startDate"
                      width: parent.width
                      display: root.dayLabel(root.formDate)
                      editValue: root.formDate
                      tint: root.roleDateColor
                      onCommitText: function(text) { root.commitStartDate(text) }
                    }

                    SlotEdit {
                      slotName: "startTime"
                      width: parent.width
                      strong: true
                      display: root.formAllDay
                        ? "all day"
                        : (root.formStart !== "" ? root.formStart : "set time")
                      dim: root.formAllDay || root.formStart === ""
                      editValue: root.formStart
                      tint: root.roleTimeColor
                      onCommitText: function(text) { root.commitStartTime(text) }
                    }
                  }

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Style.space(6)
                    visible: endSide.visible
                    text: "→"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.heading
                  }

                  Column {
                    id: endSide
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: (parent.width - Style.space(28)) / 2
                    spacing: Style.space(2)
                    visible: root.entryKind === "event"

                    SlotEdit {
                      slotName: "endDate"
                      width: parent.width
                      align: Text.AlignRight
                      display: root.dayLabel(root.entryEndDateKey())
                      editValue: root.entryEndDateKey()
                      tint: root.roleDateColor
                      onCommitText: function(text) { root.commitEndDate(text) }
                    }

                    SlotEdit {
                      slotName: "endTime"
                      width: parent.width
                      align: Text.AlignRight
                      strong: true
                      display: root.formAllDay
                        ? "all day"
                        : (root.formEnd !== "" ? root.formEnd : "set time")
                      dim: root.formAllDay || root.formEnd === ""
                      editValue: root.formEnd
                      tint: root.roleTimeColor
                      onCommitText: function(text) { root.commitEndTime(text) }
                    }
                  }
                }

                // A span that crosses midnight says so; nothing else needs
                // saying under the card now that all-day is just "no time".
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: root.formEndNextDay && !root.formAllDay && !root.formEndDate
                  text: "ends next day"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            // ---- Pills: the parts a phrase can carry but usually doesn't.
            //      A pill lights up when the phrase filled its part in, and
            //      opens the same row a click on it opens.
            Flow {
              width: entryColumn.rowWidth
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(6)

              Button {
                iconText: "󰌹"
                // The pill names the service once a link is in, so the row
                // does not have to be open to see what it is.
                text: root.formLink !== "" ? Model.linkProviderLabel(root.formLink) : "Link"
                bordered: true
                horizontalPadding: Style.space(7)
                selected: root.rowOpen("link")
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: {
                  root.toggleRow("link")
                  if (root.rowOpen("link")) linkField.forceActiveFocus()
                }
              }

              Button {
                iconText: "󰍎"
                text: "Location"
                bordered: true
                horizontalPadding: Style.space(7)
                selected: root.rowOpen("location")
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: {
                  root.toggleRow("location")
                  if (root.rowOpen("location")) locationField.forceActiveFocus()
                }
              }

              Button {
                iconText: "󰦨"
                text: "Notes"
                bordered: true
                horizontalPadding: Style.space(7)
                selected: root.rowOpen("notes")
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: {
                  root.toggleRow("notes")
                  if (root.rowOpen("notes")) notesField.focusInput()
                }
              }

              Button {
                iconText: "󰂚"
                text: "Notify me"
                bordered: true
                horizontalPadding: Style.space(7)
                visible: root.entryKind === "event"
                selected: root.rowOpen("alert")
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.toggleRow("alert")
              }

              Button {
                iconText: "󰑐"
                text: "Repeat"
                bordered: true
                horizontalPadding: Style.space(7)
                selected: root.rowOpen("repeat")
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.toggleRow("repeat")
              }

              Button {
                iconText: "󰈻"
                text: "Priority"
                bordered: true
                horizontalPadding: Style.space(7)
                visible: root.entryKind === "task"
                selected: root.rowOpen("priority")
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.toggleRow("priority")
              }
            }

            // ---- The opened parts themselves.
            Column {
              width: entryColumn.rowWidth
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(6)

              EntryRow {
                rowName: "link"
                icon: "󰌹"

                TextField {
                  id: linkField
                  width: parent.width
                  placeholderText: "https://zoom.us/j/…"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  text: root.formLink
                  onTextEdited: root.formLink = text
                  Keys.onPressed: function(event) { root.handleEntryKey(event) }
                }
              }

              EntryRow {
                rowName: "location"
                icon: "󰍎"

                TextField {
                  id: locationField
                  width: parent.width
                  placeholderText: "Location"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  text: root.formLocation
                  onTextEdited: root.formLocation = text
                  Keys.onPressed: function(event) { root.handleEntryKey(event) }
                }
              }

              EntryRow {
                rowName: "notes"
                icon: "󰦨"

                NotesField {
                  id: notesField
                  width: parent.width
                  placeholderText: "Notes"
                  value: root.formDescription
                  onEdited: function(text) { root.formDescription = text }
                  onCancelled: root.closeEntry()
                  onSubmitted: root.commitEntry()
                }
              }

              EntryRow {
                rowName: "alert"
                icon: "󰂚"
                visible: root.entryKind === "event" && root.rowOpen("alert")

                Dropdown {
                  id: alertDropdown
                  width: parent.width
                  showLabel: false
                  label: "Alert"
                  value: String(root.formAlertMinutes || 0)
                  options: Model.alertOptions(root.formAlertMinutes)
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onChanged: function(v) { root.formAlertMinutes = parseInt(v, 10) || 0 }
                }
              }

              EntryRow {
                rowName: "repeat"
                icon: "󰑐"

                Dropdown {
                  id: repeatDropdown
                  width: parent.width
                  showLabel: false
                  label: "Repeat"
                  value: root.formRecurrenceValue
                  options: Model.repeatOptions(root.formRecurrenceValue)
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onChanged: function(v) { root.setRecurrenceFrom(v) }
                }
              }

              EntryRow {
                rowName: "priority"
                icon: "󰈻"
                visible: root.entryKind === "task" && root.rowOpen("priority")

                Dropdown {
                  id: priorityDropdown
                  width: parent.width
                  showLabel: false
                  label: "Priority"
                  value: root.formPriority
                  options: [
                    { value: "", label: "No priority" },
                    { value: "low", label: "Low !" },
                    { value: "medium", label: "Medium !!" },
                    { value: "high", label: "High !!!" }
                  ]
                  foreground: root.contentForeground
                  fontFamily: root.contentFontFamily
                  onChanged: function(v) { root.formPriority = v }
                }
              }
            }

            Text {
              width: entryColumn.rowWidth
              anchors.horizontalCenter: parent.horizontalCenter
              visible: {
                if (root.nlText === "") return false
                return !Model.buildQuickAddRequest(root.assembleDraft(), Date.now()).ok
              }
              text: Model.buildQuickAddRequest(root.assembleDraft(), Date.now()).error || ""
              color: Qt.darker(root.contentForeground, 1.3)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }

            Button {
              width: entryColumn.rowWidth
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.entryKind === "task" ? "Add this task" : "Add this event"
              selected: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.commitEntry()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.closeEntry()
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  root.commitEntry()
                  event.accepted = true
                }
              }
            }

            Text {
              width: entryColumn.rowWidth
              anchors.horizontalCenter: parent.horizontalCenter
              visible: root.entryStatus !== ""
              text: root.entryStatus
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
      }
    }
  }
}
