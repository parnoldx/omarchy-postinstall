import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

Item {
  id: root

  property var bar
  property string moduleName
  property var settings
  property string voxState: "idle"

  readonly property bool recording: voxState === "recording"
  readonly property bool transcribing: voxState === "transcribing"
  readonly property bool agenting: voxState === "agent"
  readonly property bool busy: recording || transcribing || agenting
  readonly property string interruptCmd: Quickshell.env("HOME") + "/.local/bin/voxtype-dictation interrupt"

  visible: busy
  readonly property bool showMeter: recording && !(bar && bar.vertical)
  readonly property int meterWidth: showMeter ? meter.width : 0
  implicitWidth: busy ? button.implicitWidth + meterWidth : 0
  implicitHeight: bar ? bar.barSize : 26

  BarIconButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    bar: root.bar

    // Same color as the upstream dictation indicator: bar.urgent while active.
    readonly property color activeColor: root.bar ? root.bar.urgent : "#ff4455"
    text: root.agenting ? "󱚣" : (root.transcribing ? "󰔟" : "󰍬")
    active: true
    useActiveColor: true
    tooltipText: root.recording
      ? "Recording — click to stop"
      : (root.agenting ? "Agent — click to cancel" : "Transcribing — click to cancel")
    onPressed: function() {
      if (!root.bar) return
      root.bar.run(root.interruptCmd)
    }
  }

  // Live mic level from voxtype's audio.sock, sampled into a short history
  // that drives the wave bands (newest sample at the right).
  property real level: 0
  property var history: []
  readonly property int bands: 6
  onRecordingChanged: history = []

  Timer {
    interval: 70
    running: root.recording
    repeat: true
    onTriggered: {
      var h = root.history.slice()
      h.unshift(root.level)
      if (h.length > root.bands) h.pop()
      root.history = h
    }
  }

  // Same wave as the YouTube Music indicator (centered rounded bars growing
  // both ways, opacity by level, 60 ms ease), just narrower.
  Item {
    id: meter
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: root.bands * 4 - 2
    height: parent.height * 0.55
    visible: root.showMeter

    Repeater {
      model: root.bands
      Rectangle {
        required property int index
        readonly property real v: root.history[index] || 0
        x: index * 4
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        radius: 1
        height: Math.max(2, parent.height * (0.12 + 0.88 * v))
        color: button.activeColor
        opacity: 0.45 + 0.55 * v
        Behavior on height { NumberAnimation { duration: 60; easing.type: Easing.OutQuad } }
      }
    }
  }

  Process {
    id: levelProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/bar/scripts/voxtype-levels"]
    running: true
    stdout: SplitParser {
      onRead: function(data) {
        var v = parseFloat(String(data || "").trim())
        if (!isNaN(v)) root.level = Math.max(0, Math.min(1, v))
      }
    }
    onExited: levelRestartTimer.restart()
  }

  Timer {
    id: levelRestartTimer
    interval: 500
    onTriggered: levelProc.running = true
  }

  Process {
    id: statusProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/bar/scripts/voxtype-status"]
    running: true
    stdout: SplitParser {
      onRead: function(data) {
      var line = String(data || "").trim()
      if (line === "recording" || line === "transcribing" || line === "agent" || line === "idle")
        root.voxState = line
    }
    }
    onExited: restartTimer.restart()
  }

  Timer {
    id: restartTimer
    interval: 1000
    onTriggered: statusProc.running = true
  }
}
