import QtQuick
import Quickshell
import Quickshell.Io
import "../components"
import "../services"
import "../services/Settings.js" as SettingsJs

PrefsPage {
  id: root
  title: "Import and export"
  description: "Write this machine's settings to a Markdown file you can read, keep, or hand to someone else. Importing shows you every change before anything happens."

  readonly property string home: Quickshell.env("HOME")
  readonly property string applyScript: Omarchy.shellDir + "/scripts/apply-settings.sh"

  property string preset: "portable"
  property string exportPath: home + "/atmos-settings.md"
  property string importPath: home + "/atmos-settings.md"

  property string exportStatus: ""
  property string importStatus: ""
  property var plan: null
  property bool working: false

  readonly property var presetOptions: [
    { value: "look", label: "Looks only" },
    { value: "portable", label: "Everything portable" },
    { value: "full", label: "Everything, including this machine's identity" }
  ]

  readonly property int presetCount: SettingsJs.presetKeys(root.preset).length

  readonly property string planSummary: root.plan ? root.plan.summary : ""
  readonly property bool planHasChanges: !!root.plan && root.plan.changes.length > 0

  function lines(list, render) {
    var out = []
    for (var i = 0; i < list.length; i++) out.push(render(list[i]))
    return out.join("\n")
  }

  function shown(value) {
    return value === null || value === undefined || value === "" ? "not set" : SettingsJs.displayValue(value)
  }

  readonly property string changeText: root.plan
    ? lines(root.plan.changes, function(c) {
        var head = "• " + c.label + ": " + shown(c.from) + " → " + shown(c.to)
        return c.consequence ? head + "\n    " + c.consequence : head
      })
    : ""

  readonly property string warningText: root.plan
    ? lines(root.plan.warnings, function(w) { return "• " + w.message })
    : ""

  readonly property string blockedText: root.plan
    ? lines(root.plan.blocked, function(b) { return "• " + b.reason })
    : ""

  function doExport() {
    var keys = SettingsJs.presetKeys(root.preset)
    var text = SettingsJs.exportMarkdown(Omarchy.snapshotData, keys, {
      exported: new Date().toISOString(),
      hardware: Omarchy.dmiProduct
    })
    root.exportStatus = ""
    root.working = true
    writeProc.text = text
    writeProc.command = ["sh", "-c", "cat > \"$1\"", "sh", root.exportPath]
    writeProc.running = true
  }

  function doReview() {
    root.plan = null
    root.importStatus = ""
    root.working = true
    readProc.command = ["cat", root.importPath]
    readProc.running = true
  }

  function doApply() {
    if (!root.planHasChanges) return
    root.importStatus = ""
    root.working = true
    applyProc.text = SettingsJs.planToJson(root.plan)
    applyProc.command = ["bash", root.applyScript]
    applyProc.running = true
  }

  function doUndo() {
    root.importStatus = ""
    root.working = true
    applyProc.text = ""
    applyProc.command = ["sh", "-c",
      "d=$(ls -1d \"$HOME\"/.local/state/atmos/imports/*/ 2>/dev/null | tail -1); " +
      "[ -n \"$d\" ] || { echo 'no import to undo' >&2; exit 1; }; " +
      "bash \"$1\" --plan \"$d/undo.json\"", "sh", root.applyScript]
    applyProc.running = true
  }

  Process {
    id: writeProc
    property string text: ""
    command: ["true"]
    stdinEnabled: true
    onStarted: {
      write(text)
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      root.working = false
      root.exportStatus = exitCode === 0
        ? "Wrote " + root.presetCount + " settings to " + root.exportPath
        : "Could not write " + root.exportPath
    }
  }

  Process {
    id: readProc
    command: ["true"]
    stdout: StdioCollector { id: readOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.working = false
      if (exitCode !== 0) {
        root.importStatus = "Could not read " + root.importPath
        return
      }
      var doc = SettingsJs.parseSettingsMarkdown(String(readOut.text || ""))
      root.plan = SettingsJs.planImport(doc, Omarchy.snapshotData, null, {
        hardware: Omarchy.dmiProduct
      })
      root.importStatus = root.plan.changes.length === 0
        ? "Nothing to change. " + root.plan.summary
        : ""
    }
  }

  Process {
    id: applyProc
    property string text: ""
    command: ["true"]
    stdinEnabled: true
    stderr: StdioCollector { id: applyErr; waitForEnd: true }
    onStarted: {
      if (text.length > 0) write(text)
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      root.working = false
      root.plan = null
      var err = String(applyErr.text || "").replace(/^\s+|\s+$/g, "")
      root.importStatus = exitCode === 0
        ? "Applied. Atmos kept a way back in ~/.local/state/atmos/imports."
        : (err.length > 0 ? err : "Some changes did not apply.")
      Omarchy.scheduleRefresh()
    }
  }

  PrefsGroup {
    title: "Export"
    query: root.query
    detail: "Atmos writes a Markdown file. The settings live in fenced blocks, so you can read the file, edit it, and hand it to someone without it being able to do anything you cannot see. Security settings are written down for you to read but Atmos will never import them."

    PrefsRow {
      label: "What to include"
      description: "Looks travel anywhere. Portable adds the settings that are true on any machine. The last one adds hostname, timezone, locale, and keyboard layout, which usually belong to one machine only."
      query: root.query
      keywords: ["preset", "look", "portable", "everything", "identity"]

      PrefsSelect {
        value: root.preset
        options: root.presetOptions
        enabled: !root.working
        onChanged: function(value) { root.preset = value }
      }
    }

    PrefsRow {
      label: "File"
      description: "Where to write it."
      query: root.query
      keywords: ["path", "file", "markdown", "md"]

      PrefsField {
        value: root.exportPath
        placeholder: root.home + "/atmos-settings.md"
        enabled: !root.working
        onEdited: function(value) { root.exportPath = value }
      }
    }

    PrefsRow {
      label: "Write the file"
      description: root.exportStatus.length > 0
        ? root.exportStatus
        : root.presetCount + " settings will be written."
      query: root.query
      keywords: ["export", "save", "write", "backup"]

      PrefsButton {
        text: "Export"
        primary: true
        enabled: !root.working && root.exportPath.length > 0
        onClicked: root.doExport()
      }
    }
  }

  PrefsGroup {
    title: "Import"
    query: root.query
    detail: "Nothing is applied until you have read the plan. Atmos compares the file against this machine, shows every change with what it will do, and writes a way back before it touches anything."

    PrefsRow {
      label: "File"
      description: "The file to read."
      query: root.query
      keywords: ["path", "file", "import", "load"]

      PrefsField {
        value: root.importPath
        placeholder: root.home + "/atmos-settings.md"
        enabled: !root.working
        onEdited: function(value) { root.importPath = value }
      }
    }

    PrefsRow {
      label: "See what it would do"
      description: root.importStatus.length > 0 ? root.importStatus : "Reads the file and compares it against this machine. Changes nothing."
      query: root.query
      keywords: ["review", "dry run", "preview", "plan", "diff"]

      PrefsButton {
        text: "Review"
        enabled: !root.working && root.importPath.length > 0
        onClicked: root.doReview()
      }
    }

    PrefsRow {
      label: "Changes"
      description: root.planSummary
      query: root.query
      available: !!root.plan
      stretchControl: true
      keywords: ["changes", "plan"]

      PrefsText {
        width: parent.width
        visible: root.changeText.length > 0
        text: root.changeText
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        wrapMode: Text.Wrap
      }
    }

    PrefsRow {
      label: "Warnings"
      description: "Things that will still happen, but that you should know about."
      query: root.query
      available: root.warningText.length > 0
      stretchControl: true
      keywords: ["warning", "hardware", "skipped"]

      PrefsText {
        width: parent.width
        text: root.warningText
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        wrapMode: Text.Wrap
      }
    }

    PrefsRow {
      label: "Blocked"
      description: "Atmos will not do these."
      query: root.query
      available: root.blockedText.length > 0
      stretchControl: true
      keywords: ["blocked", "refused", "security"]

      PrefsText {
        width: parent.width
        text: root.blockedText
        color: Theme.urgent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        wrapMode: Text.Wrap
      }
    }

    PrefsRow {
      label: "Apply the plan you just read"
      description: "Runs exactly the changes listed above."
      query: root.query
      available: root.planHasChanges
      keywords: ["apply", "import", "run"]

      PrefsButton {
        text: "Apply"
        danger: true
        enabled: !root.working
        onClicked: applyConfirm.ask()
      }
    }

    PrefsRow {
      label: "Undo the last import"
      description: "Puts back the values the last import replaced."
      query: root.query
      keywords: ["undo", "revert", "restore", "back"]

      PrefsButton {
        text: "Undo"
        enabled: !root.working
        onClicked: undoConfirm.ask()
      }
    }
  }

  Component.onCompleted: {
    applyConfirm.parent = root.prefsOverlay
    undoConfirm.parent = root.prefsOverlay
  }

  PrefsConfirm {
    id: applyConfirm
    title: "Apply these settings?"
    message: root.plan
      ? root.planSummary + ". Atmos writes a way back first, and Undo puts it all back."
      : ""
    confirmText: "Apply"
    onConfirmed: root.doApply()
  }

  PrefsConfirm {
    id: undoConfirm
    title: "Undo the last import?"
    message: "Puts back the values the last import replaced."
    confirmText: "Undo"
    onConfirmed: root.doUndo()
  }
}
