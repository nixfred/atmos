import QtQuick
import "../components"
import "../services"
import "../services/Hardware.js" as HardwareJs
import "../services/RichUi.js" as RichUi
import "../services/CardArt.js" as CardArtJs
import "../services/MachineCard.js" as MachineCardJs

PrefsPage {
  id: root
  title: "Hardware"
  description: "What this machine is made of. Processor, memory, chipset, firmware, graphics, NPU, and the rest of the units the kernel can see."

  readonly property var hw: HardwareJs.normalize(Omarchy.hardware)

  PrefsConfirm {
    id: hybridGpuConfirm
    title: "Switch GPU mode"
    message: Omarchy.hybridGpuMode === "Integrated"
      ? "Turn the dedicated GPU on (hybrid) and reboot."
      : "Use only the integrated GPU and reboot."
    confirmText: "Switch and reboot"
    onConfirmed: Omarchy.toggleHybridGpu()
  }

  Component.onCompleted: {
    if (Lab.on("machinecard")) Omarchy.labLoadCard()
    hybridGpuConfirm.parent = root.prefsOverlay
  }

  function hasText() {
    for (var i = 0; i < arguments.length; i++) {
      if (String(arguments[i] || "").length) return true
    }
    return false
  }

  function listQuery(list) {
    return (list instanceof Array) && list.length > 0 ? root.query : "."
  }

  function objectQuery(obj, keys) {
    if (!obj) return "."
    for (var i = 0; i < keys.length; i++) {
      var value = obj[keys[i]]
      if (value === true) return root.query
      if (typeof value === "number" && value) return root.query
      if (String(value || "").length) return root.query
    }
    return "."
  }

  function firmwareQuery() {
    if (root.objectQuery(root.hw.bios, ["vendor", "version", "date"]) !== ".")
      return root.query
    if (root.hw.bios.uefi || root.hw.tpm.present || root.hw.secureBoot.available)
      return root.query
    return "."
  }

  function copyField(text) {
    Omarchy.copyText(String(text || ""))
  }

  // Lab(machinecard): the Atmos host card.
  //
  // One box and one button. An earlier version had four rows of controls and
  // Fred's verdict was that it was too busy, which was right -- the feature
  // is "describe it and get a card", and every extra control was me exposing
  // my own plumbing.
  //
  // The agent designs the whole composition: where the mark sits, where the
  // type sits, how the specs are arranged, what the art does and where.
  // Atmos keeps only the three things that make it an Atmos card -- the mark
  // is always on it, every spec row is always on it, and the type is always
  // readable. Everything on it is built by an allow-list, so the serial and
  // SKU rows further down this same page can never reach it.
  property bool awaitingDesign: false
  property string wish: ""

  Connections {
    target: Omarchy
    enabled: Lab.on("machinecard")
    function onLabAgentAnswerChanged() {
      if (Omarchy.labAgentAnswer.length === 0 || !root.awaitingDesign) return
      root.awaitingDesign = false
      Omarchy.labApplyScene(Omarchy.labAgentAnswer)
    }
  }

  PrefsGroup {
    title: "Host card"
    query: root.query
    visible: Lab.on("machinecard")
    detail: "A wallpaper-sized card of your specs, designed by your coding agent in your own theme. Nothing identifying goes on it: no serial, no SKU, no hostname, no addresses."

    PrefsRow {
      label: "Describe the card you want"
      description: "A sentence or a paragraph, about the feeling rather than the layout. \"Dragons and fire.\" \"Cold machine deep underwater, almost silent.\" Your agent designs it from there."
      query: root.query
      stretchControl: true
      keywords: ["card", "share", "wallpaper", "brag", "graphic", "custom", "art", "host"]

      Column {
        width: parent ? parent.width : 0
        spacing: Theme.space

        PrefsField {
          width: parent.width
          placeholder: "I want dragons and fire…"
          value: root.wish
          onEdited: function (value) { root.wish = value }
          onSubmitted: function (value) { root.makeCard(value) }
        }

        PrefsButton {
          text: Omarchy.labAgentBusy ? "Drawing…" : "Make it"
          primary: true
          enabled: !Omarchy.labAgentBusy && root.wish.length > 0
          onClicked: root.makeCard(root.wish)
        }

        // Waiting has to be unmissable. Drawing a scene takes a coding agent
        // tens of seconds, which is long enough that a thin bar reads as a
        // frozen window -- the first version of this looked broken to Fred
        // and he was right. A framed panel, the agent by name, a live clock
        // and a moving bar, so there is no question it is working.
        Rectangle {
          width: parent.width
          visible: Omarchy.labAgentBusy
          implicitHeight: waitCol.implicitHeight + Theme.spaceMd * 2
          height: implicitHeight
          color: Theme.accentFill(0.10)
          border.width: Theme.borderWidth
          border.color: Theme.accent

          Column {
            id: waitCol
            x: Theme.spaceMd
            y: Theme.spaceMd
            width: parent.width - Theme.spaceMd * 2
            spacing: Theme.space

            PrefsText {
              width: parent.width
              text: Omarchy.labSceneStage.length > 0
                ? Omarchy.labSceneStage + "…"
                : "Working…"
              color: Theme.foreground
              font.family: Theme.fontFamily
              font.pixelSize: Theme.labelSize
              font.bold: true
            }

            PrefsText {
              width: parent.width
              text: Omarchy.labAgentSeconds + "s elapsed. Drawing a whole scene usually takes 30 to 90 seconds. Leave this page open."
              color: Theme.muted
              font.family: Theme.fontFamily
              font.pixelSize: Theme.captionSize
              wrapMode: Text.WordWrap
            }

            // No percentage: an agent reports none, and a bar with a number
            // on it would be a lie. This says alive; the clock says how long.
            PrefsProgress {
              width: parent.width
              indeterminate: true
            }
          }
        }

        PrefsText {
          width: parent.width
          visible: !Omarchy.labAgentBusy && Omarchy.labAgentError.length > 0
          text: "Your agent could not answer: " + Omarchy.labAgentError
          color: Theme.urgent
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          wrapMode: Text.WordWrap
        }
      }
    }

    PrefsRow {
      label: "Your card"
      description: Omarchy.labSceneSvg.length > 0
        ? Omarchy.labCard.rows.length + " facts · " + root.cardW + "x" + root.cardH + " · drawn by " + Omarchy.labAgentName
        : Omarchy.labCard.rows.length + " facts · " + root.cardW + "x" + root.cardH + " · describe a scene and press Make it"
      query: root.query
      stretchControl: true

      Item {
        width: parent ? parent.width : 0
        // Drawn at full output size and scaled to fit, so the preview and
        // the exported file cannot disagree.
        readonly property real fit: Math.min(1, (width > 0 ? width : root.cardW) / root.cardW)
        implicitHeight: Math.round(root.cardH * fit) + Theme.space

        MachineCard {
          id: cardArt
          width: root.cardW
          height: root.cardH
          card: Omarchy.labCard
          layout: Omarchy.labCardLayout
          sceneSvg: Omarchy.labSceneSvg
          transform: Scale { xScale: parent.fit; yScale: parent.fit }
        }
      }
    }

    PrefsRow {
      label: "Keep it"
      description: Omarchy.labCardStatus.length > 0
        ? Omarchy.labCardStatus
        : "Save writes a PNG. Copy puts the picture itself on the clipboard, not a path."
      query: root.query

      Row {
        spacing: Theme.space

        PrefsButton {
          text: "Save"
          onClicked: root.exportCard("save")
        }

        PrefsButton {
          text: "Copy"
          onClicked: root.exportCard("copy")
        }

        PrefsButton {
          text: "Set as wallpaper"
          primary: true
          onClicked: root.exportCard("wallpaper")
        }
      }
    }
  }

  // Output size follows the screen, so a saved card is a wallpaper that fits
  // rather than something to scale afterwards.
  readonly property int cardW: Omarchy.labCardWidth > 0 ? Omarchy.labCardWidth : 1920
  readonly property int cardH: Omarchy.labCardHeight > 0 ? Omarchy.labCardHeight : 1080

  function makeCard(value) {
    root.wish = String(value || "")
    if (root.wish.length === 0) return
    root.awaitingDesign = true
    Omarchy.labMakeScene(root.wish, root.cardW, root.cardH)
  }

  // grabToImage lives here because only this page holds the live Item. Atmos
  // owns the filesystem, clipboard and wallpaper ends.
  function exportCard(what) {
    var target = (Omarchy.picturesDir || Omarchy.home) + "/omarchy-host-card.png"
    cardArt.grabToImage(function (result) {
      if (!result || !result.saveToFile(target)) {
        Omarchy.labCardStatus = "Could not write " + target
        return
      }
      if (what === "copy") Omarchy.labCardCopy(target)
      else if (what === "wallpaper") Omarchy.labCardWallpaper(target)
      else Omarchy.labCardSaved(target)
    }, Qt.size(root.cardW, root.cardH))
  }

  PrefsGroup {
    title: "Machine"
    query: root.objectQuery(root.hw.machine, ["vendor", "name", "family", "chassis", "version", "serial", "sku"])
    detail: "Name and chassis from DMI. Refresh reads the machine again, including memory use."

    SettingRow {
      available: root.hasText(root.hw.machine.vendor, root.hw.machine.name, root.hw.machine.family, root.hw.machine.chassis)
      label: root.hw.machine.name || root.hw.machine.family || "This machine"
      description: HardwareJs.machineSummary(root.hw.machine) || "The firmware did not name this chassis."
      hint: "/sys/class/dmi/id"
      query: root.query
      keywords: ["machine", "system", "product", "chassis", "laptop", "desktop", "dmi", "smbios"]

      PrefsButton {
        text: "Copy"
        enabled: root.hasText(HardwareJs.machineSummary(root.hw.machine), root.hw.machine.name)
        onClicked: root.copyField(HardwareJs.machineSummary(root.hw.machine) || root.hw.machine.name)
      }
    }

    SettingRow {
      available: root.hasText(root.hw.machine.serial, root.hw.machine.sku)
      label: "Identity"
      description: root.hasText(root.hw.machine.serial)
        ? ("Serial " + root.hw.machine.serial + (root.hw.machine.sku ? (". SKU " + root.hw.machine.sku) : "") + ".")
        : ("SKU " + root.hw.machine.sku + ".")
      hint: "/sys/class/dmi/id/product_serial"
      query: root.query
      keywords: ["serial", "sku", "service tag"]

      PrefsButton {
        text: root.hasText(root.hw.machine.serial) ? "Copy serial" : "Copy SKU"
        enabled: root.hasText(root.hw.machine.serial, root.hw.machine.sku)
        onClicked: root.copyField(root.hw.machine.serial || root.hw.machine.sku)
      }
    }

    SettingRow {
      label: "Refresh"
      description: "Read the units again. Memory use and temperatures change while the machine runs."
      hint: "snapshot"
      query: root.query
      keywords: ["reload", "rescan", "inventory"]

      PrefsButton {
        text: "Refresh"
        onClicked: Omarchy.refresh()
      }
    }
  }

  PrefsGroup {
    title: "Motherboard"
    query: root.objectQuery(root.hw.board, ["vendor", "name", "version"])
    detail: "The board DMI names. Chipset is the host bridge on that board, listed next."

    SettingRow {
      available: root.hasText(root.hw.board.vendor, root.hw.board.name)
      label: root.hw.board.name || "Board"
      description: HardwareJs.boardSummary(root.hw.board)
      hint: "/sys/class/dmi/id/board_name"
      query: root.query
      keywords: ["motherboard", "mainboard", "board", "baseboard"]

      PrefsButton {
        text: "Copy"
        enabled: root.hasText(HardwareJs.boardSummary(root.hw.board))
        onClicked: root.copyField(HardwareJs.boardSummary(root.hw.board))
      }
    }
  }

  PrefsGroup {
    title: "Chipset"
    query: root.objectQuery(root.hw.chipset, ["name", "vendor", "pciId", "southbridge"])
    detail: "The PCI host bridge, and the ISA or LPC bridge when the kernel names one. That is the chipset the CPU talks to."

    SettingRow {
      available: root.hasText(root.hw.chipset.name, root.hw.chipset.vendor, root.hw.chipset.pciId)
      label: root.hw.chipset.name || "Host bridge"
      description: HardwareJs.chipsetSummary(root.hw.chipset)
      hint: "lspci"
      query: root.query
      keywords: ["chipset", "northbridge", "southbridge", "host bridge", "isa", "lpc", "pch", "pci"]

      PrefsButton {
        text: "Copy"
        enabled: root.hasText(HardwareJs.chipsetSummary(root.hw.chipset))
        onClicked: root.copyField(HardwareJs.chipsetSummary(root.hw.chipset))
      }
    }
  }

  PrefsGroup {
    title: "Firmware"
    query: root.firmwareQuery()
    detail: "BIOS or UEFI from DMI, plus TPM and Secure Boot when the firmware exposes them."

    SettingRow {
      available: root.hasText(root.hw.bios.vendor, root.hw.bios.version, root.hw.bios.date) || root.hw.bios.uefi
      label: "BIOS"
      description: HardwareJs.biosSummary(root.hw.bios) || (root.hw.bios.uefi ? "UEFI firmware." : "")
      hint: "/sys/class/dmi/id/bios_version"
      query: root.query
      keywords: ["bios", "uefi", "firmware", "efi"]

      PrefsButton {
        text: "Copy"
        enabled: root.hasText(HardwareJs.biosSummary(root.hw.bios), root.hw.bios.version)
        onClicked: root.copyField(HardwareJs.biosSummary(root.hw.bios) || root.hw.bios.version)
      }
    }

    SettingRow {
      available: root.hw.secureBoot.available
      label: "Secure Boot"
      description: root.hw.secureBoot.enabled
        ? "The firmware is verifying boot loaders. Change this in UEFI setup, not here."
        : "The firmware is not verifying boot loaders. Change this in UEFI setup, not here."
      hint: "/sys/firmware/efi"
      query: root.query
      keywords: ["secure boot", "efi", "mok"]
      valueText: root.hw.secureBoot.enabled ? "On" : "Off"
    }

    SettingRow {
      available: root.hw.tpm.present
      label: "TPM"
      description: HardwareJs.tpmSummary(root.hw.tpm)
      hint: "/sys/class/tpm"
      query: root.query
      keywords: ["tpm", "trusted platform"]

      PrefsButton {
        text: "Copy"
        enabled: root.hasText(HardwareJs.tpmSummary(root.hw.tpm))
        onClicked: root.copyField(HardwareJs.tpmSummary(root.hw.tpm))
      }
    }
  }

  PrefsGroup {
    title: "Processor"
    query: root.objectQuery(root.hw.cpu, ["model", "vendor", "arch", "cores"])
    detail: "Cores and threads from the kernel. Flags are the ones that matter for guests and SIMD."

    SettingRow {
      available: root.hasText(root.hw.cpu.model, root.hw.cpu.vendor)
      label: root.hw.cpu.model || "CPU"
      description: HardwareJs.cpuSummary(root.hw.cpu)
      hint: "lscpu"
      query: root.query
      keywords: ["cpu", "processor", "core", "thread", "avx", "intel", "amd", "arm"]

      PrefsButton {
        text: "Copy"
        enabled: root.hasText(root.hw.cpu.model)
        onClicked: root.copyField(root.hw.cpu.model)
      }
    }
  }

  PrefsGroup {
    framed: true
    title: "Memory"
    query: root.hw.memory.total > 0 || root.hw.memory.modules.length > 0 ? root.query : "."
    detail: "Use comes from /proc/meminfo. Modules are SMBIOS type 17 when the firmware table is readable without root."

    SettingRow {
      available: root.hw.memory.total > 0
      stretchControl: true
      label: "Installed"
      description: ""
      hint: "/proc/meminfo"
      query: root.query
      keywords: ["ram", "memory", "dimm", "ddr", "swap"]

      PrefsUsageBar {
        width: parent.width
        used: root.hw.memory.used
        size: root.hw.memory.total
        avail: root.hw.memory.available
      }
    }

    SettingRow {
      available: root.hw.memory.swapTotal > 0
      stretchControl: true
      label: "Swap"
      description: ""
      hint: "/proc/meminfo"
      query: root.query
      keywords: ["swap", "zram"]

      PrefsUsageBar {
        width: parent.width
        used: root.hw.memory.swapUsed
        size: root.hw.memory.swapTotal
        avail: Math.max(0, root.hw.memory.swapTotal - root.hw.memory.swapUsed)
      }
    }

    Repeater {
      model: root.hw.memory.modules

      SettingRow {
        required property var modelData
        sectionHelp: false
        label: (modelData && modelData.locator) || "DIMM"
        description: HardwareJs.moduleSummary(modelData)
        hint: "dmidecode -t memory"
        query: root.query
        keywords: ["dimm", "sodimm", "ddr4", "ddr5", "module", "bank"]

        PrefsButton {
          text: "Copy"
          enabled: !!(modelData && HardwareJs.moduleSummary(modelData))
          onClicked: root.copyField(HardwareJs.moduleSummary(modelData))
        }
      }
    }
  }

  PrefsGroup {
    framed: true
    title: "Graphics"
    query: (root.hw.gpus.length || Omarchy.hwNvidia || Omarchy.hwVulkan || Omarchy.hybridGpuAvailable) ? root.query : "."
    detail: "PCI display devices, plus the DRM driver when the kernel bound one. Active is NVIDIA when that GPU is present, otherwise Vulkan. Hybrid switching reboots."

    Repeater {
      model: root.hw.gpus

      SettingRow {
        required property var modelData
        label: (modelData && modelData.name) || "GPU"
        description: HardwareJs.gpuSummary(modelData)
        hint: "lspci"
        query: root.query
        keywords: ["gpu", "graphics", "vga", "nvidia", "amd", "intel", "drm"]

        PrefsButton {
          text: "Copy"
          enabled: !!(modelData && (modelData.name || HardwareJs.gpuSummary(modelData)))
          onClicked: root.copyField(HardwareJs.gpuSummary(modelData) || (modelData && modelData.name) || "")
        }
      }
    }

    SettingRow {
      available: Omarchy.hwNvidia || Omarchy.hwVulkan
      label: "Active stack"
      description: Omarchy.hwNvidia
        ? (Omarchy.hwNvidiaGsp
          ? "NVIDIA, with GSP firmware (Turing or newer)."
          : (Omarchy.hwNvidiaWithoutGsp
            ? "NVIDIA, without GSP firmware (Maxwell, Pascal, or Volta)."
            : "NVIDIA."))
        : "Vulkan."
      hint: Omarchy.hwNvidia ? "omarchy hw nvidia" : "omarchy hw vulkan"
      query: root.query
      keywords: ["vulkan", "nvidia", "gsp", "turing", "cuda", "api"]

      PrefsButton {
        text: "Copy"
        onClicked: root.copyField(Omarchy.hwNvidia
          ? (Omarchy.hwNvidiaGsp ? "NVIDIA GSP" : (Omarchy.hwNvidiaWithoutGsp ? "NVIDIA without GSP" : "NVIDIA"))
          : "Vulkan")
      }
    }

    SettingRow {
      available: Omarchy.hybridGpuAvailable
      label: "Hybrid GPU"
      description: Omarchy.hybridGpuMode === "Integrated"
        ? "Using the integrated GPU only. Switch to hybrid if you want the dedicated GPU."
        : (Omarchy.hybridGpuMode === "Hybrid"
          ? "Hybrid mode. The dedicated GPU can wake for a game or CUDA."
          : "This machine can switch between integrated-only and hybrid.")
      hint: "omarchy toggle hybrid gpu"
      query: root.query
      keywords: ["hybrid", "supergfx", "igpu"]

      PrefsButton {
        text: "Switch…"
        enabled: !Omarchy.jobBusy && Omarchy.hybridGpuAvailable
        onClicked: hybridGpuConfirm.ask()
      }
    }
  }

  PrefsGroup {
    framed: true
    title: "NPU"
    query: root.listQuery(root.hw.npus)
    detail: "A neural processor on PCI, such as AMD XDNA, when one is present."

    Repeater {
      model: root.hw.npus

      SettingRow {
        required property var modelData
        label: (modelData && modelData.name) || "NPU"
        description: HardwareJs.npuSummary(modelData)
        hint: "lspci"
        query: root.query
        keywords: ["npu", "xdna", "neural", "ai", "tpu", "accelerator"]

        PrefsButton {
          text: "Copy"
          enabled: !!(modelData && (modelData.name || HardwareJs.npuSummary(modelData)))
          onClicked: root.copyField(HardwareJs.npuSummary(modelData) || (modelData && modelData.name) || "")
        }
      }
    }
  }

  PrefsGroup {
    framed: true
    title: "Network adapters"
    query: root.listQuery(root.hw.nics)
    detail: "Physical interfaces the kernel registered. Virtual bridges and containers stay off this list."

    Repeater {
      model: root.hw.nics

      SettingRow {
        required property var modelData
        label: (modelData && (modelData.iface || modelData.name)) || "NIC"
        description: HardwareJs.nicSummary(modelData)
        hint: "/sys/class/net"
        query: root.query
        keywords: ["nic", "ethernet", "wifi", "wlan", "adapter", "mac"]

        PrefsButton {
          text: modelData && modelData.mac ? "Copy MAC" : "Copy"
          enabled: !!(modelData && (modelData.mac || modelData.iface || modelData.name))
          onClicked: root.copyField((modelData && (modelData.mac || modelData.iface || modelData.name)) || "")
        }
      }
    }
  }

  PrefsGroup {
    framed: true
    title: "Audio"
    query: root.listQuery(root.hw.audio)
    detail: "Sound cards from ALSA. Volume and sinks stay on the Sound page."

    Repeater {
      model: root.hw.audio

      SettingRow {
        required property var modelData
        label: (modelData && modelData.name) || "Audio"
        description: modelData && modelData.driver ? ("ALSA " + modelData.driver + ". Volume and sinks are on Sound.") : "ALSA card. Volume and sinks are on Sound."
        hint: "/proc/asound/cards"
        query: root.query
        keywords: ["audio", "sound", "alsa", "card"]

        PrefsButton {
          text: "Copy"
          enabled: !!(modelData && modelData.name)
          onClicked: root.copyField((modelData && modelData.name) || "")
        }
      }
    }
  }

  PrefsGroup {
    framed: true
    title: "USB"
    query: root.listQuery(root.hw.usb)
    detail: "Devices on the USB buses that published a product name."

    Repeater {
      model: root.hw.usb

      SettingRow {
        required property var modelData
        label: (modelData && modelData.name) || "USB"
        description: [
          modelData && modelData.vendor ? modelData.vendor : "",
          modelData && modelData.speed ? (modelData.speed + " Mb/s") : ""
        ].filter(function(bit) { return bit.length }).join(". ") + ((modelData && (modelData.vendor || modelData.speed)) ? "." : "")
        hint: "/sys/bus/usb/devices"
        query: root.query
        keywords: ["usb", "hub", "keyboard", "mouse", "storage"]

        PrefsButton {
          text: "Copy"
          enabled: !!(modelData && modelData.name)
          onClicked: root.copyField((modelData && modelData.name) || "")
        }
      }
    }
  }

  PrefsGroup {
    framed: true
    title: "Battery"
    query: root.listQuery(root.hw.batteries)
    detail: "Charge from sysfs. Profiles and the bar percentage stay on the Power page."

    Repeater {
      model: root.hw.batteries

      SettingRow {
        required property var modelData
        stretchControl: true
        label: (modelData && modelData.name) || "Battery"
        description: {
          var s = HardwareJs.batterySummary(modelData)
          return s ? (s + " Charge profiles stay on Power.") : "Charge profiles stay on Power."
        }
        hint: "/sys/class/power_supply"
        query: root.query
        keywords: ["battery", "charge", "capacity"]

        Column {
          width: parent.width
          spacing: Theme.space

          PrefsProgress {
            width: parent.width
            visible: !!(modelData && modelData.capacity)
            from: 0
            to: 100
            value: modelData && modelData.capacity ? modelData.capacity : 0
            valueText: (modelData && modelData.capacity ? modelData.capacity : 0) + "%"
          }

          Row {
            spacing: Theme.space
            PrefsButton {
              text: "Show battery"
              enabled: Omarchy.batteryPresent
              onClicked: Omarchy.showBatteryNotification()
            }
            PrefsButton {
              text: "Copy"
              enabled: !!HardwareJs.batterySummary(modelData)
              onClicked: root.copyField(HardwareJs.batterySummary(modelData))
            }
          }
        }
      }
    }
  }

  PrefsGroup {
    framed: true
    title: "Thermal"
    query: root.listQuery(root.hw.thermals)
    detail: "Zones the kernel exported. Refresh if you want a newer reading."

    Repeater {
      model: root.hw.thermals

      SettingRow {
        required property var modelData
        label: (modelData && (modelData.name || modelData.type)) || "Sensor"
        description: HardwareJs.thermalSummary(modelData)
        hint: "/sys/class/thermal"
        query: root.query
        keywords: ["thermal", "temperature", "sensor", "heat"]

        PrefsButton {
          text: "Copy"
          enabled: !!HardwareJs.thermalSummary(modelData)
          onClicked: root.copyField(HardwareJs.thermalSummary(modelData))
        }
      }
    }
  }

  PrefsGroup {
    title: "Virtualization"
    query: root.objectQuery(root.hw.virtualization, ["hypervisor", "guest", "kvm"])
    detail: "Whether this OS is a guest, and whether KVM can run guests here."

    SettingRow {
      available: root.hw.virtualization.guest || root.hw.virtualization.kvm || root.hasText(root.hw.virtualization.hypervisor)
      label: root.hw.virtualization.guest ? "Guest" : "Host"
      description: HardwareJs.virtSummary(root.hw.virtualization) || "No hypervisor was reported."
      hint: "lscpu"
      query: root.query
      keywords: ["kvm", "qemu", "hypervisor", "vm", "virtual", "guest"]

      PrefsButton {
        text: "Copy"
        enabled: root.hasText(HardwareJs.virtSummary(root.hw.virtualization))
        onClicked: root.copyField(HardwareJs.virtSummary(root.hw.virtualization))
      }
    }
  }
}
