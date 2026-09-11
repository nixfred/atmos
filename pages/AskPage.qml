import QtQuick
import "../components"
import "../services"
import "../services/AskBar.js" as AskJs

// Lab(askbar): ask for what you want, in plain words, without leaving.
//
// A page rather than an overlay, and the first thing in the sidebar. An
// overlay has to be summoned by someone who already knows it is there, and
// a settings app is opened rarely enough that nobody memorises its keys --
// so the one feature meant to answer "I do not know where this lives"
// cannot itself be something you have to know about.
//
// Nothing here shells out. An earlier version handed hard questions to the
// user's coding agent, which meant a terminal opening over the window you
// were working in and the answer arriving somewhere else entirely. That is
// a settings app giving up. Everything is answered here, in the window, or
// it is honestly reported as unanswered.
//
// The boundary is unchanged and it is the point: this page can take you to
// a setting and explain one, and it has no path that changes one.

PrefsPage {
  id: root
  title: "Ask"
  description: "Describe what you want in plain words. Atmos will take you to the setting, and explain it here. It will not change anything on its own."

  readonly property var hubs: AskJs.hubsFrom(Omarchy.labHubs)
  property string asked: ""

  readonly property var result: root.asked.length > 0 ? AskJs.resolve(root.hubs, root.asked) : null
  readonly property var matches: root.result && root.result.matches ? root.result.matches : []
  readonly property var localRead: Omarchy.labLocalAnswer.length > 0
    ? AskJs.readLocalAnswer(Omarchy.labLocalAnswer, root.hubs)
    : null

  signal goToHub(string hubId)

  function ask(text) {
    var q = String(text || "").replace(/^\s+|\s+$/g, "")
    root.asked = q
    Omarchy.labLocalAnswer = ""
    Omarchy.labLocalError = ""
    if (!q) return
    // Probe each time. A model can be started or stopped while Atmos is
    // open, so a verdict cached at launch would be wrong for the session.
    Omarchy.labProbeLocal()
  }

  function askLocal() {
    var titles = []
    for (var i = 0; i < root.hubs.length; i++) {
      if (root.hubs[i] && root.hubs[i].title) titles.push(root.hubs[i].title)
    }
    Omarchy.labAskLocal(AskJs.localPrompt(root.asked, titles))
  }

  Component.onCompleted: Omarchy.labProbeLocal()

  PrefsGroup {
    title: "What do you want to change?"
    query: root.query
    detail: "Answered from the list of settings pages Atmos already has. Nothing is sent anywhere unless you press the local model button, and that stays on this machine."

    PrefsRow {
      label: "Ask"
      description: "Plain words are fine. \"my bluetooth mouse keeps dropping\" works as well as \"bluetooth\"."
      query: root.query
      stretchControl: true
      keywords: ["ask", "search", "help", "find", "natural", "language"]

      PrefsField {
        placeholder: "Ask…"
        onSubmitted: function (value) { root.ask(value) }
        onEdited: function (value) { if (value.length === 0) root.ask("") }
      }
    }
  }

  PrefsGroup {
    title: "Where it lives"
    query: root.query
    visible: root.asked.length > 0
    detail: "Matched against every page title, description and keyword in Atmos. This runs in the window and needs nothing installed."

    PrefsRow {
      label: "Nothing matched"
      description: "No page title, description or keyword lines up with that. Try a plainer word, or ask the local model below if one is running."
      query: root.query
      available: root.asked.length > 0 && root.matches.length === 0
    }

    Repeater {
      model: root.matches

      delegate: PrefsRow {
        required property var modelData
        required property int index
        label: modelData.hub.title
        description: modelData.hub.description || ""
        query: root.query
        valueText: index === 0 && root.result && root.result.kind === "go" ? "best match" : ""

        // House rule: an action names where it goes. "Open" alone tells you
        // nothing on a page that is a list of destinations.
        PrefsButton {
          text: "Open " + modelData.hub.title
          primary: index === 0
          onClicked: root.goToHub(modelData.hub.id)
        }
      }
    }
  }

  PrefsGroup {
    title: "Explain it"
    query: root.query
    visible: root.asked.length > 0
    detail: "A model running on this computer can read the question and say which page it belongs on. It never sees the internet, and it is never allowed to change a setting -- what it says is printed here for you to read."

    PrefsRow {
      label: "Local model"
      description: {
        if (Omarchy.labLocalBusy) return "Thinking on this machine…"
        if (Omarchy.labLocalUp) return "Running here: " + Omarchy.labLocalModel + ". Nothing leaves this computer."
        return "No local model is answering. Atmos looks for Ollama on this machine; with none running, the matches above are all it can offer."
      }
      query: root.query
      keywords: ["ollama", "local", "llm", "model", "ai", "gpu"]

      PrefsButton {
        text: Omarchy.labLocalBusy ? "Thinking…" : "Ask it"
        primary: true
        enabled: Omarchy.labLocalUp && !Omarchy.labLocalBusy && root.asked.length > 0
        onClicked: root.askLocal()
      }
    }

    PrefsRow {
      label: "It could not answer"
      description: Omarchy.labLocalError
      query: root.query
      available: Omarchy.labLocalError.length > 0
    }

    PrefsRow {
      label: "What it said"
      description: root.localRead && root.localRead.what ? root.localRead.what : Omarchy.labLocalAnswer
      query: root.query
      available: Omarchy.labLocalAnswer.length > 0
      detail: "A small model is good at picking the right page and only guessing at the detail. Treat the page as the answer and the sentence as a hint -- it can name a setting that does not exist, which is safe here only because nothing acts on it."

      PrefsButton {
        text: root.localRead && root.localRead.target ? "Open " + root.localRead.target.title : "No page named"
        primary: !!(root.localRead && root.localRead.target)
        enabled: !!(root.localRead && root.localRead.target)
        onClicked: if (root.localRead && root.localRead.target) root.goToHub(root.localRead.target.id)
      }
    }
  }

  PrefsGroup {
    title: "What Ask may do"
    query: root.query
    detail: "Stated plainly, because a settings panel that can talk to a model should say exactly how far that goes."

    PrefsRow {
      label: "It can point"
      description: "Take you to a page, and show you what a local model thinks. That is the whole of it."
      query: root.query
    }

    PrefsRow {
      label: "It cannot change anything"
      description: "No answer here is turned into a command. There is no code path from this page to a writer, which is why it is safe to leave switched on."
      query: root.query
    }

    PrefsRow {
      label: "It stays in Atmos"
      description: "No terminal opens, nothing is handed to another program, and the question does not leave this computer."
      query: root.query
    }
  }
}
