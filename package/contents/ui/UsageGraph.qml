import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    id: graph

    property var dataPoints: []   // array of {t: timestamp_ms, v: 0-100+}
    property color lineColor: "#1d99f3"  // KDE Breeze blue
    property double timeStart: Date.now() - 5 * 3600000  // x-axis left edge (ms)
    property double timeEnd: Date.now()                    // x-axis right edge (ms)
    property real burnRate: -1   // %/hr, negative = not yet calculated

    implicitHeight: Kirigami.Units.gridUnit * 8
    Layout.fillWidth: true

    // --- Computed chart properties ---

    readonly property int sampleCount: Math.max(2, Math.round(chartArea.width / 3))

    readonly property real _rawMax: {
        var max = 100;
        var pts = graph.dataPoints;
        if (pts) {
            for (var i = 0; i < pts.length; i++) {
                if (pts[i].t >= graph.timeStart && pts[i].t <= graph.timeEnd) {
                    if (pts[i].v > max) max = pts[i].v;
                }
            }
        }
        if (graph.burnRate >= 0 && pts && pts.length > 0) {
            var lastPt = pts[pts.length - 1];
            var hoursToEnd = (graph.timeEnd - lastPt.t) / 3600000;
            if (hoursToEnd > 0.01) {
                var proj = Math.max(0, lastPt.v + graph.burnRate * hoursToEnd);
                if (proj > max) max = proj;
            }
        }
        return max;
    }

    readonly property int gridStep: {
        if (_rawMax <= 125) return 25;
        if (_rawMax <= 300) return 50;
        return 100;
    }
    readonly property real yMax: Math.max(100, Math.ceil(_rawMax / gridStep) * gridStep)
    readonly property int yAxisLabelCount: yMax / gridStep + 1

    // Resample data to evenly-spaced bins; null marks gaps (no data)
    readonly property var sampledValues: {
        var pts = graph.dataPoints;
        if (!pts || pts.length === 0 || graph.sampleCount < 2) return [];

        var tMin = graph.timeStart;
        var tMax = graph.timeEnd;
        var tRange = tMax - tMin;
        if (tRange <= 0) return [];

        var n = graph.sampleCount;
        var binWidth = tRange / n;
        var lastDataT = pts[pts.length - 1].t;

        // Stop at the earlier of last data point or now (don't draw into future)
        var cutoffT = Math.min(lastDataT, Date.now());
        var lastBin = Math.min(n - 1, Math.floor((cutoffT - tMin) / binWidth));
        if (lastBin < 0) return [];

        // Gap threshold: 3x median interval, minimum 20 minutes
        var gapThreshold = 20 * 60 * 1000;
        if (pts.length >= 3) {
            var intervals = [];
            var step = Math.max(1, Math.floor(pts.length / 50));
            for (var ii = step; ii < pts.length; ii += step) {
                intervals.push(pts[ii].t - pts[ii - step].t);
            }
            intervals.sort(function(a, b) { return a - b; });
            gapThreshold = Math.max(gapThreshold, intervals[Math.floor(intervals.length / 2)] * 3);
        }

        // Build a lookup: for each bin, find the nearest preceding data point
        // and null out bins where that point is too far away (gap detection)
        var result = [];
        var pIdx = 0;
        for (var i = 0; i <= lastBin; i++) {
            var binTime = tMin + (i + 0.5) * binWidth;
            while (pIdx < pts.length - 1 && pts[pIdx + 1].t <= binTime) {
                pIdx++;
            }
            if (pts[pIdx].t > binTime) {
                result.push(null);  // no data yet for this time
            } else if (binTime - pts[pIdx].t > gapThreshold) {
                result.push(null);  // data point too far in the past — gap
            } else {
                result.push(Math.max(0, pts[pIdx].v));
            }
        }

        return result;
    }

    // --- Layout ---

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Kirigami.Units.smallSpacing

            // Y-axis labels
            Item {
                id: yAxisLabels
                Layout.fillHeight: true
                implicitWidth: yAxisMetrics.width + Kirigami.Units.smallSpacing

                TextMetrics {
                    id: yAxisMetrics
                    font: Kirigami.Theme.smallFont
                    text: graph.yMax + "%"
                }

                Repeater {
                    model: graph.yAxisLabelCount
                    QQC2.Label {
                        required property int index
                        anchors.right: parent.right
                        anchors.rightMargin: Kirigami.Units.smallSpacing
                        y: chartArea.height * (1 - index * graph.gridStep / graph.yMax) - height / 2
                        font: Kirigami.Theme.smallFont
                        text: (index * graph.gridStep) + "%"
                        color: Kirigami.Theme.disabledTextColor
                    }
                }
            }

            // Chart area
            Item {
                id: chartArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                Canvas {
                    id: canvas
                    anchors.fill: parent

                    onPaint: {
                        var ctx = getContext("2d");
                        var w = width;
                        var h = height;
                        ctx.clearRect(0, 0, w, h);
                        if (w <= 0 || h <= 0) return;

                        var sc = Math.max(1, graph.sampleCount - 1);

                        // Grid lines (KDE style: subtle blend of bg and text)
                        var gridColor = Kirigami.ColorUtils.linearInterpolation(
                            Kirigami.Theme.backgroundColor, Kirigami.Theme.textColor, 0.2);
                        ctx.strokeStyle = gridColor;
                        ctx.lineWidth = 1;
                        for (var g = graph.gridStep; g < graph.yMax; g += graph.gridStep) {
                            var gy = h * (1 - g / graph.yMax);
                            ctx.beginPath();
                            ctx.moveTo(0, gy);
                            ctx.lineTo(w, gy);
                            ctx.stroke();
                        }

                        // Split sampled data into segments (break at nulls = gaps)
                        var vals = graph.sampledValues;
                        var segments = [];
                        var curSeg = [];
                        if (vals) {
                            for (var si = 0; si < vals.length; si++) {
                                if (vals[si] !== null && vals[si] !== undefined) {
                                    curSeg.push({i: si, v: vals[si]});
                                } else {
                                    if (curSeg.length > 0) {
                                        segments.push(curSeg);
                                        curSeg = [];
                                    }
                                }
                            }
                            if (curSeg.length > 0) segments.push(curSeg);
                        }

                        // Draw each contiguous segment (skip tiny fragments)
                        var fillColor = Qt.rgba(graph.lineColor.r, graph.lineColor.g,
                                                 graph.lineColor.b, 0.20);
                        for (var seg = 0; seg < segments.length; seg++) {
                            var s = segments[seg];
                            if (s.length < 3) continue;

                            // Filled area
                            ctx.beginPath();
                            ctx.moveTo((s[0].i / sc) * w, h);
                            for (var fp = 0; fp < s.length; fp++) {
                                ctx.lineTo((s[fp].i / sc) * w, h * (1 - s[fp].v / graph.yMax));
                            }
                            ctx.lineTo((s[s.length - 1].i / sc) * w, h);
                            ctx.closePath();
                            ctx.fillStyle = fillColor;
                            ctx.fill();

                            // Line
                            ctx.beginPath();
                            for (var lp = 0; lp < s.length; lp++) {
                                var lx = (s[lp].i / sc) * w;
                                var ly = h * (1 - s[lp].v / graph.yMax);
                                if (lp === 0) ctx.moveTo(lx, ly);
                                else ctx.lineTo(lx, ly);
                            }
                            ctx.strokeStyle = graph.lineColor;
                            ctx.lineWidth = 1;
                            ctx.stroke();
                        }

                        // Threshold at 75% (neutral)
                        var y75 = h * (1 - 75 / graph.yMax);
                        drawDashedLine(ctx, 0, y75, w, y75,
                            Kirigami.Theme.neutralTextColor, 0.7, [4, 4]);

                        // Threshold at 90% (negative/warning)
                        var y90 = h * (1 - 90 / graph.yMax);
                        drawDashedLine(ctx, 0, y90, w, y90,
                            Kirigami.Theme.negativeTextColor, 0.7, [4, 4]);

                        // Projection — find last non-null value
                        if (graph.burnRate >= 0 && vals && vals.length > 0) {
                            var lastBinIdx = -1;
                            var lastVal = 0;
                            for (var pi = vals.length - 1; pi >= 0; pi--) {
                                if (vals[pi] !== null) {
                                    lastBinIdx = pi;
                                    lastVal = vals[pi];
                                    break;
                                }
                            }
                            if (lastBinIdx >= 0) {
                                var startX = (lastBinIdx / sc) * w;
                                var startY = h * (1 - lastVal / graph.yMax);
                                var hoursToEnd = (graph.timeEnd - Date.now()) / 3600000;
                                if (hoursToEnd > 0.01) {
                                    var projV = Math.max(0, lastVal + graph.burnRate * hoursToEnd);
                                    var endY = h * (1 - Math.min(projV, graph.yMax) / graph.yMax);
                                    drawDashedLine(ctx, startX, startY, w, endY,
                                        graph.lineColor, 0.5, [6, 4]);
                                }
                            }
                        }
                    }

                    function drawDashedLine(ctx, x1, y1, x2, y2, color, alpha, pattern) {
                        ctx.save();
                        ctx.strokeStyle = Qt.rgba(color.r, color.g, color.b, alpha);
                        ctx.lineWidth = 1.5;
                        ctx.setLineDash(pattern);
                        ctx.beginPath();
                        ctx.moveTo(x1, y1);
                        ctx.lineTo(x2, y2);
                        ctx.stroke();
                        ctx.setLineDash([]);
                        ctx.restore();
                    }
                }
            }
        }

    }

    // Repaint when data, size, or theme changes
    onDataPointsChanged: canvas.requestPaint()
    onSampledValuesChanged: canvas.requestPaint()
    onTimeStartChanged: canvas.requestPaint()
    onTimeEndChanged: canvas.requestPaint()
    onBurnRateChanged: canvas.requestPaint()
    onYMaxChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Connections {
        target: Kirigami.Theme
        function onTextColorChanged() { canvas.requestPaint(); }
    }
}
