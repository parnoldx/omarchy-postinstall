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
  readonly property string toggleCmd: Quickshell.env("HOME") + "/.local/bin/handy-toggle"

  visible: busy
  implicitWidth: busy ? button.implicitWidth : 0
  implicitHeight: bar ? bar.barSize : 26

  function applyState(raw) {
    var line = String(raw || "").trim()
    if (line === "recording" || line === "transcribing" || line === "idle")
      handyState = line
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.transcribing ? "󰔟" : "󰍬"
    active: true
    useActiveColor: true
    tooltipText: root.recording ? "Recording — click to stop" : "Transcribing — click to cancel"
    onPressed: function() {
      if (!root.bar) return
      root.bar.run(root.toggleCmd)
    }
  }

  Process {
    id: statusProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/bar/scripts/handy-status"]
    running: true
    stdout: SplitParser {
      onRead: function(data) { root.applyState(data) }
    }
    onExited: restartTimer.restart()
  }

  Timer {
    id: restartTimer
    interval: 1000
    onTriggered: statusProc.running = true
  }
}
