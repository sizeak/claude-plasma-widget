import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support

PlasmoidItem {
    id: root

    // Usage data properties - bound by both representations
    property real fiveHourUsage: 0.0
    property real sevenDayUsage: 0.0
    property string fiveHourResetsAt: ""
    property string sevenDayResetsAt: ""
    property string errorMessage: ""

    // Internal state
    property string accessToken: ""

    switchWidth: Kirigami.Units.gridUnit * 10
    switchHeight: Kirigami.Units.gridUnit * 10

    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}

    toolTipMainText: i18n("Claude Code Usage")
    toolTipSubText: {
        if (errorMessage !== "") return errorMessage;
        var text = i18n("Session: %1%", Math.round(fiveHourUsage * 100));
        if (Plasmoid.configuration.showWeeklyUsage) {
            text += "\n" + i18n("Weekly: %1%", Math.round(sevenDayUsage * 100));
        }
        return text;
    }

    // Timer for periodic polling
    Timer {
        id: pollTimer
        interval: Plasmoid.configuration.refreshInterval * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchCredentials()
    }

    // Executable data source for reading credentials file
    Plasma5Support.DataSource {
        id: credentialsSource
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            credentialsSource.disconnectSource(source);

            var stdout = data["stdout"] || "";
            var stderr = data["stderr"] || "";
            var exitCode = data["exit code"] || 0;

            if (exitCode !== 0 || stdout.trim() === "") {
                root.errorMessage = i18n("Cannot read credentials file: %1",
                    stderr.trim() || "file not found or empty");
                return;
            }

            try {
                var creds = JSON.parse(stdout);
                // Find the first account with an accessToken
                var token = "";
                for (var key in creds) {
                    if (creds[key] && creds[key].accessToken) {
                        token = creds[key].accessToken;
                        break;
                    }
                }

                if (!token) {
                    root.errorMessage = i18n("No access token found in credentials file");
                    return;
                }

                root.accessToken = token;
                root.errorMessage = "";
                fetchUsage();
            } catch (e) {
                root.errorMessage = i18n("Invalid JSON in credentials file: %1", e.message);
            }
        }
    }

    function fetchCredentials() {
        var path = Plasmoid.configuration.credentialsPath;
        // Expand ~ and single-quote the rest to prevent shell injection
        var cmd;
        if (path.indexOf("~/") === 0) {
            var rest = path.substring(1).replace(/'/g, "'\\''");
            cmd = "cat \"$HOME\"'" + rest + "'";
        } else {
            cmd = "cat '" + path.replace(/'/g, "'\\''") + "'";
        }
        credentialsSource.connectSource(cmd);
    }

    function fetchUsage() {
        if (!root.accessToken) return;

        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.anthropic.com/api/oauth/usage");
        xhr.setRequestHeader("Authorization", "Bearer " + root.accessToken);
        xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20");

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;

            if (xhr.status === 200) {
                try {
                    var resp = JSON.parse(xhr.responseText);
                    // API returns "utilization" as a percentage (e.g. 71.0 = 71%)
                    var fh = resp.five_hour;
                    var sd = resp.seven_day;
                    root.fiveHourUsage = (fh && fh.utilization != null) ? fh.utilization / 100.0 : 0;
                    root.sevenDayUsage = (sd && sd.utilization != null) ? sd.utilization / 100.0 : 0;
                    root.fiveHourResetsAt = (fh && fh.resets_at) ? fh.resets_at : "";
                    root.sevenDayResetsAt = (sd && sd.resets_at) ? sd.resets_at : "";
                    root.errorMessage = "";
                } catch (e) {
                    root.errorMessage = i18n("Failed to parse usage response: %1", e.message);
                }
            } else if (xhr.status === 401) {
                // Token expired, clear it so next cycle re-reads credentials
                root.accessToken = "";
                root.errorMessage = i18n("Token expired, will retry on next poll");
            } else if (xhr.status === 0) {
                root.errorMessage = i18n("Network error: cannot reach API");
            } else {
                root.errorMessage = i18n("API error: HTTP %1", xhr.status);
            }
        };

        xhr.send();
    }

    function refresh() {
        fetchCredentials();
    }
}
