pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons

// Bar pill for the Device Battery Stats widget. Composes either one glyph per
// connected device (glyphs), or a single Material Symbols battery glyph and a
// percent label (iconText/labelText). Registers itself with the host bar as a
// click target so panel click-through forwarding and tooltips work on any bar
// that follows Quattro's bar-widget contract (stock bar and Shibumi alike).
Item {
  id: root

  property var bar: null
  property var tokens: null
  property var glyphs: []
  property string iconText: ""
  property string labelText: ""
  property string tooltipText: ""
  property string fontFamily: tokens && tokens.fontFamily
    ? tokens.fontFamily : (bar && bar.fontFamily ? bar.fontFamily : Style.font.family)
  property real fontSize: tokens ? tokens.labelSize : Style.font.body
  property real iconSize: tokens ? tokens.iconSize : Style.space(15)
  property color foreground: tokens ? tokens.ink
    : (bar ? bar.foreground : Color.foreground)
  property color activeColor: tokens ? tokens.seal
    : (bar ? bar.urgent : Color.urgent)
  property bool active: false
  property bool iconOnly: false
  property real horizontalMargin: 8.5
  property real verticalPadding: 6
  property real fixedWidth: -1
  property real fixedHeight: -1

  signal pressed(int button)

  function triggerPress(button) {
    if (root.bar) root.bar.hideTooltip(root)
    root.pressed(button)
  }

  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
  readonly property bool hasVisualContent: glyphs.length > 0
    || iconText !== "" || labelText !== ""
  // Width of the painted content, for the bar's open-panel indicator.
  readonly property real labelWidth: root.iconOnly ? glyph.implicitWidth
    : row.implicitWidth

  visible: hasVisualContent
  implicitWidth: fixedWidth > 0 ? fixedWidth
    : (vertical ? barSize : Math.max(12, row.implicitWidth + horizontalMargin * 2))
  implicitHeight: fixedHeight > 0 ? fixedHeight
    : (vertical ? Math.max(12, row.implicitHeight + verticalPadding * 2) : barSize)

  property var registeredBar: null

  function syncClickRegistration() {
    if (registeredBar && registeredBar.unregisterClickTarget)
      registeredBar.unregisterClickTarget(root)
    registeredBar = root.bar
    if (registeredBar && registeredBar.registerClickTarget)
      registeredBar.registerClickTarget(root)
  }

  onBarChanged: syncClickRegistration()
  onVisibleChanged: if (!visible) { if (root.bar) root.bar.hideTooltip(root) }
  Component.onCompleted: syncClickRegistration()
  Component.onDestruction: {
    if (registeredBar && registeredBar.unregisterClickTarget)
      registeredBar.unregisterClickTarget(root)
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(4)

    Repeater {
      model: root.glyphs
      delegate: PillGlyph { }
    }

    IconText {
      id: glyph
      visible: root.iconText !== "" && root.glyphs.length === 0
      anchors.verticalCenter: parent.verticalCenter
      text: root.iconText
      fill: root.active ? 1 : 0
      color: root.active ? root.activeColor : root.foreground
      font.pixelSize: root.iconSize
    }

    Text {
      visible: root.labelText !== "" && !root.iconOnly && root.glyphs.length === 0
      anchors.verticalCenter: parent.verticalCenter
      text: root.labelText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      renderType: Text.NativeRendering
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tooltipText)
    onExited: if (root.bar) root.bar.hideTooltip(root)
    onClicked: function(mouse) { if (mouse.button === Qt.LeftButton) root.triggerPress(mouse.button) }
  }

  component PillGlyph: IconText {
    required property var modelData

    anchors.verticalCenter: parent.verticalCenter
    text: modelData.glyph
    fill: modelData.active ? 1 : 0
    color: modelData.active ? root.activeColor : root.foreground
    font.pixelSize: root.iconSize
  }
}
