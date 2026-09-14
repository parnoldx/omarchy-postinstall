import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// One-shot master-password dialog for vault-bridge, cloned from Omarchy's
// polkit agent card (Ui look: scrim, rounded card, lock glyph, error shake).
// vault-bridge spawns it with env vars; the password comes back through the
// file named by VB_RESULT_FILE. Exit 0 = password written, 3 = cancelled.
PanelWindow {
  id: root

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "vault-bridge-pinentry"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  // Injected by vault-bridge
  property string resultFile: Quickshell.env("VB_RESULT_FILE") || ""
  property string desc: Quickshell.env("VB_DESC") || ""
  property string errorText: Quickshell.env("VB_ERROR") || ""
  property bool hasError: errorText.length > 0

  // polkit palette, resolved by vault-bridge from the active Omarchy theme
  property color cardColor: Quickshell.env("VB_CARD") || "#1e1e2e"
  property color textColor: Quickshell.env("VB_TEXT") || "#cdd6f4"
  property color textErrorColor: Quickshell.env("VB_TEXT_ERROR") || "#f38ba8"
  property color borderIdle: Quickshell.env("VB_BORDER") || "#89b4fa"
  property color borderError: Quickshell.env("VB_BORDER_ERROR") || "#f38ba8"
  property color accentColor: Quickshell.env("VB_ACCENT") || "#89b4fa"
  property color scrimColor: Quickshell.env("VB_SCRIM") || "#801e1e2e"

  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property int fieldHeight: 44
  readonly property int cardWidth: 312
  readonly property int radius: 10

  property bool submitted: false
  property bool errorFlash: hasError
  property int shakeOffset: 0

  FileView {
    id: resultView
    path: root.resultFile
    atomicWrites: true
    printErrors: false
  }

  Timer {
    id: errorTimer
    interval: 1200
    onTriggered: root.errorFlash = false
  }

  SequentialAnimation {
    id: shakeAnimation
    NumberAnimation { target: shake; property: "x"; to: -8; duration: 35; easing.type: Easing.OutQuad }
    NumberAnimation { target: shake; property: "x"; to: 8; duration: 50; easing.type: Easing.InOutQuad }
    NumberAnimation { target: shake; property: "x"; to: 0; duration: 55; easing.type: Easing.OutQuad }
  }

  Component.onCompleted: {
    if (hasError) errorTimer.restart()
    passwordInput.forceActiveFocus()
  }

  function submit() {
    if (submitted) return
    submitted = true
    resultView.setText(passwordInput.text)
    Qt.exit(0)
  }

  function cancel() {
    submitted = true
    Qt.exit(3)
  }

  Rectangle {
    anchors.fill: parent
    color: root.scrimColor
  }

  MouseArea {
    anchors.fill: parent
    onClicked: passwordInput.forceActiveFocus()
  }

  Column {
    id: centerColumn
    anchors.centerIn: parent
    spacing: 10

    transform: Translate { id: shake; x: 0 }

    // The justification / error pill, like the polkit dialog's label above the card
    Rectangle {
      visible: root.desc.length > 0 || root.errorText.length > 0
      width: pillText.implicitWidth + 24
      height: 28
      radius: root.radius
      color: root.cardColor

      Text {
        id: pillText
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        text: root.hasError ? root.errorText : root.desc
        color: root.hasError ? root.textErrorColor : root.textColor
        font.family: root.fontFamily
        font.pixelSize: 12
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideMiddle
      }
    }

    Rectangle {
      id: card
      width: root.cardWidth
      height: root.fieldHeight + 20
      radius: root.radius
      color: root.cardColor
      border.width: 2
      border.color: root.errorFlash ? root.borderError : root.borderIdle

      Row {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 14

        Text {
          text: "\uf023"
          color: root.errorFlash ? root.textErrorColor : root.accentColor
          font.family: root.fontFamily
          font.pixelSize: 20
          width: 24
          height: root.fieldHeight
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }

        Item {
          width: parent.width - 40
          height: root.fieldHeight

          TextInput {
            id: passwordInput
            anchors.fill: parent
            verticalAlignment: TextInput.AlignVCenter
            activeFocusOnPress: true
            clip: true
            selectionColor: Qt.alpha(root.accentColor, 0.45)
            selectedTextColor: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 18
            echoMode: TextInput.Password
            passwordCharacter: "\u2022"
            color: root.errorFlash ? root.textErrorColor : root.textColor
            cursorVisible: activeFocus && !root.submitted
            enabled: !root.submitted
            onAccepted: root.submit()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancel()
                event.accepted = true
              }
            }
          }

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.errorFlash ? "Wrong" : "Enter password"
            color: root.errorFlash ? root.textErrorColor : root.textColor
            opacity: root.errorFlash ? 1 : 0.36
            font.family: root.fontFamily
            font.pixelSize: 18
            elide: Text.ElideRight
            visible: passwordInput.text.length === 0
          }

          Rectangle {
            width: 2
            height: 24
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            color: root.errorFlash ? root.textErrorColor : root.textColor
            visible: passwordInput.activeFocus && passwordInput.text.length === 0 && !root.submitted
          }

          MouseArea {
            anchors.fill: parent
            onClicked: passwordInput.forceActiveFocus()
          }
        }
      }
    }
  }

  // Test hook: VB_TEST_SUBMIT=<secret> auto-fills and submits after 600ms
  Timer {
    interval: 600
    running: (Quickshell.env("VB_TEST_SUBMIT") || "").length > 0
    onTriggered: {
      if (root.submitted) return
      passwordInput.text = Quickshell.env("VB_TEST_SUBMIT")
      root.submit()
    }
  }
}
