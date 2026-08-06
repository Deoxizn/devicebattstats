pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "DeviceBattery.js" as DeviceBattery

// Bar button for Device Battery Stats and the host for the device list popup.
// By default it shows one glyph per connected device (keyboard, mouse, ...);
// a battery glyph plus the lowest known charge can be restored with the
// displayMode setting (see README).
//
// Left click reveals the panel; right click is reserved for future actions.
//
// Theming: colors and sizes come from the active bar. A Shibumi bar hands us
// its VisualTokens (bar.visualTokens); any other host is covered by HostTokens,
// which derives the same interface from the bar's standard properties. See
// HostTokens.qml for the values the widget reads.
BarWidget {
  id: root
  moduleName: "dev.deoxizn.devicebattstats"

  readonly property string serviceId: "dev.deoxizn.devicebattstats"
  readonly property var deviceService: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(serviceId) : null

  HostTokens {
    id: hostTokens
    bar: root.bar
  }

  // Prefer the bar's own tokens (Shibumi VisualTokens) so per-widget color
  // fills configured in Shibumi settings keep working; fall back to the
  // built-in adapter for the stock bar and other Quattro hosts.
  readonly property var tokens: bar && "visualTokens" in bar && bar.visualTokens
    ? bar.visualTokens : hostTokens

  readonly property var devices: deviceService ? deviceService.devices : []
  readonly property var summary: DeviceBattery.summarize(devices)

  readonly property string displayMode: String(setting("displayMode",
    setting("compact", false) ? "icon" : "devices"))
  readonly property bool devicesMode: displayMode === "devices"
  readonly property bool iconOnly: displayMode === "icon"
  readonly property var deviceGlyphs: DeviceBattery.connectedGlyphs(devices)
  readonly property string iconText: (root.devicesMode || displayMode === "text")
    ? "" : DeviceBattery.pillIcon(summary)
  readonly property string percentText: root.devicesMode ? ""
    : (summary.lowest >= 0 ? summary.lowest + "%" : "\u2014")
  readonly property bool pillActive: summary.anyLow || summary.anyCharging
  readonly property string tooltipText: DeviceBattery.pillTooltip(summary, devices)

  // ---- Popup contract. Bar.findPanelWidget requires open/close/opened on
  //      the widget root; the popout coordinator compares against the slot's
  //      activeItem, which is this widget.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property real openPanelIndicatorWidth: Math.max(
    Style.space(10), pill.labelWidth)
  readonly property real openPanelIndicatorHeight: Math.max(
    Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("tokens" in target) target.tokens = root.tokens
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = pill
    if ("hostWidget" in target) target.hostWidget = root
  }

  // ---- Service acquisition. The service is ensured by the shell at startup,
  //      but the widget can mount before it exists; retry a short window.
  property bool serviceClaimed: false
  property int serviceTries: 0

  function tryClaimService() {
    if (root.deviceService && !root.serviceClaimed) {
      if (typeof root.deviceService.acquire === "function")
        root.deviceService.acquire()
      root.serviceClaimed = true
      root.serviceTries = 0
      serviceRetry.stop()
    } else if (!root.deviceService && root.serviceTries < 30) {
      root.serviceTries++
      serviceRetry.restart()
    }
  }

  onDeviceServiceChanged: tryClaimService()
  Component.onCompleted: tryClaimService()
  Component.onDestruction: {
    if (root.serviceClaimed && root.deviceService
        && typeof root.deviceService.release === "function")
      root.deviceService.release()
    serviceRetry.stop()
  }

  Timer {
    id: serviceRetry
    interval: 500
    onTriggered: root.tryClaimService()
  }

  visible: root.devicesMode ? root.deviceGlyphs.length > 0 : summary.knownCount > 0
  implicitWidth: visible ? pill.implicitWidth : 0
  implicitHeight: visible ? pill.implicitHeight : 0

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onTokensChanged: injectPanel()

  DevicePill {
    id: pill
    bar: root.bar
    tokens: root.tokens
    glyphs: root.deviceGlyphs
    iconText: root.iconText
    labelText: root.percentText
    tooltipText: root.tooltipText
    active: root.pillActive
    iconOnly: root.iconOnly
    onPressed: function(button) {
      if (button === Qt.LeftButton) root.togglePanel()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("DevicePanel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
