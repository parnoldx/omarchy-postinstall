import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

Item {
  id: root

  property var bar
  property string moduleName
  property var settings
  property string handyState: "idle"

  readonly property bool recording: handyState === "recording"
  readonly property bool transcribing: handyState === "transcribing"
  readonly property bool busy: recording || transcribing

  visible: busy
  implicitWidth: busy ? button.implicitWidth : 0
  implicitHeight: bar ? bar.barSize : 26

  function applyLine(raw) {
    var line = String(raw || "")
    if (line.indexOf("tray icon change (Recording)") !== -1
        || line.indexOf("Recording started") !== -1)
      handyState = "recording"
    else if (line.indexOf("tray icon change (Transcribing)") !== -1
        || line.indexOf("Starting async transcription") !== -1)
      handyState = "transcribing"
    else if (line.indexOf("tray icon change (Idle)") !== -1
        || line.indexOf("returned to idle state") !== -1)
      handyState = "idle"
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.transcribing ? "󰔟" : "󰍬"
    active: true
    useActiveColor: true
    tooltipText: root.recording ? "Recording — click to stop" : "Inserting — click to cancel"
    onPressed: function() {
      if (!root.bar) return
      root.bar.run(root.transcribing ? "handy --cancel" : "handy --toggle-transcription")
    }
  }

  Process {
    id: statusProc
    command: [
      "stdbuf", "-oL", "tail", "-n", "80", "-F",
      Quickshell.env("HOME") + "/.local/share/com.pais.handy/logs/handy.log"
    ]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.applyLine(data) }
    }
    onExited: restartTimer.restart()
  }

  Timer {
    id: restartTimer
    interval: 1000
    onTriggered: statusProc.running = true
  }
}
