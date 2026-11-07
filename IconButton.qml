import QtQuick
import QtQuick.Controls

// Square icon-only button with hover/pressed highlight and a tooltip
// (TopBar's info / gear / fullscreen / minimize / close buttons). `danger`
// turns the hover state red, for destructive actions (close).
AbstractButton {
    id: root

    property string iconName
    property string tooltip
    property color iconColor: Theme.fgSurfaceVariant
    property color hoverColor: Theme.primary
    property bool danger: false
    // 46 = MatryoshkaV2's on-screen size (its 34 px × the user's fontScale 1.35);
    // icon = 50 % = 23 px.
    property int buttonSize: 46

    implicitWidth: buttonSize
    implicitHeight: buttonSize
    hoverEnabled: true
    focusPolicy: Qt.NoFocus

    background: Rectangle {
        radius: Theme.radiusMd
        color: root.down    ? Theme.p20
             : root.hovered ? (root.danger ? Theme.danger15 : Theme.p10)
             :                "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    contentItem: Item {
        SvgIcon {
            anchors.centerIn: parent
            name: root.iconName
            size: Math.round(root.buttonSize * 0.5)
            color: !root.enabled ? Theme.outlineVariant
                 : root.hovered  ? (root.danger ? Theme.danger : root.hoverColor)
                 :                 root.iconColor
        }
    }

    ToolTip.visible: hovered && tooltip.length > 0
    ToolTip.text: tooltip
    ToolTip.delay: 500
}
