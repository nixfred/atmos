import QtQuick
import "../../components"
import "../../services"

// Lab(all): the switchboard.
//
// This page exists so a reviewer can disagree with nine of these and keep
// one without touching a line of code. Every feature is independent, every
// one can be turned off here or by environment variable, and with the master
// switch off Atmos is byte-for-byte the app it was before.
//
// That is the whole argument for merging any of this: none of it is a
// commitment. Keep what earns its place and delete the rest.

PrefsPage {
  id: root
  title: "Lab"
  description: "Proposed features, each independent and each reversible. Turn the lot off with ATMOS_LAB=0, or drop individual ones with ATMOS_LAB_OFF=id,id."

  PrefsGroup {
    title: "Everything"
    query: root.query
    detail: "The master switch is an environment variable so it works before the window is even drawn. These toggles are per-session and do not persist."

    PrefsRow {
      label: "Lab features"
      description: Lab.enabled
        ? Lab.activeCount + " of " + Lab.features.length + " are on right now."
        : "Off. ATMOS_LAB=0 is set, so Atmos is running exactly as it does on main."
      query: root.query
      valueText: Lab.enabled ? "on" : "off"
    }

    PrefsRow {
      label: "Reset toggles"
      description: "Forget anything changed on this page and go back to what the environment asked for."
      query: root.query
      available: Lab.enabled

      PrefsButton {
        text: "Reset"
        onClicked: Lab.clearOverrides()
      }
    }
  }

  PrefsGroup {
    title: "The ten"
    query: root.query
    detail: "Each of these can be switched off on its own. Nothing here depends on anything else here."

    Repeater {
      model: Lab.features

      delegate: PrefsRow {
        required property var modelData
        label: modelData.n + ". " + modelData.title
        description: modelData.blurb
        detail: "Touches: " + modelData.touches
        query: root.query
        available: Lab.enabled
        keywords: ["lab", modelData.id]

        PrefsToggle {
          checked: Lab.on(modelData.id)
          onToggled: function (value) {
            Lab.setOverride(modelData.id, value)
          }
        }
      }
    }
  }

  PrefsGroup {
    title: "How to turn it off"
    query: root.query
    detail: "For anyone reviewing this who wants to see the difference rather than read about it."

    PrefsRow {
      label: "Everything off"
      description: "Start Atmos with the master switch off. Nothing below this line renders, no new key handler is installed, and no new process runs."
      query: root.query
      valueText: "ATMOS_LAB=0 atmos"
    }

    PrefsRow {
      label: "Some of it off"
      description: "A comma separated list of the ids above. Unknown ids are ignored rather than treated as an error."
      query: root.query
      valueText: "ATMOS_LAB_OFF=chamfer,askbar atmos"
    }
  }
}
