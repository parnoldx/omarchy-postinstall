import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "pa.chord-expander"

  property Item anchorItem: null
  property Item hostWidget: null
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string cliPath: homeDir + "/.local/bin/chord-expander"
  readonly property string configPath: homeDir + "/.config/chord-expander/snippets.json"
  readonly property string submapPath: homeDir + "/.config/chord-expander/submap.lua"

  readonly property color fg: Color.foreground
  readonly property color dim: Qt.darker(Color.foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property string leader: "SUPER + E"
  property var entries: []
  property bool loading: true
  property bool configured: false
  property string statusText: ""

  function open() {
    controller.show()
    initProcess.running = true
  }

  function loadConfig(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      leader = String(parsed.leader || "SUPER + E")
      var next = []
      var snippets = parsed.snippets || {}
      var keys = Object.keys(snippets).sort()
      for (var i = 0; i < keys.length; i++) {
        var key = keys[i]
        next.push({ key: key, name: String(snippets[key].name || ""), text: String(snippets[key].text || "") })
      }
      entries = next
      loading = false
      if (list.currentIndex >= entries.length) list.currentIndex = Math.max(0, entries.length - 1)
    } catch (error) {
      statusText = "Could not read snippets.json"
    }
  }

  // Snippet edits only touch snippets.json. The submap is static, so there is
  // no bindings regeneration and no hyprctl reload here.
  function persist(nextEntries) {
    var snippets = {}
    for (var i = 0; i < nextEntries.length; i++) {
      var entry = nextEntries[i]
      snippets[entry.key] = { name: entry.name, text: entry.text }
    }
    entries = nextEntries
    configFile.setText(JSON.stringify({ version: 1, leader: leader, snippets: snippets }, null, 2) + "\n")
    statusText = "Saved"
  }

  function saveEntry(index, oldKey, keyValue, nameValue, textValue) {
    var key = String(keyValue || "").trim().toUpperCase()
    var name = String(nameValue || "").trim()
    if (!/^[A-Z0-9]{1,5}$/.test(key)) { statusText = "Trigger must be 1-5 letters or digits"; return false }
    if (name === "") { statusText = "Name cannot be empty"; return false }
    for (var i = 0; i < entries.length; i++)
      if (i !== index && entries[i].key === key) { statusText = key + " is already in use"; return false }

    var next = entries.slice()
    next[index] = { key: key, name: name, text: String(textValue || "") }
    next.sort(function(a, b) { return a.key.localeCompare(b.key) })
    persist(next)
    return true
  }

  function addEntry() {
    var alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    var used = {}
    for (var i = 0; i < entries.length; i++) used[entries[i].key] = true
    var key = ""
    for (var j = 0; j < alphabet.length; j++) if (!used[alphabet[j]]) { key = alphabet[j]; break }
    if (key === "") { statusText = "No free one-key chords"; return }
    var next = entries.slice()
    next.push({ key: key, name: "New snippet", text: "$" })
    next.sort(function(a, b) { return a.key.localeCompare(b.key) })
    persist(next)
    for (var k = 0; k < next.length; k++) if (next[k].key === key) list.currentIndex = k
    Qt.callLater(function() { if (list.currentItem) list.currentItem.beginEdit() })
  }

  function removeEntry(index) {
    var next = entries.slice()
    next.splice(index, 1)
    persist(next)
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onFileChanged: reload()
  }

  FileView {
    id: submapFile
    path: root.submapPath
    watchChanges: true
    printErrors: false
    onLoaded: root.configured = true
    onLoadFailed: root.configured = false
    onFileChanged: reload()
  }

  // Ensures snippets.json exists (the CLI's `path` creates it on first run).
  Process {
    id: initProcess
    running: false
    command: [root.cliPath, "path"]
    onExited: function() { configFile.reload(); submapFile.reload() }
  }

  // First-time setup: write the static submap + the guarded include line.
  Process {
    id: setupProcess
    running: false
    command: [root.cliPath, "install"]
    onExited: function(exitCode) {
      root.statusText = exitCode === 0 ? "Chord shortcuts enabled" : "Setup failed"
      configFile.reload(); submapFile.reload()
    }
  }

  // Changing the leader is the one edit that must regenerate the submap and
  // reload Hyprland; `install <leader>` does exactly that.
  Process {
    id: leaderProcess
    running: false
    property string value: ""
    command: [root.cliPath, "install", value]
    onExited: function(exitCode) {
      root.statusText = exitCode === 0 ? "Leader set to " + value : "Could not set leader"
      configFile.reload(); submapFile.reload()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: list
    contentWidth: panel.fittedContentWidth(Style.space(480))
    contentHeight: panel.fittedContentHeight(Math.min(Style.space(580), content.implicitHeight))

    ColumnLayout {
      id: content
      anchors.fill: parent
      spacing: Style.spacing.panelGap

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)
        Text {
          text: "Chord Expander"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          Layout.fillWidth: true
          text: root.leader + " then type a trigger  ·  " + root.leader + " twice for the picker  ·  N/+ add  ·  Enter edit  ·  Backspace remove"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }

      PanelSeparator { Layout.fillWidth: true }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.controlGap
        Text {
          text: "Leader"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        TextField {
          id: leaderField
          Layout.fillWidth: true
          text: root.leader
          onEditingFinished: {
            var value = text.trim()
            if (value !== "" && value !== root.leader) {
              leaderProcess.value = value
              leaderProcess.running = true
            } else if (value === "") {
              text = root.leader
            }
          }
        }
        Button {
          iconText: "󰐕"
          bordered: true
          tooltipText: "Add snippet"
          onClicked: root.addEntry()
        }
        Button {
          visible: !root.configured
          text: "Enable"
          bordered: true
          onClicked: setupProcess.running = true
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.controlGap
        PanelSectionHeader { text: "SNIPPETS"; Layout.fillWidth: true }
        Text {
          text: root.entries.length + (root.entries.length === 1 ? " chord" : " chords")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, Style.space(420))
        clip: true
        spacing: Style.space(6)
        model: root.entries
        currentIndex: root.entries.length > 0 ? 0 : -1
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
            currentIndex = Math.max(0, currentIndex - 1); positionViewAtIndex(currentIndex, ListView.Contain); event.accepted = true
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            currentIndex = Math.min(count - 1, currentIndex + 1); positionViewAtIndex(currentIndex, ListView.Contain); event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (currentItem) currentItem.beginEdit(); event.accepted = true
          } else if (event.key === Qt.Key_N || event.text === "+") {
            root.addEntry(); event.accepted = true
          } else if (event.key === Qt.Key_Backspace) {
            if (currentIndex >= 0) root.removeEntry(currentIndex)
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            root.close(); event.accepted = true
          }
        }

        delegate: CursorSurface {
          id: row
          required property int index
          required property var modelData
          width: ListView.view.width
          height: editing ? editor.implicitHeight + Style.space(16) : Style.space(52)
          current: ListView.isCurrentItem
          hasCursor: rowMouse.containsMouse && !editing

          property bool editing: false

          function beginEdit() {
            editing = true
            chordField.text = modelData.key
            nameField.text = modelData.name
            expansionField.text = modelData.text
            chordField.forceActiveFocus()
            chordField.selectAll()
          }

          function finishEdit() {
            if (root.saveEntry(index, modelData.key, chordField.text, nameField.text, expansionField.text)) {
              editing = false
              list.forceActiveFocus()
            }
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !row.editing
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              list.currentIndex = row.index
              row.beginEdit()
            }
          }

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            visible: !row.editing
            spacing: Style.space(12)

            Rectangle {
              implicitWidth: Math.max(Style.space(30), keyText.implicitWidth + Style.space(14))
              height: Style.space(30); radius: Style.cornerRadius
              color: Color.accent
              Text {
                id: keyText
                anchors.centerIn: parent
                text: row.modelData.key
                color: Color.background
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }
            ColumnLayout {
              Layout.fillWidth: true
              spacing: 1
              Text {
                text: row.modelData.name
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
              Text {
                text: row.modelData.text.replace(/\n/g, " ↵ ")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }
            Text { text: "↵"; color: root.dim; font.family: root.fontFamily }
          }

          ColumnLayout {
            id: editor
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: Style.space(9)
            visible: row.editing
            spacing: Style.space(7)

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.controlGap
              TextField { id: chordField; Layout.preferredWidth: Style.space(76); maximumLength: 5; placeholderText: "Trigger" }
              TextField { id: nameField; Layout.fillWidth: true; placeholderText: "Name" }
            }
            CursorSurface {
              bordered: true
              Layout.fillWidth: true
              Layout.preferredHeight: Style.space(108)
              ScrollView {
                anchors.fill: parent
                anchors.margins: Style.space(6)
                TextArea {
                  id: expansionField
                  background: null
                  color: root.fg
                  selectionColor: Style.selectionFill
                  selectedTextColor: root.fg
                  placeholderTextColor: Qt.darker(root.fg, 1.6)
                  placeholderText: "Expansion text — $ marks the cursor, $$ a literal $"
                  wrapMode: TextEdit.Wrap
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.controlGap
              Item { Layout.fillWidth: true }
              Button { text: "Delete"; bordered: true; onClicked: { root.removeEntry(row.index); list.forceActiveFocus() } }
              Button { text: "Cancel"; bordered: true; onClicked: { row.editing = false; list.forceActiveFocus() } }
              Button { text: "Save"; bordered: true; accent: Color.accent; onClicked: row.finishEdit() }
            }
          }
        }
      }

      PanelSeparator { Layout.fillWidth: true }

      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: "$ cursor  ·  $$ literal dollar  ·  select text then $ to wrap it"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          text: root.statusText
          visible: text !== ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
        }
      }
    }
  }
}
