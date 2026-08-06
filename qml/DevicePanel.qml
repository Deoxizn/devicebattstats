pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "DeviceBattery.js" as DeviceBattery

// Popup listing every wireless device the collector found, with its charge
// level. Sits beside the pill on the bar; the Shibumi host repaints the card
// with its own chrome via WidgetSlot's hosted-panel adapter.
Panel {
  id: root
  moduleName: "dev.deoxizn.devicebattstats"
  ipcTarget: ""
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var tokens: null
  readonly property var barIdentity: hostWidget || root

  readonly property var service: bar && bar.shell
    && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("dev.deoxizn.devicebattstats") : null
  readonly property var devices: service ? service.devices : []

  property int selectedIndex: -1

  readonly property color contentForeground: tokens && tokens.ink
    ? tokens.ink : (bar ? bar.foreground : Color.foreground)
  readonly property string contentFontFamily: tokens && tokens.fontFamily
    ? tokens.fontFamily : (bar ? bar.fontFamily : Style.font.family)
  readonly property int labelSize: tokens ? tokens.labelSize : Style.font.body
  readonly property int captionSize: tokens ? tokens.captionSize : Style.font.caption
  readonly property int iconSize: tokens ? tokens.iconSize : Style.space(15)

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function select(index) {
    if (index >= 0 && index < root.devices.length) root.selectedIndex = index
  }

  function moveSelection(delta) {
    if (root.devices.length === 0) return
    var next = root.selectedIndex < 0 ? 0
      : (root.selectedIndex + delta + root.devices.length) % root.devices.length
    root.selectedIndex = next
    ensureRowVisible(next)
  }

  function ensureRowVisible(index) {
    if (index < 0 || listScroll.contentHeight <= 0) return
    var y = index * rowSpacing - listScroll.contentY
    if (y < 0 || y + rowHeight > listScroll.height)
      listScroll.contentY = Math.max(0, Math.min(
        index * rowSpacing, listScroll.contentHeight - listScroll.height))
  }

  readonly property real rowHeight: Style.space(46)
  readonly property real rowSpacing: rowHeight + Style.space(2)
  readonly property real headerHeight: Style.space(34)

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(
      root.headerHeight + root.devices.length * root.rowSpacing)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveSelection(dy > 0 ? 1 : -1)
      }
      onActivateRequested: {}
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "d" || t === "D") root.close()
      }
    }

    Flickable {
      id: listScroll
      anchors.fill: parent
      contentWidth: listColumn.width
      contentHeight: listColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: listColumn
        width: Math.max(listScroll.width, Style.space(300))
        spacing: Style.space(2)

        // ---- Header: name + last-polled time.
        Item {
          width: parent.width
          height: root.headerHeight
          visible: root.devices.length > 0

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            text: "WIRELESS BATTERIES"
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: root.captionSize
            font.letterSpacing: 1
            renderType: Text.NativeRendering
          }

          Text {
            anchors.right: parent.right
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            text: root.devices.length + (root.devices.length === 1 ? " device" : " devices")
            color: Qt.darker(root.contentForeground, 1.9)
            font.family: root.contentFontFamily
            font.pixelSize: root.captionSize
            renderType: Text.NativeRendering
          }
        }

        Repeater {
          model: root.devices

          delegate: DeviceRow {
            width: listColumn.width
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onActivate: root.select(index)
          }
        }

        Item {
          visible: root.devices.length === 0
          width: parent.width
          height: Style.space(56)

          Text {
            anchors.centerIn: parent
            text: "No wireless device batteries found"
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: root.labelSize
            renderType: Text.NativeRendering
          }
        }
      }
    }
  }

  component DeviceRow: Item {
    id: row

    required property var modelData
    required property int index

    readonly property var device: modelData
    required property color foreground
    required property string fontFamily
    readonly property bool selected: index === root.selectedIndex
    signal activate()

    implicitHeight: Style.space(46)
    height: implicitHeight

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: row.selected
        ? Style.hoverFillFor(row.foreground, Color.accent) : "transparent"
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.activate()
    }

    Row {
      id: rightGutter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: row.device.percentText
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: root.labelSize
        renderType: Text.NativeRendering
      }

      Item {
        width: Style.space(44)
        height: Style.space(7)
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: Qt.rgba(row.foreground.r, row.foreground.g,
            row.foreground.b, 0.12)

          Rectangle {
            width: parent.width * DeviceBattery.ratio(row.device.percent)
            height: parent.height
            radius: parent.radius
            color: row.device.low
              ? Style.selectedStateColor(row.foreground, Color.accent)
              : Style.normalStateColor(row.foreground, Color.accent)
            Behavior on width {
              NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
          }
        }
      }
    }

    Row {
      id: leftContent
      anchors.left: parent.left
      anchors.leftMargin: Style.space(14)
      anchors.right: rightGutter.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(10)
      clip: true

      IconText {
        id: glyphIcon
        anchors.verticalCenter: parent.verticalCenter
        text: row.device.glyph
        fill: row.device.charging || row.device.low ? 1 : 0
        color: row.device.charging || row.device.low
          ? Style.selectedStateColor(row.foreground, Color.accent)
          : row.foreground
        font.pixelSize: root.iconSize
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)
        width: Math.max(0, leftContent.width - glyphIcon.implicitWidth
          - leftContent.spacing)

        Text {
          width: parent.width
          elide: Text.ElideRight
          text: row.device.name
          color: row.foreground
          font.family: row.fontFamily
          font.pixelSize: root.labelSize
          font.bold: row.selected
          renderType: Text.NativeRendering
        }

        Text {
          width: parent.width
          elide: Text.ElideRight
          text: row.device.detail
          color: Qt.darker(row.foreground, 1.7)
          font.family: row.fontFamily
          font.pixelSize: root.captionSize
          renderType: Text.NativeRendering
        }
      }
    }
  }
}
