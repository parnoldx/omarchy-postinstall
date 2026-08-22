import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TileMath.js" as TileMath
import "RadarModel.js" as RadarModel

// Compact RainViewer map for the weather popup. Shown only while rain is
// falling here or forecast today; height 0 otherwise so a dry day does
// not grow the panel. Tile math and the RainViewer client follow
// eduardodallecort/omarchy-weather-radar.
Item {
  id: root

  property var bar: null
  property real latitude: 0
  property real longitude: 0
  property bool shown: false

  visible: shown
  height: shown ? implicitHeight : 0
  clip: true
  implicitHeight: column.implicitHeight

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool darkTheme: {
    var background = Color.background
    return (0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b) < 0.5
  }
  readonly property string basemapStyle: darkTheme ? "dark_all" : "light_all"
  readonly property int colorSchemeId: 2
  readonly property bool smoothTiles: true
  readonly property bool showSnow: true

  property real viewLatitude: 0
  property real viewLongitude: 0
  property int zoom: 9
  property bool panned: false
  readonly property int radarSourceZoom: Math.min(zoom, RadarModel.MAX_RADAR_ZOOM)

  property var radarManifest: null
  readonly property var frames: radarManifest ? radarManifest.past : []
  readonly property string tileHost: radarManifest ? radarManifest.host : ""
  property int frameIndex: 0
  property bool playing: true
  property int frameA: -1
  property int frameB: -1
  property bool frontIsA: true

  readonly property var currentFrame: {
    if (!frames || frames.length === 0) return null
    var index = Math.max(0, Math.min(frames.length - 1, frameIndex))
    return frames[index]
  }
  readonly property string frameLabel: currentFrame ? RadarModel.formatFrameTime(currentFrame.time) : "--:--"
  readonly property bool isLatestFrame: frames.length > 0 && frameIndex >= frames.length - 1

  property bool coverageChecked: false
  property bool hasCoverage: true
  readonly property bool coverageMissing: coverageChecked && !hasCoverage
  readonly property string coverageProbeUrl: {
    if (!shown || !tileHost || !isFinite(latitude) || !isFinite(longitude)) return ""
    if (coverageChecked) return ""
    return RadarModel.coverageTileUrl(tileHost, 256, RadarModel.MAX_RADAR_ZOOM, latitude, longitude)
  }

  function recenter() {
    if (!isFinite(latitude) || !isFinite(longitude)) return
    viewLatitude = latitude
    viewLongitude = longitude
  }

  function maybeRecenter() {
    if (panned) return
    Qt.callLater(function() {
      if (!root.panned) root.recenter()
    })
  }

  onLatitudeChanged: {
    coverageChecked = false
    hasCoverage = true
    maybeRecenter()
  }
  onLongitudeChanged: {
    coverageChecked = false
    hasCoverage = true
    maybeRecenter()
  }

  onShownChanged: {
    if (shown) {
      playing = true
      if (!panned) recenter()
      refreshManifest()
      Qt.callLater(function() { coverageProbe.probe() })
    } else {
      playing = false
    }
  }

  onFramesChanged: {
    if (frames.length === 0) return
    if (frameIndex >= frames.length - 1 || frameIndex === 0) frameIndex = frames.length - 1
    if (frameA < 0) {
      frameA = frameIndex
      frontIsA = true
    }
  }

  onFrameIndexChanged: showFrame(frameIndex)

  function showFrame(index) {
    if (index < 0 || frames.length === 0) return
    if (frontIsA) frameB = index
    else frameA = index
    frontIsA = !frontIsA
  }

  function radarTileUrlForFrame(index, z, x, y) {
    if (!shown || !tileHost) return ""
    if (index < 0 || index >= frames.length) return ""
    return RadarModel.tileUrl(tileHost, frames[index].path, 256, z, x, y, colorSchemeId, smoothTiles, showSnow)
  }

  function basemapTileUrl(z, x, y) {
    if (!shown) return ""
    return "https://basemaps.cartocdn.com/" + basemapStyle + "/" + z + "/" + x + "/" + y + ".png"
  }

  function radarTileUrlA(z, x, y) { return radarTileUrlForFrame(frameA, z, x, y) }
  function radarTileUrlB(z, x, y) { return radarTileUrlForFrame(frameB, z, x, y) }

  function refreshManifest() {
    if (!shown || manifestProc.running) return
    manifestProc.command = ["curl", "-fsS", "--max-time", "10", RadarModel.MANIFEST_URL]
    manifestProc.running = true
  }

  Process {
    id: manifestProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = RadarModel.parseManifest(text)
        if (parsed) root.radarManifest = parsed
      }
    }
  }

  Timer {
    interval: RadarModel.FRAME_INTERVAL_SEC * 1000
    repeat: true
    running: root.shown
    onTriggered: root.refreshManifest()
  }

  Timer {
    id: playbackTimer
    interval: root.isLatestFrame ? 1500 : 550
    repeat: true
    running: root.playing && root.shown && root.frames.length > 1
    onTriggered: {
      if (root.frameIndex >= root.frames.length - 1) root.frameIndex = 0
      else root.frameIndex++
    }
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(10)

    Rectangle {
      width: parent.width
      height: Style.spacing.hairline
      color: root.fg
      opacity: 0.12
    }

    Item {
      id: mapArea
      width: parent.width
      height: Style.space(240)

      Rectangle {
        anchors.fill: parent
        color: root.darkTheme ? "#101014" : "#e8e8ec"
        radius: Style.cornerRadius
        clip: true

        TileLayer {
          anchors.fill: parent
          centerLatitude: root.viewLatitude
          centerLongitude: root.viewLongitude
          zoom: root.zoom
          tileUrlFor: root.basemapTileUrl
        }

        TileLayer {
          anchors.fill: parent
          centerLatitude: root.viewLatitude
          centerLongitude: root.viewLongitude
          zoom: root.zoom
          sourceZoom: root.radarSourceZoom
          tileUrlFor: root.radarTileUrlA
          revision: root.frameA + (root.colorSchemeId * 1000)
          smooth: root.smoothTiles
          opacity: root.frontIsA ? 1 : 0
          Behavior on opacity {
            NumberAnimation { duration: 380; easing.type: Easing.InOutQuad }
          }
        }

        TileLayer {
          anchors.fill: parent
          centerLatitude: root.viewLatitude
          centerLongitude: root.viewLongitude
          zoom: root.zoom
          sourceZoom: root.radarSourceZoom
          tileUrlFor: root.radarTileUrlB
          revision: root.frameB + (root.colorSchemeId * 1000)
          smooth: root.smoothTiles
          opacity: root.frontIsA ? 0 : 1
          Behavior on opacity {
            NumberAnimation { duration: 380; easing.type: Easing.InOutQuad }
          }
        }

        Item {
          anchors.fill: parent
          visible: root.shown && isFinite(root.latitude) && isFinite(root.longitude)

          readonly property var home: TileMath.projectToViewport(
            root.latitude, root.longitude,
            root.viewLatitude, root.viewLongitude,
            root.zoom, parent.width, parent.height)

          Rectangle {
            readonly property real dot: Style.space(7)
            x: parent.home.x - dot / 2
            y: parent.home.y - dot / 2
            width: dot
            height: dot
            radius: dot / 2
            color: Color.accent
            border.color: root.darkTheme ? "#000000" : "#ffffff"
            border.width: 1
          }
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton
          cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor

          property real lastX: 0
          property real lastY: 0

          onPressed: function(mouse) {
            lastX = mouse.x
            lastY = mouse.y
          }

          onPositionChanged: function(mouse) {
            if (!pressed) return
            var dx = mouse.x - lastX
            var dy = mouse.y - lastY
            if (dx === 0 && dy === 0) return
            lastX = mouse.x
            lastY = mouse.y

            var moved = TileMath.unprojectFromViewport(
              width / 2 - dx, height / 2 - dy,
              root.viewLatitude, root.viewLongitude,
              root.zoom, width, height)
            root.viewLatitude = moved.latitude
            root.viewLongitude = moved.longitude
            root.panned = true
          }

          onWheel: function(wheel) {
            var direction = wheel.angleDelta.y > 0 ? 1 : -1
            var next = Math.max(RadarModel.MIN_RADAR_ZOOM,
              Math.min(RadarModel.MAX_MAP_ZOOM, root.zoom + direction))
            if (next !== root.zoom) root.zoom = next
            wheel.accepted = true
          }

          onDoubleClicked: {
            root.panned = false
            root.recenter()
          }
        }

        Text {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(6)
          text: "RainViewer · CARTO · OpenStreetMap"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption * 0.8
          opacity: 0.4
        }

        Canvas {
          id: coverageProbe
          width: 256
          height: 256
          opacity: 0
          z: -1

          property string probeUrl: root.coverageProbeUrl

          function probe() {
            if (probeUrl === "") return
            if (isImageLoaded(probeUrl)) requestPaint()
            else loadImage(probeUrl)
          }

          onProbeUrlChanged: probe()
          onImageLoaded: requestPaint()

          onPaint: {
            if (probeUrl === "" || !isImageLoaded(probeUrl)) return
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.drawImage(probeUrl, 0, 0, width, height)
            var pixels = ctx.getImageData(0, 0, width, height).data
            root.hasCoverage = RadarModel.hasCoverageAtCenter(pixels, width)
            root.coverageChecked = true
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.shown && root.frames.length === 0
          text: "Loading radar…"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          opacity: 0.6
        }
      }
    }

    Item {
      width: parent.width
      height: Style.spacing.controlHeight
      visible: root.frames.length > 1

      Button {
        id: playButton
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: root.playing ? "󰏤" : "󰐊"
        fontFamily: root.fontFamily
        foreground: root.fg
        tooltipText: root.playing ? "Pause" : "Play the last two hours"
        onClicked: root.playing = !root.playing
      }

      PanelSlider {
        id: timeline
        anchors.left: playButton.right
        anchors.right: frameTime.left
        anchors.leftMargin: Style.space(8)
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        bar: root.bar
        minimum: 0
        maximum: Math.max(1, root.frames.length - 1)
        integer: true
        step: 1
        tickCount: root.frames.length
        value: root.frameIndex
        onMoved: function(value) {
          root.playing = false
          root.frameIndex = Math.round(value)
        }
      }

      Text {
        id: frameTime
        anchors.right: parent.right
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(44)
        horizontalAlignment: Text.AlignRight
        text: root.frameLabel
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        opacity: root.isLatestFrame ? 0.9 : 0.6
      }
    }

    Text {
      visible: root.coverageMissing
      width: parent.width
      leftPadding: Style.space(8)
      text: "No radar coverage at this location"
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      opacity: 0.9
    }
  }
}
