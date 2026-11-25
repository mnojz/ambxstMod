pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.theme

Item {
    id: root

    required property var settings
    property bool captureAudio: false
    property bool sample: false
    property real pixelScale: 1
    readonly property var spectrum: LockscreenSpectrum.bands
    readonly property color graphColor: settings.visualizerUseShellColors ? Colors.primary : settings.visualizerColor
    readonly property int bandsPerChannel: LockscreenSpectrum.bandCount / 2
    readonly property var waveWeights: [20, 15, 6, 1]
    readonly property int barCount: 2 * Math.max(1, Math.floor(width / (16 * pixelScale)))
    readonly property string style: settings.visualizerStyle

    function sampleLevel(fraction) {
        const distance = Math.abs(2 * fraction - 1);
        const bass = distance * 5.5;
        const mids = (distance - 0.37) * 9;
        const treble = (distance - 0.74) * 13;
        return 0.77 * Math.exp(-bass * bass)
            + 0.45 * Math.exp(-mids * mids) + 0.24 * Math.exp(-treble * treble);
    }

    function levelAt(fraction) {
        if (sample)
            return sampleLevel(fraction);
        if (spectrum.length === 0)
            return 0;
        const index = fraction * (spectrum.length - 1);
        const left = Math.floor(index);
        return spectrum[left] + (spectrum[Math.min(left + 1, spectrum.length - 1)] - spectrum[left]) * (index - left);
    }

    function waveLevel(fraction) {
        if (sample)
            return sampleLevel(fraction);

        // A local Gaussian filter smooths the trace. Weighting higher levels
        // more strongly keeps distinct peaks visible after averaging.
        const radius = waveWeights.length - 1;
        let weightedLevel = 0;
        for (let offset = -radius; offset <= radius; offset++) {
            const position = Math.max(0, Math.min(1, fraction + offset / (bandsPerChannel - 1)));
            const level = levelAt(position);
            const squared = level * level;
            weightedLevel += waveWeights[Math.abs(offset)] * squared * squared;
        }
        const center = levelAt(fraction);
        return center * 0.22 + Math.sqrt(Math.sqrt(weightedLevel / 64)) * 0.78;
    }

    function barLevel(start, end) {
        if (sample || spectrum.length === 0)
            return levelAt((start + end) / 2);

        // Wider bar cells can span multiple FFT bands. Retain peaks between
        // the cell's edges as the widget is resized.
        const lastBand = spectrum.length - 1;
        let level = levelAt((start + end) / 2);
        for (let band = Math.ceil(start * lastBand); band <= Math.floor(end * lastBand); band++)
            level = Math.max(level, spectrum[band]);
        return level;
    }

    Loader {
        active: root.captureAudio && root.visible
        sourceComponent: Item {
            Component.onCompleted: LockscreenSpectrum.consumers++
            Component.onDestruction: LockscreenSpectrum.consumers--
        }
    }

    LockscreenWidgetShadow {
        active: root.settings.visualizerShadow
        foreground: graph
        renderScale: root.pixelScale
    }

    onSpectrumChanged: if (visible && !sample) graph.requestPaint()
    onGraphColorChanged: graph.requestPaint()
    onStyleChanged: graph.requestPaint()
    onPixelScaleChanged: graph.requestPaint()
    onSampleChanged: graph.requestPaint()

    Canvas {
        id: graph
        readonly property real waveOffset: 2 * root.pixelScale
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.height + (root.style === "wave" ? waveOffset : 0)
        antialiasing: true
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()

        function paintBars(ctx) {
            const centered = root.style === "mirror";
            const spacing = width / root.barCount;
            const thickness = Math.min(spacing, 4 * root.pixelScale);
            ctx.fillStyle = root.graphColor;
            for (let index = 0; index < root.barCount; index++) {
                const level = root.barLevel(index / root.barCount, (index + 1) / root.barCount);
                const barHeight = Math.max(Math.min(thickness, height), level * height);
                const corner = Math.min(thickness, barHeight) / 2;
                const top = centered ? (height - barHeight) / 2 : height - barHeight;
                ctx.beginPath();
                ctx.roundedRect((index + 0.5) * spacing - thickness / 2, top, thickness, barHeight, corner, corner);
                ctx.fill();
            }
        }

        function paintDots(ctx) {
            const horizontalSpacing = width / root.barCount;
            const verticalSpacing = Math.min(height, 8 * root.pixelScale);
            const rows = Math.max(1, Math.floor(height / verticalSpacing));
            const radius = Math.min(horizontalSpacing, verticalSpacing, 4.5 * root.pixelScale) / 2;
            ctx.fillStyle = root.graphColor;

            for (let index = 0; index < root.barCount; index++) {
                const x = (index + 0.5) * horizontalSpacing;
                const level = root.barLevel(index / root.barCount, (index + 1) / root.barCount) * rows;
                const litRows = Math.max(1, Math.ceil(level));
                for (let row = 0; row < litRows; row++) {
                    const opacity = Math.min(1, Math.max(0, level - row));
                    ctx.globalAlpha = row === 0 ? Math.max(0.22, opacity) : opacity;
                    ctx.beginPath();
                    ctx.arc(x, height - (row + 0.5) * verticalSpacing, radius, 0, 2 * Math.PI);
                    ctx.fill();
                }
            }
            ctx.globalAlpha = 1;
        }

        function paintRing(ctx) {
            const diameter = Math.min(width, height);
            const centerX = width / 2;
            const centerY = height / 2;
            const lineWidth = Math.min(diameter * 0.055, Math.max(1, 2 * root.pixelScale));
            const innerRadius = diameter * 0.34;
            const outerLimit = (diameter - lineWidth) / 2;

            if (root.spectrum.length > 0 || root.sample) {
                const pointCount = 128;
                const points = [];
                for (let index = 0; index < pointCount; index++) {
                    const angle = index / pointCount * 2 * Math.PI;
                    const horizontal = Math.sin(angle);
                    // Wrap each channel on its own half, with bass at the top and bottom.
                    const level = root.waveLevel(0.5 + horizontal * 0.5);
                    const radius = innerRadius + (outerLimit - innerRadius) * level;
                    points.push(Qt.point(centerX + radius * horizontal, centerY - radius * Math.cos(angle)));
                }

                const first = points[0];
                const last = points[pointCount - 1];
                ctx.beginPath();
                ctx.moveTo((last.x + first.x) / 2, (last.y + first.y) / 2);
                for (let index = 0; index < pointCount; index++) {
                    const current = points[index];
                    const next = points[(index + 1) % pointCount];
                    ctx.quadraticCurveTo(current.x, current.y, (current.x + next.x) / 2, (current.y + next.y) / 2);
                }
                ctx.closePath();

                const gradient = ctx.createRadialGradient(centerX, centerY, innerRadius,
                                                         centerX, centerY, outerLimit);
                gradient.addColorStop(0, Qt.alpha(root.graphColor, 0));
                gradient.addColorStop(1, root.graphColor);
                ctx.fillStyle = gradient;
                ctx.fill();

                ctx.strokeStyle = root.graphColor;
                ctx.lineWidth = lineWidth;
                ctx.stroke();
            }

            ctx.beginPath();
            ctx.arc(centerX, centerY, innerRadius, 0, 2 * Math.PI);
            ctx.strokeStyle = Qt.alpha(root.graphColor, 0.55);
            ctx.lineWidth = lineWidth;
            ctx.stroke();
        }

        function paintWave(ctx) {
            const lineWidth = Math.min(root.height, Math.max(1, 2 * root.pixelScale));
            const baseline = root.height - lineWidth / 2 + waveOffset;
            // Keep a control point at the center of the stereo spectrum.
            const segments = 64;
            const step = width / segments;
            const amplitude = Math.max(0, root.height - lineWidth);
            let lastY = baseline - root.waveLevel(0) * amplitude;

            ctx.beginPath();
            ctx.moveTo(0, lastY);
            for (let index = 1; index <= segments; index++) {
                const y = baseline - root.waveLevel(index / segments) * amplitude;
                ctx.quadraticCurveTo((index - 1) * step, lastY, (index - 0.5) * step, (lastY + y) / 2);
                lastY = y;
            }
            ctx.quadraticCurveTo(width, lastY, width, lastY);
            ctx.strokeStyle = root.graphColor;
            ctx.lineWidth = lineWidth;
            ctx.stroke();

            if (baseline > waveOffset) {
                const gradient = ctx.createLinearGradient(0, waveOffset, 0, baseline);
                gradient.addColorStop(0, root.graphColor);
                gradient.addColorStop(1, Qt.alpha(root.graphColor, 0));
                ctx.lineTo(width, baseline);
                ctx.lineTo(0, baseline);
                ctx.closePath();
                ctx.fillStyle = gradient;
                ctx.fill();
            }
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (width <= 0 || height <= 0)
                return;
            switch (root.style) {
            case "wave":
                paintWave(ctx);
                break;
            case "ring":
                paintRing(ctx);
                break;
            case "dots":
                paintDots(ctx);
                break;
            default:
                paintBars(ctx);
            }
        }
    }
}
