import QtQuick
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "../components"
import "../services"
import "../services/Settings.js" as SettingsJs
import "../services/RichUi.js" as RichUi

PrefsPage {
  id: root
  title: "Import and export"
  description: "Write this machine's settings to a Markdown file you can read, keep, or hand to someone else. Importing shows you every change before anything happens."

  readonly property string home: Quickshell.env("HOME")
  readonly property string applyScript: Omarchy.shellDir + "/scripts/apply-settings.sh"
  readonly property string defaultName: "atmos-settings.md"

  // Section id -> included. Seeded from the catalog, so a section added
  // there appears here without this page being told about it.
  property var sections: ({})

  property string exportPath: home + "/" + defaultName
  property string importPath: home + "/" + defaultName
  property string exportStatus: ""
  property string importStatus: ""
  property string writtenPath: ""
  property var plan: null

  // Derived rather than assigned, so it cannot be left stuck on by a path
  // that forgot to clear it.
  readonly property bool working: writeProc.running || readProc.running || applyProc.running

  readonly property var sectionList: SettingsJs.selectableSections()

  // Reads root.sections so the binding re-runs when a switch moves. A
  // function call on its own would not be tracked.
  readonly property var chosenKeys: {
    var chosen = root.sections
    var ids = []
    for (var i = 0; i < root.sectionList.length; i++) {
      var id = root.sectionList[i].id
      if (chosen[id]) ids.push(id)
    }
    return SettingsJs.keysForSections(ids)
  }

  readonly property int chosenSectionCount: {
    var chosen = root.sections
    var n = 0
    for (var i = 0; i < root.sectionList.length; i++)
      if (chosen[root.sectionList[i].id]) n++
    return n
  }

  readonly property string planSummary: root.plan ? root.plan.summary : ""
  readonly property bool planHasChanges: !!root.plan && root.plan.changes.length > 0

  // ---- paths -------------------------------------------------------------

  // A path typed with a leading tilde never reaches a shell that would
  // expand it, so it would arrive at the writer as a literal directory.
  function realPath(path) {
    var text = String(path || "")
    if (text === "~") return root.home
    if (text.indexOf("~/") === 0) return root.home + text.slice(1)
    return text
  }

  function folderUrl(path) {
    var text = root.realPath(path)
    var cut = text.lastIndexOf("/")
    return "file://" + (cut > 0 ? text.slice(0, cut) : root.home)
  }

  // The save dialog has no default suffix, so a name typed without one
  // would produce a file nothing recognises as a settings file.
  function withMarkdownSuffix(path) {
    var text = String(path || "")
    if (text.length === 0) return root.home + "/" + root.defaultName
    return /\.md$/i.test(text) ? text : text + ".md"
  }

  // ---- state -------------------------------------------------------------

  function setSection(id, on) {
    var next = {}
    for (var key in root.sections) next[key] = root.sections[key]
    next[id] = on
    root.sections = next
    root.forgetExport()
  }

  function setAllSections(on) {
    var next = {}
    for (var i = 0; i < root.sectionList.length; i++) next[root.sectionList[i].id] = on
    root.sections = next
    root.forgetExport()
  }

  function resetSections() {
    var next = {}
    for (var i = 0; i < root.sectionList.length; i++)
      next[root.sectionList[i].id] = root.sectionList[i].byDefault
    root.sections = next
  }

  // What was written is only worth offering to open while it still matches
  // what the page would write now.
  function forgetExport() {
    root.writtenPath = ""
    root.exportStatus = ""
  }

  // A plan belongs to one file. Point at another and the old plan is a lie.
  function forgetPlan() {
    root.plan = null
    root.importStatus = ""
  }

  onExportPathChanged: root.forgetExport()
  onImportPathChanged: root.forgetPlan()

  // ---- actions -----------------------------------------------------------

  function doExport() {
    if (root.chosenKeys.length === 0) return
    var text = SettingsJs.exportMarkdown(Omarchy.snapshotData, root.chosenKeys, {
      exported: new Date().toISOString(),
      hardware: Omarchy.dmiProduct
    })
    root.forgetExport()
    writeProc.target = root.realPath(root.exportPath)
    writeProc.text = text
    writeProc.command = ["sh", "-c", "cat > \"$1\"", "sh", writeProc.target]
    writeProc.running = true
  }

  function openFile(path) {
    openProc.command = ["xdg-open", root.realPath(path)]
    openProc.running = true
  }

  function doReview() {
    root.forgetPlan()
    readProc.command = ["cat", root.realPath(root.importPath)]
    readProc.running = true
  }

  function doApply() {
    if (!root.planHasChanges) return
    root.importStatus = ""
    applyProc.text = SettingsJs.planToJson(root.plan)
    applyProc.command = ["bash", root.applyScript]
    applyProc.running = true
  }

  function doUndo() {
    root.importStatus = ""
    applyProc.text = ""
    // --no-backup, or undoing would leave a way back of its own and a
    // second undo would put the import straight back.
    applyProc.command = ["sh", "-c",
      "d=$(ls -1d \"$HOME\"/.local/state/atmos/imports/*/ 2>/dev/null | tail -1); " +
      "[ -n \"$d\" ] || { echo 'There is no import to undo.' >&2; exit 1; }; " +
      "bash \"$1\" --no-backup --plan \"$d/undo.json\"", "sh", root.applyScript]
    applyProc.running = true
  }

  // ---- processes ---------------------------------------------------------

  Process {
    id: writeProc
    property string text: ""
    property string target: ""
    command: ["true"]
    stdinEnabled: true
    stderr: StdioCollector { id: writeErr; waitForEnd: true }
    onStarted: {
      write(text)
      // cat only finishes when its input ends.
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.writtenPath = writeProc.target
        root.exportStatus = "Wrote " + root.chosenKeys.length + " settings to " + writeProc.target
        return
      }
      var err = String(writeErr.text || "").replace(/^\s+|\s+$/g, "")
      root.exportStatus = err.length > 0 ? err : "Could not write " + writeProc.target
    }
  }

  Process {
    id: openProc
    command: ["true"]
    stderr: StdioCollector { id: openErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) return
      var err = String(openErr.text || "").replace(/^\s+|\s+$/g, "")
      root.exportStatus = err.length > 0 ? err : "Nothing on this machine opens that file."
    }
  }

  Process {
    id: readProc
    command: ["true"]
    stdout: StdioCollector { id: readOut; waitForEnd: true }
    stderr: StdioCollector { id: readErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var err = String(readErr.text || "").replace(/^\s+|\s+$/g, "")
        root.importStatus = err.length > 0 ? err : "Could not read " + root.importPath
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
      root.plan = null
      var err = String(applyErr.text || "").replace(/^\s+|\s+$/g, "")
      root.importStatus = exitCode === 0
        ? "Applied. Atmos kept a way back in ~/.local/state/atmos/imports."
        : (err.length > 0 ? err : "Some changes did not apply.")
      Omarchy.scheduleRefresh()
    }
  }

  // ---- export ------------------------------------------------------------

  PrefsGroup {
    title: "Export"
    query: root.query
    detail: "Atmos writes a Markdown file. The settings live in fenced blocks, so you can read the file, edit it, and hand it to someone without it being able to do anything you cannot see. Security settings are written down for you to read but Atmos will never import them."

    PrefsRow {
      label: "Sections"
      description: root.chosenKeys.length + " settings across " + root.chosenSectionCount + " sections."
      query: root.query
      keywords: ["all", "none", "select", "sections", "choose"]

      Row {
        spacing: 8

        PrefsButton {
          text: "All"
          enabled: !root.working
          onClicked: root.setAllSections(true)
        }

        PrefsButton {
          text: "None"
          enabled: !root.working
          onClicked: root.setAllSections(false)
        }
      }
    }

    Repeater {
      model: root.sectionList

      PrefsRow {
        required property var modelData
        label: modelData.title
        description: modelData.note + "  (" + modelData.count + " settings)"
        query: root.query
        keywords: [modelData.id, "section", "include", "export"]

        PrefsToggle {
          checked: !!root.sections[modelData.id]
          enabled: !root.working
          onToggled: root.setSection(modelData.id, !root.sections[modelData.id])
        }
      }
    }

    PrefsRow {
      label: "Where to write it"
      description: root.exportPath
      query: root.query
      keywords: ["path", "file", "folder", "directory", "markdown", "md", "save", "choose"]

      PrefsButton {
        text: "Choose…"
        enabled: !root.working
        onClicked: exportFileDialog.open()
      }
    }

    PrefsRow {
      label: "Write the file"
      description: root.exportStatus.length > 0
        ? root.exportStatus
        : "Writes the sections switched on above."
      query: root.query
      keywords: ["export", "save", "write", "backup", "open"]

      Row {
        spacing: 8

        PrefsButton {
          text: "Export"
          primary: true
          enabled: !root.working && root.chosenKeys.length > 0
          onClicked: root.doExport()
        }

        PrefsButton {
          text: "Open"
          enabled: !root.working && root.writtenPath.length > 0
          onClicked: root.openFile(root.writtenPath)
        }
      }
    }
  }

  // ---- import ------------------------------------------------------------

  PrefsGroup {
    title: "Import"
    query: root.query
    detail: "Nothing is applied until you have read the plan. Atmos compares the file against this machine, shows every change with what it will do, and writes a way back before it touches anything."

    PrefsRow {
      label: "File to read"
      description: root.importPath
      query: root.query
      keywords: ["path", "file", "import", "load", "browse", "open"]

      PrefsButton {
        text: "Browse…"
        enabled: !root.working
        onClicked: importFileDialog.open()
      }
    }

    PrefsRow {
      label: "See what it would do"
      description: root.importStatus.length > 0
        ? root.importStatus
        : "Reads the file and compares it against this machine. Changes nothing."
      query: root.query
      keywords: ["review", "dry run", "preview", "plan", "diff"]

      PrefsButton {
        text: "Review"
        enabled: !root.working
        onClicked: root.doReview()
      }
    }

    PrefsRow {
      label: "Changes"
      description: root.planSummary
      query: root.query
      available: root.planHasChanges
      stretchControl: true
      keywords: ["changes", "plan"]

      PrefsText {
        width: parent.width
        text: root.plan ? SettingsJs.changeLines(root.plan) : ""
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        wrapMode: Text.Wrap
      }
    }

    PrefsRow {
      label: "Worth knowing"
      description: "These still happen."
      query: root.query
      available: !!root.plan && root.plan.warnings.length > 0
      stretchControl: true
      keywords: ["warning", "hardware", "skipped", "shadow"]

      PrefsText {
        width: parent.width
        text: root.plan ? SettingsJs.warningLines(root.plan) : ""
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
      available: !!root.plan && root.plan.blocked.length > 0
      stretchControl: true
      keywords: ["blocked", "refused", "security"]

      PrefsText {
        width: parent.width
        text: root.plan ? SettingsJs.blockedLines(root.plan) : ""
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

  // ---- dialogs -----------------------------------------------------------

  FileDialog {
    id: exportFileDialog
    title: "Write the settings file"
    fileMode: FileDialog.SaveFile
    nameFilters: ["Settings files (*.md)", "All files (*)"]
    currentFolder: root.folderUrl(root.exportPath)
    onAccepted: root.exportPath = root.withMarkdownSuffix(RichUi.pathFromUrl(selectedFile))
  }

  FileDialog {
    id: importFileDialog
    title: "Open a settings file"
    fileMode: FileDialog.OpenFile
    nameFilters: ["Settings files (*.md)", "All files (*)"]
    currentFolder: root.folderUrl(root.importPath)
    onAccepted: root.importPath = RichUi.pathFromUrl(selectedFile)
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

  Component.onCompleted: {
    root.resetSections()
    applyConfirm.parent = root.prefsOverlay
    undoConfirm.parent = root.prefsOverlay
  }
}
