import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "pa.dictation-answer"
  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    if (url.indexOf("file://") === 0) url = url.slice(7)
    return url.replace(/\/$/, "")
  }
  readonly property string defaultAnswerPath: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    return runtime ? runtime + "/voxtype-dictation/answer.json" : ""
  }

  property bool opened: false
  property string markdown: ""
  property string question: ""
  property var actions: []
  property var outputs: []
  property var blocks: []
  property int contentEpoch: 0
  property int toastOffset: 0
  property bool copied: false

  readonly property string barPosition: shell && shell.bar ? String(shell.bar.position || "top") : "top"
  readonly property bool barVertical: barPosition === "left" || barPosition === "right"
  readonly property int defaultBarSize: barVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  readonly property int liveBarSize: shell && shell.bar && !shell.bar.barHidden ? Math.max(0, shell.bar.barSize) : defaultBarSize
  readonly property int barClearance: liveBarSize + Style.gapsOut
  readonly property string fontFamily: shell && shell.bar && shell.bar.fontFamily ? shell.bar.fontFamily : Style.font.family

  readonly property color background: Color.notifications.background
  readonly property color foreground: Color.notifications.text
  readonly property color borderColor: Color.notifications.border
  readonly property var borderSpec: Border.surfaceSpec("notifications", "border", borderColor, Math.max(1, Style.space(2)))
  readonly property color dimColor: Qt.darker(foreground, 1.4)

  readonly property int cardWidth: Style.space(380)
  readonly property int headerPad: Style.space(12)

  function sanitizeMarkdown(raw) {
    var s = String(raw || "")
    s = s.replace(/!\[[^\]]*\]\([^)]*\)/g, "")
    s = s.replace(/<img\b[^>]*>/ig, "")
    // Text.MarkdownText ignores linkColor, so links are colored with an
    // inline style from the live theme accent instead.
    var accent = String(Color.accent)
    s = s.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g,
        "<a href=\"$2\" style=\"color: " + accent + "\"><span style=\"color: " + accent + "\">$1</span></a>")
    return s
  }

  function isSafeLink(link) {
    return /^(https?|mailto):/i.test(String(link || "").trim())
  }

  function toneColor(tone) {
    var t = String(tone || "").toLowerCase()
    if (t === "ok") return root.themeColors["green"] || "#41c46f"
    if (t === "warn") return root.themeColors["yellow"] || "#e0a83a"
    if (t === "danger") return root.themeColors["red"] || "#e05252"
    return Color.accent
  }

  property var themeColors: ({})

  FileView {
    id: themeColorsFile
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    onLoaded: {
      var map = {}
      var lines = String(text() || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
        if (m) map[m[1]] = m[2]
      }
      root.themeColors = map
    }
    onFileChanged: reload()
  }

  function applyAnswer(md, q, acts, outs, blks) {
    root.markdown = String(md || "")
    root.question = String(q || "")
    root.actions = Array.isArray(acts) ? acts : []
    root.outputs = Array.isArray(outs) ? outs : []
    root.blocks = (Array.isArray(blks) && blks.length > 0)
        ? blks : [{ type: "md", text: String(md || "") }]
    // Any answer update may carry regenerated image files behind unchanged
    // paths -- bump the epoch so Image URLs change and Qt re-decodes them.
    root.contentEpoch++
    root.copied = false
    copiedTimer.stop()
    root.opened = true
  }

  function loadFromFile(path) {
    var target = String(path || "").trim()
    if (!target) target = root.defaultAnswerPath
    answerFile.path = target
    answerFile.reload()
  }

  function parseAnswerText(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      if (data && typeof data === "object")
        return {
          markdown: String(data.markdown || ""),
          question: String(data.question || ""),
          actions: Array.isArray(data.actions) ? data.actions : [],
          outputs: Array.isArray(data.outputs) ? data.outputs : [],
          blocks: (Array.isArray(data.blocks) && data.blocks.length > 0)
              ? data.blocks : [{ type: "md", text: String(data.markdown || "") }]
        }
    } catch (e) {}
    return { markdown: String(raw || ""), question: "", actions: [], outputs: [],
             blocks: [{ type: "md", text: String(raw || "") }] }
  }

  function runAction(index) {
    var home = Quickshell.env("HOME")
    if (!home) return
    Quickshell.execDetached([home + "/.local/bin/voxtype-dictation", "card-action", String(index)])
  }

  function open(payloadJson) {
    var args = {}
    try { args = JSON.parse(String(payloadJson || "{}")) } catch (e) { args = {} }
    if (args.markdown) {
      applyAnswer(args.markdown, args.question || "")
      return
    }
    root.opened = true
    loadFromFile(args.file || root.defaultAnswerPath)
  }

  function close() { root.opened = false }

  function dismiss(discard) {
    root.opened = false
    if (discard !== false) {
      var home = Quickshell.env("HOME")
      if (home)
        Quickshell.execDetached([home + "/.local/bin/voxtype-dictation", "card-discard"])
    }
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function copyAnswer() {
    var text = root.markdown
    if (!text) return
    Quickshell.execDetached(["wl-copy", "--", text])
    root.copied = true
    copiedTimer.restart()
  }

  function continueInHerdr() {
    var home = Quickshell.env("HOME")
    if (!home) return
    Quickshell.execDetached([home + "/.local/bin/voxtype-dictation", "continue-in-herdr"])
    // The handoff marks the session as resumed; keep it alive, so no discard.
    root.dismiss(false)
  }

  Timer {
    id: copiedTimer
    interval: 1500
    onTriggered: root.copied = false
  }

  FileView {
    id: answerFile
    watchChanges: true
    printErrors: false
    onLoaded: {
      var parsed = root.parseAnswerText(text())
      root.applyAnswer(parsed.markdown, parsed.question, parsed.actions, parsed.outputs, parsed.blocks)
    }
  }

  Process {
    id: toastProc
    command: [root.pluginDir + "/toast-offset"]
    running: root.opened
    stdout: SplitParser {
      onRead: function(data) {
        var n = parseInt(String(data || "").trim(), 10)
        if (!isNaN(n) && n >= 0) root.toastOffset = n
      }
    }
    onExited: if (root.opened) toastRestart.restart()
  }

  Timer {
    id: toastRestart
    interval: 1000
    onTriggered: if (root.opened) toastProc.running = true
  }

  onOpenedChanged: if (!opened) toastOffset = 0

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData
      visible: root.opened
      color: "transparent"
      WlrLayershell.namespace: "pa-dictation-answer"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      anchors { top: true; bottom: true; left: true; right: true }
      mask: Region { item: card }

      readonly property int topClearance: root.barPosition === "top" ? root.barClearance : Style.gapsOut
      readonly property int rightClearance: root.barPosition === "right" ? root.barClearance : Style.gapsOut
      readonly property real screenH: panel.screen ? panel.screen.height : 800
      readonly property int maxCardHeight: Math.max(
        Style.space(160),
        Math.round(screenH - topClearance - root.toastOffset - Style.gapsOut * 2))

      BorderSurface {
        id: card
        width: root.cardWidth
        height: Math.min(panel.maxCardHeight, implicitCardHeight)
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: panel.topClearance + root.toastOffset
        anchors.rightMargin: panel.rightClearance
        color: root.background
        borderSpec: root.borderSpec
        radius: Style.cornerRadius

        readonly property int innerPad: root.headerPad
        readonly property int actionsSpace: actionsRow.visible ? Style.space(8) + Math.ceil(actionsRow.implicitHeight) : 0
        readonly property int implicitCardHeight: innerPad + headerRow.implicitHeight
          + Style.space(8) + Math.ceil(bodyColumn.implicitHeight) + innerPad
          + actionsSpace + borderTop + borderBottom

        Behavior on anchors.topMargin { NumberAnimation { duration: 120 } }

        ColumnLayout {
          id: layout
          anchors.fill: parent
          anchors.topMargin: card.borderTop + card.innerPad
          anchors.rightMargin: card.borderRight + card.innerPad
          anchors.bottomMargin: card.borderBottom + card.innerPad
          anchors.leftMargin: card.borderLeft + card.innerPad
          spacing: Style.space(8)

          RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: Style.space(8)

            Text {
              Layout.fillWidth: true
              text: root.question !== "" ? root.question : "Answer"
              textFormat: Text.PlainText
              color: root.question !== "" ? root.dimColor : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
              maximumLineCount: 2
              wrapMode: Text.Wrap
            }

            PanelActionButton {
              iconText: root.copied ? "󰄬" : "󰆏"
              tooltipText: root.copied ? "Copied" : "Copy"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.copyAnswer()
            }

            PanelActionButton {
              iconText: "󰆍"
              tooltipText: "Continue in Herdr"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.continueInHerdr()
            }

            PanelActionButton {
              iconText: "󰅖"
              tooltipText: "Dismiss"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.dismiss()
            }
          }

          Flickable {
            id: flicker
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: bodyColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Column {
              id: bodyColumn
              width: flicker.width
              spacing: Style.space(8)

              Repeater {
                model: root.blocks

                delegate: Column {
                  id: contentBlock
                  required property var modelData
                  width: parent ? parent.width : 0
                  spacing: 0

                  Text {
                    id: contentMd
                    visible: contentBlock.modelData.type === "md"
                    width: parent.width
                    text: root.sanitizeMarkdown(contentBlock.modelData.text || "")
                    textFormat: Text.MarkdownText
                    linkColor: Color.accent
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    wrapMode: Text.Wrap
                    onLinkActivated: function(link) {
                      if (root.isSafeLink(link))
                        Quickshell.execDetached(["xdg-open", link])
                    }

                    HoverHandler {
                      cursorShape: contentMd.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }
                  }

                  Image {
                    id: contentImg
                    visible: contentBlock.modelData.type === "img"
                    width: parent.width
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: false
                    source: visible && contentBlock.modelData.path
                        ? "file://" + contentBlock.modelData.path + "?e=" + root.contentEpoch : ""
                    height: visible ? Math.min(Style.space(320), Math.round(width * implicitHeight / Math.max(1, implicitWidth))) : 0
                  }

                  Text {
                    visible: contentBlock.modelData.type === "img" && contentImg.status === Image.Error
                    width: parent.width
                    text: "\u25B8 image unavailable: " + String(contentBlock.modelData.path || "")
                    textFormat: Text.PlainText
                    color: root.dimColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.Wrap
                  }

                  Rectangle {
                    visible: contentBlock.modelData.type === "color"
                    width: parent.width
                    radius: Style.cornerRadius / 2
                    color: Qt.alpha(root.toneColor(contentBlock.modelData.tone), 0.14)
                    implicitHeight: visible ? calloutText.implicitHeight + Style.space(12) : 0

                    Rectangle {
                      anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                        margins: Style.space(3)
                      }
                      width: 3
                      radius: 1.5
                      color: root.toneColor(contentBlock.modelData.tone)
                    }

                    Text {
                      id: calloutText
                      anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: Style.space(6)
                        leftMargin: Style.space(12)
                      }
                      text: root.sanitizeMarkdown(contentBlock.modelData.text || "")
                      textFormat: Text.MarkdownText
                      linkColor: Color.accent
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      wrapMode: Text.Wrap
                      onLinkActivated: function(link) {
                        if (root.isSafeLink(link))
                          Quickshell.execDetached(["xdg-open", link])
                      }
                    }
                  }
                }
              }

              Repeater {
                model: root.outputs

                delegate: Rectangle {
                  required property var modelData
                  width: parent ? parent.width : 0
                  color: Qt.alpha(root.foreground, 0.06)
                  radius: Style.cornerRadius / 2
                  implicitHeight: outputText.implicitHeight + Style.space(10)

                  Text {
                    id: outputText
                    anchors {
                      left: parent.left; right: parent.right
                      top: parent.top; margins: Style.space(5)
                    }
                    text: "\u25B8 " + (modelData.label || "output") + "\n" + String(modelData.text || "")
                    textFormat: Text.PlainText
                    color: root.dimColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.Wrap
                  }
                }
              }
            }
          }

          Flow {
            id: actionsRow
            visible: root.actions.length > 0
            Layout.fillWidth: true
            spacing: Style.space(6)

            Repeater {
              model: root.actions

              delegate: Rectangle {
                id: actionButton
                required property var modelData
                required property int index
                width: actionLabel.implicitWidth + Style.space(16)
                height: actionLabel.implicitHeight + Style.space(8)
                radius: Style.cornerRadius / 2
                color: actionMouse.pressed ? Qt.alpha(root.foreground, 0.18)
                                           : Qt.alpha(root.foreground, 0.09)
                border.color: Qt.alpha(root.foreground, 0.25)
                border.width: 1

                Text {
                  id: actionLabel
                  anchors.centerIn: parent
                  text: actionButton.modelData.label || "?"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: actionMouse
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.runAction(actionButton.index)
                }
              }
            }
          }
        }

        // Same as notification toasts: right-click anywhere on the card dismisses.
        // Left button is not accepted, so flicks, copy, and links still work.
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.RightButton
          onClicked: root.dismiss()
        }
      }
    }
  }
}
