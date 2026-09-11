pragma Singleton
import QtQuick
import Quickshell

// Atmos Lab: ten proposed features behind one switch.
//
// Everything here is additive and reversible. ATMOS_LAB=0 turns the whole
// set off, and with it off Atmos renders and behaves exactly as it does on
// main -- no shape change, no extra chrome, no new key handlers, no new
// processes. That is the contract: this file can be deleted and the diff
// that removes it touches nothing but Lab call sites.
//
// Each feature also has its own flag so a reviewer can keep three and drop
// seven without untangling anything. ATMOS_LAB_OFF is a comma list of
// feature ids to disable individually, e.g. ATMOS_LAB_OFF=askbar,timemachine
//
// Honouring services/Theme.qml's stated visual language: no rounded cards,
// no shadows, no wider column. The chamfer is a cut corner, not a radius,
// which is why it is offered here rather than ruled out by that comment.

QtObject {
  id: root

  readonly property string envMaster: Quickshell.env("ATMOS_LAB")
  readonly property string envOff: Quickshell.env("ATMOS_LAB_OFF")

  // Default on. Only an explicit 0/off/false disables.
  readonly property bool enabled: {
    var v = String(root.envMaster || "").toLowerCase()
    if (v === "0" || v === "off" || v === "false" || v === "no") return false
    return true
  }

  // Keys are prefixed. A bare object is not a set: disabledIds["constructor"]
  // and ["toString"] are truthy through the prototype, so ATMOS_LAB_OFF with
  // either word would have disabled nothing while appearing to work. Same
  // hazard as the one already fixed in AskBar.js and History.js.
  readonly property var disabledIds: {
    var out = {}
    var parts = String(root.envOff || "").split(",")
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].replace(/^\s+|\s+$/g, "").toLowerCase()
      if (p) out["f_" + p] = true
    }
    return out
  }

  // Runtime overrides from the Lab page, so a reviewer can flip a feature
  // without restarting. Null means "follow the env".
  property var overrides: ({})

  // Lab(disclosure): Simple hides rows marked advanced. It never removes
  // them -- search still finds a folded row and unfolds it -- so this is
  // progressive disclosure and not the option-hiding people rightly hate
  // about other settings apps.
  property bool simpleMode: false

  // Lab(previewmode): while this is on, a write is shown instead of made.
  // Off by default and never persisted, because a settings app silently
  // refusing to save across a restart would be indistinguishable from a bug.
  property bool previewMode: false

  function on(id) {
    if (!root.enabled) return false
    var key = String(id || "").toLowerCase()
    if (root.overrides["o_" + key] !== undefined) return root.overrides["o_" + key] === true
    return root.disabledIds["f_" + key] !== true
  }

  function setOverride(id, value) {
    var key = String(id || "").toLowerCase()
    var next = {}
    for (var k in root.overrides) next[k] = root.overrides[k]
    next["o_" + key] = value === true
    root.overrides = next
  }

  function clearOverrides() {
    root.overrides = ({})
  }

  // The ten. Order is the order they appear on the Lab page.
  readonly property var features: [
    {
      id: "chamfer",
      n: 6,
      title: "Chamfered shape language",
      blurb: "A 45 degree cut on cards, focus rings and the sidebar selection. Not a radius -- Theme.qml says do not round cards, and this does not.",
      touches: "Theme.qml tokens, components/Chamfer.qml"
    },
    {
      id: "statusglyph",
      n: 1,
      title: "Live status in the sidebar",
      blurb: "Hub icons carry current state instead of decoration. Failed units, connected devices, disabled outputs, pending updates -- readable without opening a page.",
      touches: "shell.qml nav rows, services/LabStatus.js"
    },
    {
      id: "hoverpreview",
      n: 8,
      title: "Live hover preview",
      blurb: "Hover a theme, gap, font size or animation and the real desktop shows it, reverting on mouse-out. Atmos is the shell, so it can do what a settings client structurally cannot.",
      touches: "pages/AppearancePage.qml, WindowsPage.qml"
    },
    {
      id: "provenance",
      n: 3,
      title: "Why is this set?",
      blurb: "Every row can say which file holds it, whether Atmos manages it or you hand-wrote it, and what the default was. Atmos already computes this for sentinel deferral.",
      touches: "components/PrefsRow.qml"
    },
    {
      id: "disclosure",
      n: 7,
      title: "Simple / Everything per page",
      blurb: "Nothing is removed, only folded, per page, remembered. Search still finds folded rows and unfolds them.",
      touches: "components/PrefsGroup.qml, PrefsPage.qml"
    },
    {
      id: "previewmode",
      n: 5,
      title: "Preview mode",
      blurb: "Flip a control and see the config diff it would write, before it writes. The import planner already computes exactly this for files.",
      touches: "services/Settings.js commandFor, a preview overlay"
    },
    {
      id: "timemachine",
      n: 4,
      title: "Time machine",
      blurb: "Every change with its source -- you, an import, the agent -- and one-click revert. Atmos already writes undo plans; this surfaces them.",
      touches: "pages/system/HistoryPage.qml"
    },
    {
      id: "keyboard",
      n: 10,
      title: "Keyboard-first navigation",
      blurb: "j/k to move, / to search, Enter to act, g to jump, ? for the overlay. The audience runs a tiling WM and lives on the keyboard.",
      touches: "shell.qml key handling"
    },
    {
      id: "machine",
      n: 9,
      title: "Machine page",
      blurb: "Diagnostics is a report. This is the dashboard: the actual laptop, battery health, SMART, thermals, what is plugged in.",
      touches: "pages/system/MachinePage.qml"
    },
    {
      id: "sectionfocus",
      n: 11,
      title: "Light the whole row",
      blurb: "Hover or keyboard-focus a setting and the entire row lights, label and description and control together, with a hard edge on the left. Answers \"where am I\" without hunting for a focus ring.",
      touches: "components/SettingRow.qml"
    },
    {
      id: "askbar",
      n: 2,
      title: "Ask bar",
      blurb: "Natural language in. Its own hub at the top of the sidebar, or Ctrl+K. Matches against the catalogue instantly, and can hand anything it cannot answer to the coding agent this machine already uses. Neither can write a setting; both can only point.",
      touches: "pages/AskPage.qml, services/AskBar.js, scripts/agent-ask.sh"
    }
  ]

  function featureById(id) {
    var key = String(id || "").toLowerCase()
    for (var i = 0; i < root.features.length; i++) {
      if (root.features[i].id === key) return root.features[i]
    }
    return null
  }

  readonly property int activeCount: {
    var n = 0
    for (var i = 0; i < root.features.length; i++) {
      if (root.on(root.features[i].id)) n++
    }
    return n
  }
}
