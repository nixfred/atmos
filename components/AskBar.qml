import QtQuick
import Quickshell
import "../services"
import "../services/AskBar.js" as AskBarJs

// Lab(askbar): ask for what you want in plain words.
//
// Two outcomes and only two. It takes you to the page, or it hands the
// request to your agent and asks the agent for a plan you approve. It never
// changes a setting on your behalf, and there is deliberately no code path
// here that could -- the agent is invoked through `omarchy agent prompt`,
// which opens a terminal the user is looking at, rather than through
// anything that writes.
//
// That restraint is the feature. A settings panel wired to an LLM that can
// act is one most people would switch off on principle; one that can only
// ever navigate or explain is one they will leave on.

Item {
  id: root

  property var hubs: []
  property bool active: false

  signal navigate(string hubId)
  signal askAgent(string prompt)

  readonly property string query: input.text
  readonly property var result: AskBarJs.resolve(root.hubs, root.query)
  readonly property var matches: result && result.matches ? result.matches : []

  anchors.fill: parent
  visible: active
  z: 100

  readonly property bool localReady: Omarchy.labLocalUp && !Omarchy.labLocalBusy
  readonly property var localRead: Omarchy.labLocalAnswer.length > 0
    ? AskBarJs.readLocalAnswer(Omarchy.labLocalAnswer, root.hubs)
    : null

  function askLocal() {
    var titles = []
    for (var i = 0; i < root.hubs.length; i++) {
      if (root.hubs[i] && root.hubs[i].title) titles.push(root.hubs[i].title)
    }
    Omarchy.labAskLocal(AskBarJs.localPrompt(root.query, titles))
  }

  function open() {
    input.text = ""
    Omarchy.labLocalAnswer = ""
    Omarchy.labLocalError = ""
    // Probe on open rather than at startup. A model can be started or
    // stopped while Atmos is running, and a stale "no local model" would be
    // wrong for the rest of the session.
    Omarchy.labProbeLocal()
    root.active = true
    Qt.callLater(function () {
      input.forceActiveFocus()
    });
  }

  function close() {
    root.active = false
    input.text = ""
  }

  function go(hubId) {
    if (!hubId) return
    root.navigate(hubId)
    root.close()
  }

  function acceptTop() {
    if (root.result && root.result.kind === "go" && root.result.target) {
      root.go(root.result.target.id)
      return
    }
    if (root.matches.length > 0) {
      root.go(root.matches[0].hub.id)
      return
    }
    root.handOff()
  }

  // Everything local matching could not answer goes here. The prompt asks
  // for a plan and forbids action in as many words, so what comes back is
  // something to read rather than something that already happened.
  function handOff() {
    var titles = []
    for (var i = 0; i < root.hubs.length; i++) {
      if (root.hubs[i] && root.hubs[i].title) titles.push(root.hubs[i].title)
    }
    var prompt = AskBarJs.agentPrompt(root.query, titles)
    if (!prompt) return
    root.askAgent(prompt)
    root.close()
  }

  // Scrim. Clicking away closes, matching every other overlay in the app.
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, Theme.scrimAlpha)
    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }
  }

  Rectangle {
    id: panel
    width: Math.min(Theme.dialogWidth, root.width - Theme.overlayInset * 2)
    anchors.horizontalCenter: parent.horizontalCenter
    y: Math.round(root.height * 0.18)
    height: content.implicitHeight + Theme.pad * 2
    color: Theme.background
    border.width: Theme.borderWidth
    border.color: Theme.borderColor()
    radius: Theme.radius

    Column {
      id: content
      x: Theme.pad
      y: Theme.pad
      width: parent.width - Theme.pad * 2
      spacing: Theme.space

      TextInput {
        id: input
        width: parent.width
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.titleSize
        selectByMouse: true
        onAccepted: root.acceptTop()
        Keys.onEscapePressed: root.close()

        Text {
          anchors.fill: parent
          visible: input.text.length === 0
          text: "What do you want to change?"
          color: Theme.muted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.titleSize
        }
      }

      Rectangle {
        width: parent.width
        height: Theme.borderWidth
        color: Theme.splitColor()
      }

      // Results. The top row is what Enter will do, so it says so rather
      // than relying on a highlight the user has to decode.
      Repeater {
        model: root.query.length > 0 ? root.matches : []
        delegate: Rectangle {
          required property var modelData
          required property int index
          width: content.width
          height: Theme.rowHeight
          color: hover.containsMouse ? Theme.fill(Theme.hoverFill) : "transparent"

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: enterHint.left
            anchors.rightMargin: Theme.space
            text: modelData.hub.title
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.labelSize
            font.bold: index === 0
            elide: Text.ElideRight
          }

          Text {
            id: enterHint
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: index === 0
            text: "Enter"
            color: Theme.muted
            opacity: Theme.metaOpacity
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
          }

          MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.go(modelData.hub.id)
          }
        }
      }

      // Said plainly, every time, so the boundary is never a surprise.
      Text {
        width: parent.width
        visible: root.query.length > 0
        text: {
          if (root.result.kind === "none")
            return "No page matches that. Your agent can look at it and tell you what it would change."
          if (root.result.kind === "choose")
            return "More than one page could be it. Pick one, or let your agent work it out."
          if (root.result.change)
            return "Atmos will take you there. It will not change anything by itself."
          return "Enter opens the first result."
        }
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        wrapMode: Text.WordWrap
      }

      // What the local model said. Shown, never acted on -- Atmos does not
      // parse this into a command, it offers the page as a button and lets
      // you decide.
      Rectangle {
        width: parent.width
        visible: Omarchy.labLocalBusy || Omarchy.labLocalAnswer.length > 0 || Omarchy.labLocalError.length > 0
        implicitHeight: localCol.implicitHeight + Theme.space * 2
        height: implicitHeight
        color: Theme.fill(Theme.normalFill)
        border.width: Theme.borderWidth
        border.color: Theme.borderColor()
        radius: Theme.radius

        Column {
          id: localCol
          x: Theme.space
          y: Theme.space
          width: parent.width - Theme.space * 2
          spacing: Theme.titleGap

          Text {
            width: parent.width
            text: {
              if (Omarchy.labLocalBusy) return "Asking " + Omarchy.labLocalModel + " on this machine…"
              if (Omarchy.labLocalError.length > 0) return Omarchy.labLocalError
              var r = root.localRead
              return r && r.what ? r.what : Omarchy.labLocalAnswer
            }
            color: Omarchy.labLocalError.length > 0 ? Theme.urgent : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.labelSize
            wrapMode: Text.WordWrap
          }

          PrefsButton {
            visible: !!(root.localRead && root.localRead.target)
            text: root.localRead && root.localRead.target
              ? "Open " + root.localRead.target.title
              : ""
            primary: true
            onClicked: if (root.localRead && root.localRead.target) root.go(root.localRead.target.id)
          }
        }
      }

      Row {
        anchors.right: parent.right
        spacing: Theme.space

        // Local first when a model is actually running. It is private, it
        // costs nothing and it does not open a terminal over what you were
        // doing. The agent stays for when there is no local model.
        PrefsButton {
          text: Omarchy.labLocalBusy
            ? "Thinking…"
            : (Omarchy.labLocalUp ? "Ask " + Omarchy.labLocalModel : "Ask locally")
          enabled: root.query.length > 0 && root.localReady
          onClicked: root.askLocal()
        }

        PrefsButton {
          text: "Ask my agent"
          enabled: root.query.length > 0
          onClicked: root.handOff()
        }

        PrefsButton {
          text: "Close"
          onClicked: root.close()
        }
      }
    }
  }
}
