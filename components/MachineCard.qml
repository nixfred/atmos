import QtQuick
import "../services"
import "../services/CardArt.js" as CardArtJs
import "../services/CardLayout.js" as CardLayoutJs

// Lab(machinecard): renders a layout the agent designed.
//
// This draws data, never code. Positions arrive as fractions of the canvas,
// colours as role names resolved against the user's own theme, and the art
// is one of a fixed set of motifs. A reply this does not understand makes a
// plainer card, never an unsafe one.
//
// The agent owns the arrangement. Atmos owns three things it will not
// delegate: the Omarchy mark is always present, every spec row is always
// present, and the type always sits on enough scrim to be read. Those are
// what make a wildly different card still obviously an Atmos card.
//
// Rendered at true output size rather than scaled on export, so the file you
// save is the card you previewed.

Item {
  id: root

  property var card: ({ title: "", tagline: "", rows: [] })
  property var layout: CardLayoutJs.defaultLayout()
  // The scene the agent drew. When present it replaces the procedural art
  // entirely -- a real illustration beats a texture every time, and the
  // motif engine stays only as the instant fallback before the agent answers
  // or when it cannot.
  property string sceneSvg: ""
  property string logoPath: "/usr/share/omarchy/logo.svg"

  implicitWidth: 1920
  implicitHeight: 1080
  width: implicitWidth
  height: implicitHeight

  readonly property real u: height / 1080
  readonly property var rows: (card && card.rows) || []

  function roleColor(name) {
    if (name === "accent") return Theme.accent
    if (name === "muted") return Theme.muted
    if (name === "background") return Theme.background
    return Theme.foreground
  }

  function blockOf(name) {
    var b = root.layout && root.layout.blocks ? root.layout.blocks[name] : null
    return b || CardLayoutJs.defaultLayout().blocks[name]
  }

  Rectangle {
    anchors.fill: parent
    color: root.roleColor(root.layout ? root.layout.background : "background")
  }

  // The agent's illustration, drawn edge to edge. Handed to Image as a data
  // URI so nothing touches the filesystem and there is no temp file to leak
  // or clean up.
  Image {
    anchors.fill: parent
    visible: root.sceneSvg.length > 0
    source: root.sceneSvg.length > 0
      ? "data:image/svg+xml;utf8," + encodeURIComponent(root.sceneSvg)
      : ""
    fillMode: Image.PreserveAspectCrop
    smooth: true
    // sourceSize pins the rasterisation to the real output size. Without it
    // an SVG scaled up on export comes out soft.
    sourceSize.width: root.width
    sourceSize.height: root.height
    asynchronous: false
  }

  // Procedural art. Only when the agent has not drawn anything.
  Canvas {
    id: art
    anchors.fill: parent
    renderStrategy: Canvas.Immediate
    renderTarget: Canvas.Image
    visible: root.sceneSvg.length === 0 && root.layout.art.motif !== "none"

    readonly property color ink: root.roleColor(root.layout.art.color)
    readonly property var spec: root.layout.art

    onInkChanged: requestPaint()
    onSpecChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      if (width <= 0 || height <= 0 || !visible) return

      var shapes = CardArtJs.plan(root.layout.art, width, height, {
        r: art.ink.r,
        g: art.ink.g,
        b: art.ink.b
      })

      for (var i = 0; i < shapes.length; i++) {
        var s = shapes[i]
        var c = Qt.rgba(s.color.r, s.color.g, s.color.b, s.alpha)
        if (s.type === "circle") {
          ctx.beginPath()
          ctx.arc(s.x, s.y, s.r, 0, 6.2832)
          ctx.fillStyle = c
          ctx.fill()
        } else if (s.type === "rect") {
          ctx.fillStyle = c
          ctx.fillRect(s.x, s.y, s.w, s.h)
        } else if (s.type === "poly") {
          ctx.beginPath()
          ctx.moveTo(s.points[0].x, s.points[0].y)
          for (var p = 1; p < s.points.length; p++) ctx.lineTo(s.points[p].x, s.points[p].y)
          ctx.closePath()
          ctx.fillStyle = c
          ctx.fill()
        } else if (s.type === "line") {
          ctx.beginPath()
          ctx.moveTo(s.points[0].x, s.points[0].y)
          for (var q = 1; q < s.points.length; q++) ctx.lineTo(s.points[q].x, s.points[q].y)
          ctx.strokeStyle = c
          ctx.lineWidth = s.width || 1
          ctx.stroke()
        }
      }
    }
  }

  // Readability is not the agent's call, but the scrim has to be local to
  // the type. An earlier version drew one band from the topmost text block
  // to the bottom edge, which was fine while the type always sat at the
  // bottom -- and the moment the agent put the title at the top it covered
  // 96% of the card and erased the art entirely.
  //
  // Each text block now gets its own soft pad, so the type stays readable
  // and the art is only dimmed where it would otherwise fight the words.
  Repeater {
    model: ["title", "tagline", "specs"]

    delegate: Rectangle {
      required property var modelData
      readonly property var b: root.blockOf(modelData)
      readonly property real pad: 26 * root.u
      visible: root.layout.scrim > 0.02
      x: b.x * root.width - pad
      y: b.y * root.height - pad
      width: Math.min(root.width - x, b.w * root.width + pad * 2)
      height: {
        if (modelData === "specs") {
          return specsRow.height + pad * 2
        }
        if (modelData === "title") return 64 * root.u * b.scale + pad * 2
        return 34 * root.u * b.scale + pad * 2
      }
      color: Qt.rgba(
        Theme.background.r,
        Theme.background.g,
        Theme.background.b,
        Math.min(0.9, root.layout.scrim * 0.82)
      )
    }
  }

  // The mark. The agent places and sizes it; it cannot remove it.
  Image {
    id: logo
    x: root.blockOf("logo").x * root.width
    y: root.blockOf("logo").y * root.height
    height: 46 * root.u * root.blockOf("logo").scale
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    // Recoloured at the source. An effect-based tint rendered black in the
    // exported PNG while looking correct on screen.
    source: Theme.omarchyMarkUri(root.logoPath, root.roleColor(root.blockOf("logo").color))
  }

  Text {
    visible: logo.status !== Image.Ready
    x: logo.x
    y: logo.y
    text: "OMARCHY"
    color: root.roleColor(root.blockOf("logo").color)
    font.family: Theme.fontFamily
    font.pixelSize: 30 * root.u * root.blockOf("logo").scale
    font.bold: true
    font.letterSpacing: 5 * root.u
  }

  Text {
    x: root.blockOf("title").x * root.width
    y: root.blockOf("title").y * root.height
    width: root.blockOf("title").w * root.width
    text: root.card && root.card.title ? root.card.title : "This machine"
    color: root.roleColor(root.blockOf("title").color)
    horizontalAlignment: root.blockOf("title").align === "center"
      ? Text.AlignHCenter
      : (root.blockOf("title").align === "right" ? Text.AlignRight : Text.AlignLeft)
    font.family: Theme.fontFamily
    font.pixelSize: 54 * root.u * root.blockOf("title").scale
    font.bold: true
    elide: Text.ElideRight
  }

  Text {
    x: root.blockOf("tagline").x * root.width
    y: root.blockOf("tagline").y * root.height
    width: root.blockOf("tagline").w * root.width
    visible: text.length > 0
    text: root.card && root.card.tagline ? root.card.tagline : ""
    color: root.roleColor(root.blockOf("tagline").color)
    horizontalAlignment: root.blockOf("tagline").align === "center"
      ? Text.AlignHCenter
      : (root.blockOf("tagline").align === "right" ? Text.AlignRight : Text.AlignLeft)
    font.family: Theme.fontFamily
    font.pixelSize: 24 * root.u * root.blockOf("tagline").scale
    wrapMode: Text.WordWrap
    maximumLineCount: 2
    elide: Text.ElideRight
  }

  // Specs, in however many columns the design asked for. Every row always
  // appears -- the agent chooses the arrangement, never the content.
  Row {
    id: specsRow
    x: root.blockOf("specs").x * root.width
    y: root.blockOf("specs").y * root.height
    width: root.blockOf("specs").w * root.width
    spacing: 48 * root.u

    readonly property int cols: root.blockOf("specs").columns
    readonly property real sc: root.blockOf("specs").scale
    readonly property int per: Math.ceil(root.rows.length / Math.max(1, cols))

    Repeater {
      model: specsRow.cols

      delegate: Column {
        required property int index
        width: (specsRow.width - 48 * root.u * (specsRow.cols - 1)) / specsRow.cols
        spacing: 9 * root.u * specsRow.sc

        Repeater {
          model: {
            var out = []
            var from = index * specsRow.per
            var to = Math.min(root.rows.length, from + specsRow.per)
            for (var i = from; i < to; i++) out.push(root.rows[i])
            return out
          }

          delegate: Item {
            required property var modelData
            width: parent ? parent.width : 0
            height: 30 * root.u * specsRow.sc

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width * 0.4
              text: modelData ? modelData.label : ""
              color: Theme.muted
              font.family: Theme.fontFamily
              font.pixelSize: 18 * root.u * specsRow.sc
              elide: Text.ElideRight
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: parent.width * 0.42
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: modelData ? modelData.value : ""
              color: root.roleColor(root.blockOf("specs").color)
              font.family: Theme.fontFamily
              font.pixelSize: 20 * root.u * specsRow.sc
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }

  Text {
    x: root.blockOf("wordmark").x * root.width
    y: root.blockOf("wordmark").y * root.height
    text: "OMARCHY  ·  ATMOS"
    color: root.roleColor(root.blockOf("wordmark").color)
    opacity: 0.7
    font.family: Theme.fontFamily
    font.pixelSize: 17 * root.u * root.blockOf("wordmark").scale
    font.letterSpacing: 3 * root.u
  }
}
