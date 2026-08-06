pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "DeviceBattery.js" as DeviceBattery

// One process-wide state owner for every Device Battery Stats widget instance.
// Widgets call acquire() while mounted and release() when destroyed, so the
// collector only runs while something on screen is reading it.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property int contractVersion: 1
  readonly property bool ready: true

  readonly property string scriptPath: manifest && manifest.__sourceDir
    ? manifest.__sourceDir + "/scripts/device-battery.sh" : ""

  property int refreshIntervalMs: 30000
  property int consumers: 0

  property var devices: []
  property var sources: ({})
  property string lastUpdated: ""
  property string error: ""

  readonly property bool wanted: consumers > 0
  readonly property var summary: DeviceBattery.summarize(devices)

  function acquire() { root.consumers++ }
  function release() { root.consumers = Math.max(0, root.consumers - 1) }

  function refresh() {
    if (!root.wanted || root.scriptPath === "") return
    if (pollProc.running) {
      root.refreshPending = true
      return
    }
    pollProc.running = true
  }

  property bool refreshPending: false

  onManifestChanged: Qt.callLater(root.refresh)

  Process {
    id: pollProc
    command: root.scriptPath !== "" ? [root.scriptPath] : []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = DeviceBattery.parse(text)
        root.devices = parsed.devices
        root.sources = parsed.sources
        root.lastUpdated = parsed.timestamp || ""
        root.error = parsed.ok ? "" : "collector reported an error"
      }
    }

    onExited: function(code) {
      if (code !== 0 && root.devices.length === 0)
        root.error = "collector exited with code " + code
      if (root.refreshPending) {
        root.refreshPending = false
        Qt.callLater(root.refresh)
      }
    }
  }

  Timer {
    id: pollTimer
    interval: root.refreshIntervalMs
    running: root.wanted && root.scriptPath !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  onWantedChanged: {
    if (!root.wanted) {
      root.refreshPending = false
      pollProc.running = false
    }
  }
}
