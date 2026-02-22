import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.components as PlasmaComponents3

PlasmaExtras.Representation {
    id: full

    readonly property real fiveHourUsage: root.fiveHourUsage
    readonly property real sevenDayUsage: root.sevenDayUsage
    readonly property string fiveHourResets: root.fiveHourResetsAt
    readonly property string sevenDayResets: root.sevenDayResetsAt
    readonly property string errorMsg: root.errorMessage
    readonly property real fiveHourBurnRate: root.fiveHourBurnRate
    readonly property var usageHistory: root.usageHistory

    // Time range selector: 0=Session, 1=24h, 2=7d, 3=30d
    property int selectedRangeIndex: 0

    // Compute graph time window
    readonly property double graphTimeEnd: {
        if (selectedRangeIndex === 0 && full.fiveHourResets) {
            // Session: end at the session reset time
            var resetMs = new Date(full.fiveHourResets).getTime();
            if (!isNaN(resetMs) && resetMs > 0) return resetMs;
        }
        if (selectedRangeIndex === 2 && full.sevenDayResets) {
            // 7d: end at the weekly limit reset time
            var resetMs7 = new Date(full.sevenDayResets).getTime();
            if (!isNaN(resetMs7) && resetMs7 > 0) return resetMs7;
        }
        // 24h / 30d: end at now
        return Date.now();
    }
    readonly property double graphTimeStart: {
        var durations = [5 * 3600000, 24 * 3600000, 7 * 24 * 3600000, 30 * 24 * 3600000];
        return graphTimeEnd - durations[selectedRangeIndex];
    }

    // Filter history to the computed time window, never past now
    readonly property var filteredData: {
        var history = full.usageHistory;
        if (!history || history.length === 0) return [];
        var tStart = full.graphTimeStart;
        var now = Date.now();
        var result = [];
        for (var i = 0; i < history.length; i++) {
            if (history[i].t >= tStart && history[i].t <= now) {
                result.push({t: history[i].t, v: history[i].fh});
            }
        }
        return result;
    }

    implicitWidth: Kirigami.Units.gridUnit * 20
    implicitHeight: contentLayout.implicitHeight + Kirigami.Units.largeSpacing * 2
    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: Kirigami.Units.gridUnit * 14
    Layout.maximumWidth: Kirigami.Units.gridUnit * 30

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent

            Kirigami.Heading {
                text: i18n("Claude Code Usage")
                level: 3
                Layout.fillWidth: true
            }

            PlasmaComponents3.ToolButton {
                icon.name: "view-refresh"
                onClicked: root.refresh()
                PlasmaComponents3.ToolTip {
                    text: i18n("Refresh now")
                }
            }
        }
    }

    // Error state
    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: full.errorMsg !== ""
        iconName: "dialog-warning"
        text: i18n("Error")
        explanation: full.errorMsg
    }

    ColumnLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing
        visible: full.errorMsg === ""

        // 5-hour session section
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Kirigami.Heading {
                    text: i18n("Session (5 hour)")
                    level: 4
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: Math.round(full.fiveHourUsage * 100) + "%"
                    font.bold: true
                }
            }

            PlasmaComponents3.ProgressBar {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: full.fiveHourUsage
            }

            RowLayout {
                Layout.fillWidth: true
                QQC2.Label {
                    text: full.fiveHourResets
                        ? i18n("Resets at %1", formatResetTime(full.fiveHourResets))
                        : i18n("Reset time unknown")
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: Kirigami.Theme.disabledTextColor
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: full.fiveHourBurnRate < 0
                        ? i18n("Burn rate: calculating...")
                        : i18n("Burn rate: %1%/hr", full.fiveHourBurnRate.toFixed(1))
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: {
                        if (full.fiveHourBurnRate < 0) return Kirigami.Theme.disabledTextColor;
                        var remaining = 100 - full.fiveHourUsage * 100;
                        if (full.fiveHourBurnRate > 0 && remaining / full.fiveHourBurnRate < 1)
                            return Kirigami.Theme.negativeTextColor;
                        return Kirigami.Theme.disabledTextColor;
                    }
                }
            }
        }

        // Separator
        Kirigami.Separator {
            Layout.fillWidth: true
            visible: Plasmoid.configuration.showWeeklyUsage
        }

        // 7-day weekly section
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            visible: Plasmoid.configuration.showWeeklyUsage

            RowLayout {
                Layout.fillWidth: true
                Kirigami.Heading {
                    text: i18n("Weekly (7 day)")
                    level: 4
                    Layout.fillWidth: true
                }
                QQC2.Label {
                    text: Math.round(full.sevenDayUsage * 100) + "%"
                    font.bold: true
                }
            }

            PlasmaComponents3.ProgressBar {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: full.sevenDayUsage
            }

            QQC2.Label {
                text: full.sevenDayResets
                    ? i18n("Resets at %1", formatResetTime(full.sevenDayResets))
                    : i18n("Reset time unknown")
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Kirigami.Theme.disabledTextColor
            }
        }

        // Graph section
        Kirigami.Separator {
            Layout.fillWidth: true
            visible: Plasmoid.configuration.showGraphs
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Kirigami.Units.mediumSpacing
            visible: Plasmoid.configuration.showGraphs

            PlasmaComponents3.TabBar {
                id: rangeSelector
                Layout.fillWidth: true

                PlasmaComponents3.TabButton {
                    text: i18n("Session")
                    onClicked: full.selectedRangeIndex = 0
                }
                PlasmaComponents3.TabButton {
                    text: i18n("24h")
                    onClicked: full.selectedRangeIndex = 1
                }
                PlasmaComponents3.TabButton {
                    text: i18n("7d")
                    onClicked: full.selectedRangeIndex = 2
                }
                PlasmaComponents3.TabButton {
                    text: i18n("30d")
                    onClicked: full.selectedRangeIndex = 3
                }
            }

            UsageGraph {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Kirigami.Units.gridUnit * 6
                dataPoints: full.filteredData
                timeStart: full.graphTimeStart
                timeEnd: full.graphTimeEnd
                burnRate: (full.selectedRangeIndex <= 1) ? full.fiveHourBurnRate : -1
                lineColor: "#1d99f3"
            }
        }
    }

    function formatResetTime(isoString) {
        if (!isoString) return "";
        var d = new Date(isoString);
        if (isNaN(d.getTime())) return isoString;
        return Qt.formatDateTime(d, "hh:mm AP on MMM d");
    }
}
