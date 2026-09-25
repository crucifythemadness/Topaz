import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified

// Round volume knob for the OS-Volume pane in TopBar.qml: a thick 270° arc,
// open at the bottom, filled with a theme-color gradient up to the current
// value, a white handle at the value end, and a center disc holding the mute
// button (a flat speaker icon) and the percentage.
//
// Dumb component, owner decides: it only displays `value`/`muted` and
// reports user input through moved()/muteToggled() -- TopBar forwards those
// to SystemVolumeController. Input: drag on the ring, mouse wheel anywhere
// on the knob (2 % per notch), click on the speaker icon to (un)mute.
Item {
    id: root

    property int  value: 0          // 0-100
    property bool muted: false

    // True while the user holds the ring -- TopBar keeps the pane open
    // meanwhile, even when the pointer wanders outside it.
    readonly property bool dragging: ringArea.pressed

    signal moved(int value)
    signal muteToggled()

    implicitWidth:  260
    implicitHeight: 260

    // ── Geometry (all derived from the knob size) ────────────────────────
    // Screen angles in degrees, clockwise from 3 o'clock (y points down):
    // the arc starts bottom-left (135°) and runs clockwise over the top to
    // bottom-right (405° = 45°), leaving the 90° gap at the bottom.
    readonly property real startDeg: 135
    readonly property real sweepDeg: 270
    readonly property real size:     Math.min(width, height)
    readonly property real stroke:   size * 0.09
    readonly property real handleR:  stroke * 0.8
    readonly property real glowPad:  8
    readonly property real radius:   size / 2 - handleR - glowPad
    readonly property real cx:       width / 2
    readonly property real cy:       height / 2

    onValueChanged:  arc.requestPaint()
    onMutedChanged:  arc.requestPaint()
    onWidthChanged:  arc.requestPaint()
    onHeightChanged: arc.requestPaint()

    // Gradient color at arc fraction f (0 = start, 1 = end):
    // Theme.secondary → Theme.primary → Theme.tertiary.
    function colorAt(f) {
        const a = f < 0.5 ? Theme.secondary : Theme.primary
        const b = f < 0.5 ? Theme.primary   : Theme.tertiary
        const t = f < 0.5 ? f * 2 : (f - 0.5) * 2
        return Qt.rgba(a.r + (b.r - a.r) * t,
                       a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1)
    }

    // "rgba(...)" string for the Canvas context, with an extra alpha factor.
    function css(c, alpha) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
               + Math.round(c.b * 255) + "," + (c.a * alpha) + ")"
    }

    function rad(deg) { return deg * Math.PI / 180 }

    function clampValue(v) { return Math.max(0, Math.min(100, Math.round(v))) }

    function emitValue(v) {
        v = clampValue(v)
        if (v !== root.value) root.moved(v)
    }

    // ── Ring: track, gradient value arc with glow, handle ────────────────
    Canvas {
        id: arc
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const r      = root.radius
            const f      = root.value / 100
            const endDeg = root.startDeg + root.sweepDeg * f
            const alpha  = root.muted ? 0.35 : 1.0

            // Backdrop: a faint round dark shadow behind the whole knob, so it
            // stays readable when it floats (the pane has no background) over
            // bright album covers. Solid-ish up to the ring's outer edge, then
            // fading to nothing at the canvas edge.
            const outer   = root.size / 2
            const ringOut = r + root.stroke / 2
            const shade = ctx.createRadialGradient(root.cx, root.cy, 0, root.cx, root.cy, outer)
            shade.addColorStop(0, "rgba(0,0,0,0.45)")
            shade.addColorStop(ringOut / outer, "rgba(0,0,0,0.40)")
            shade.addColorStop(1, "rgba(0,0,0,0)")
            ctx.beginPath()
            ctx.arc(root.cx, root.cy, outer, 0, 2 * Math.PI, false)
            ctx.fillStyle = shade
            ctx.fill()

            ctx.lineCap = "round"
            ctx.lineWidth = root.stroke

            // Track -- the full 270°
            ctx.beginPath()
            ctx.arc(root.cx, root.cy, r, root.rad(root.startDeg),
                    root.rad(root.startDeg + root.sweepDeg), false)
            ctx.strokeStyle = root.css(Theme.surfaceContainerHighest, 1)
            ctx.stroke()

            if (f > 0) {
                // Glow: one pass along the value arc in the end color,
                // blurred; the gradient segments below paint over its core.
                ctx.save()
                ctx.shadowBlur  = 16
                ctx.shadowColor = root.css(root.colorAt(f), 0.8 * alpha)
                ctx.beginPath()
                ctx.arc(root.cx, root.cy, r, root.rad(root.startDeg), root.rad(endDeg), false)
                ctx.strokeStyle = root.css(root.colorAt(f), alpha)
                ctx.stroke()
                ctx.restore()

                // Gradient: short segments with interpolated colors. Done by
                // hand (rather than createConicalGradient) so the color order
                // along the arc doesn't depend on the gradient's rotation
                // direction; overlapped slightly so no hairline seams show.
                ctx.lineCap = "butt"
                const stepDeg = 2
                for (let d = 0; d < root.sweepDeg * f; d += stepDeg) {
                    const d1 = Math.min(d + stepDeg, root.sweepDeg * f)
                    ctx.beginPath()
                    ctx.arc(root.cx, root.cy, r, root.rad(root.startDeg + d),
                            root.rad(root.startDeg + d1 + 0.6), false)
                    ctx.strokeStyle = root.css(root.colorAt((d + d1) / 2 / root.sweepDeg), alpha)
                    ctx.stroke()
                }
                // Round start cap in the start color (the end sits under the handle)
                const sx = root.cx + r * Math.cos(root.rad(root.startDeg))
                const sy = root.cy + r * Math.sin(root.rad(root.startDeg))
                ctx.beginPath()
                ctx.arc(sx, sy, root.stroke / 2, 0, 2 * Math.PI, false)
                ctx.fillStyle = root.css(root.colorAt(0), alpha)
                ctx.fill()
            }

            // Handle -- white circle at the value end, soft drop shadow
            const hx = root.cx + r * Math.cos(root.rad(endDeg))
            const hy = root.cy + r * Math.sin(root.rad(endDeg))
            ctx.save()
            ctx.shadowBlur    = 8
            ctx.shadowOffsetY = 2
            ctx.shadowColor   = "rgba(0,0,0,0.5)"
            ctx.beginPath()
            ctx.arc(hx, hy, root.handleR, 0, 2 * Math.PI, false)
            ctx.fillStyle = root.css(Theme.fgSurface, 1)
            ctx.fill()
            ctx.restore()
        }
    }

    // Drag on the ring. Presses away from the ring (the center disc, the
    // corners) are rejected so they reach whatever lies below -- the mute
    // button sits on top anyway.
    MouseArea {
        id: ringArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        preventStealing: true

        function valueAt(x, y) {
            let deg = Math.atan2(y - root.cy, x - root.cx) * 180 / Math.PI   // -180..180, clockwise
            let rel = (deg - root.startDeg + 720) % 360                        // 0 at the arc start
            if (rel > root.sweepDeg)                                          // inside the bottom gap:
                return rel < root.sweepDeg + (360 - root.sweepDeg) / 2 ? 100 : 0   // nearer end
            return rel / root.sweepDeg * 100
        }

        onPressed: (mouse) => {
            const d = Math.hypot(mouse.x - root.cx, mouse.y - root.cy)
            const tolerance = root.handleR + 10
            if (d < root.radius - tolerance || d > root.radius + tolerance) {
                mouse.accepted = false
                return
            }
            root.emitValue(valueAt(mouse.x, mouse.y))
        }
        onPositionChanged: (mouse) => {
            if (!pressed) return
            let v = valueAt(mouse.x, mouse.y)
            // Dragging through the bottom gap would flip 100 ↔ 0 in one step;
            // stick to the end the knob is already at instead.
            if (Math.abs(v - root.value) > 50)
                v = root.value > 50 ? 100 : 0
            root.emitValue(v)
        }
    }

    // Mouse wheel anywhere over the knob: 2 % per notch (120 units). Small
    // touchpad deltas accumulate until they add up to a whole percent.
    WheelHandler {
        property real pending: 0
        target: null
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            pending += event.angleDelta.y
            const steps = pending > 0 ? Math.floor(pending / 60) : Math.ceil(pending / 60)
            if (steps === 0) return
            pending -= steps * 60
            root.emitValue(root.value + steps)
        }
    }

    // ── Center disc: mute button + percentage ─────────────────────────────
    Rectangle {
        id: disc
        readonly property real diameter: 2 * (root.radius - root.stroke / 2 - root.stroke * 0.6)
        width:  diameter
        height: diameter
        radius: diameter / 2
        x: root.cx - diameter / 2
        y: root.cy - diameter / 2
        color: Theme.surfaceContainerHigh

        Column {
            anchors.centerIn: parent
            spacing: root.size * 0.02

            Item {
                id: muteButton
                readonly property real s: root.size * 0.25
                width:  s
                height: s
                anchors.horizontalCenter: parent.horizontalCenter

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Theme.p10
                    visible: muteArea.containsMouse
                }

                // Flat speaker icon, drawn rather than an emoji so it stays
                // monochrome and looks the same with every platform font.
                Canvas {
                    id: speaker
                    anchors.centerIn: parent
                    width:  parent.width * 0.62
                    height: width

                    property bool muted: root.muted
                    onMutedChanged: requestPaint()
                    onWidthChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        const s = width
                        const c = root.css(root.muted ? Theme.fgSurfaceVariant : Theme.fgSurface, 1)
                        ctx.fillStyle   = c
                        ctx.strokeStyle = c
                        ctx.lineCap     = "round"
                        ctx.lineWidth   = s * 0.08

                        // Body + cone
                        ctx.beginPath()
                        ctx.moveTo(s * 0.08, s * 0.36)
                        ctx.lineTo(s * 0.28, s * 0.36)
                        ctx.lineTo(s * 0.52, s * 0.14)
                        ctx.lineTo(s * 0.52, s * 0.86)
                        ctx.lineTo(s * 0.28, s * 0.64)
                        ctx.lineTo(s * 0.08, s * 0.64)
                        ctx.closePath()
                        ctx.fill()

                        if (root.muted) {
                            // ✕ where the waves were
                            const mx = s * 0.78, my = s * 0.5, a = s * 0.13
                            ctx.beginPath()
                            ctx.moveTo(mx - a, my - a); ctx.lineTo(mx + a, my + a)
                            ctx.moveTo(mx + a, my - a); ctx.lineTo(mx - a, my + a)
                            ctx.stroke()
                        } else {
                            // Two sound waves
                            for (const wr of [0.18, 0.34]) {
                                ctx.beginPath()
                                ctx.arc(s * 0.56, s * 0.5, s * wr, root.rad(-45), root.rad(45), false)
                                ctx.stroke()
                            }
                        }
                    }
                }

                MouseArea {
                    id: muteArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.muteToggled()
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.value + "%"
                font.family:    Theme.fontFamilyBody
                font.pixelSize: Math.round(root.size * 0.13)
                font.weight:    Font.Medium
                color: root.muted ? Theme.fgSurfaceVariant : Theme.fgSurface
            }
        }
    }
}
