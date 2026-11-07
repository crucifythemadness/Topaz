import QtQuick
import QtQuick.Effects

// A white line icon from icons/<name>.svg (24x24, white stroke), tinted to
// `color` with MultiEffect colorization -- one SVG serves every color/hover
// state. Used by IconButton.qml.
Item {
    id: root

    property string name
    property color color: Theme.fgSurfaceVariant
    property int size: 18

    implicitWidth: size
    implicitHeight: size

    Image {
        id: image
        anchors.fill: parent
        source: root.name ? "qrc:/Topaz/icons/" + root.name + ".svg" : ""
        // Rasterized at 2x so the strokes stay crisp on high-DPI screens
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        smooth: true
        mipmap: true
        visible: false
    }

    MultiEffect {
        anchors.fill: image
        source: image
        colorization: 1.0
        colorizationColor: root.color
        brightness: 1.0
    }
}
