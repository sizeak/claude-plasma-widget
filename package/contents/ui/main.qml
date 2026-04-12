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
    property string refreshToken: ""
    property bool fetching: false
    property double tokenExpiresAt: 0
    property bool refreshingToken: false

    switchWidth: Kirigami.Units.gridUnit * 10
    switchHeight: Kirigami.Units.gridUnit * 10

    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}

    toolTipMainText: i18n("Claude Code Usage")
    toolTipSubText: {
        if (errorMessage !== "") return errorMessage;
        var text = i18n("Session: %1%", Math.round(fiveHourUsage * 100));
        if (fiveHourResetsAt) {
            text += " " + i18n("(resets at %1)", formatResetTime(fiveHourResetsAt));
        }
        if (Plasmoid.configuration.showWeeklyUsage) {
            text += "\n" + i18n("Weekly: %1%", Math.round(sevenDayUsage * 100));
            if (sevenDayResetsAt) {
                text += " " + i18n("(resets at %1)", formatResetTime(sevenDayResetsAt));
            }
        }
        return text;
    }

    function formatResetTime(isoString) {
        if (!isoString) return "";
        var d = new Date(isoString);
        if (isNaN(d.getTime())) return isoString;
        return Qt.formatDateTime(d, "hh:mm AP on MMM d");
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
                root.fetching = false;
                return;
            }

            try {
                var creds = JSON.parse(stdout);
                // Find the first account with an accessToken
                var token = "";
                var expiresAt = 0;
                for (var key in creds) {
                    if (creds[key] && creds[key].accessToken) {
                        token = creds[key].accessToken;
                        expiresAt = creds[key].expiresAt || 0;
                        break;
                    }
                }

                if (!token) {
                    root.errorMessage = i18n("No access token found in credentials file");
                    root.fetching = false;
                    return;
                }

                root.accessToken = token;
                root.tokenExpiresAt = expiresAt;
                root.errorMessage = "";

                // If token is expired, trigger a refresh via claude CLI
                if (root.tokenExpiresAt > 0 && Date.now() > root.tokenExpiresAt) {
                    if (!root.refreshingToken) {
                        triggerTokenRefresh();
                    } else {
                        // Already tried refreshing but token is still expired
                        root.errorMessage = i18n("Token expired, run claude to refresh");
                        root.fetching = false;
                        root.refreshingToken = false;
                    }
                    return;
                }

                root.refreshingToken = false;
                fetchUsage();
            } catch (e) {
                root.errorMessage = i18n("Invalid JSON in credentials file: %1", e.message);
                root.fetching = false;
            }
        }
    }

    // Executable data source for refreshing token via claude CLI
    Plasma5Support.DataSource {
        id: refreshSource
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            refreshSource.disconnectSource(source);
            // claude auth status triggers token refresh and rewrites credentials file
            // Now re-read the credentials file to pick up the new token
            fetchCredentials();
        }
    }

    function fetchCredentials() {
        if (fetching) return;
        fetching = true;

        var path = Plasmoid.configuration.credentialsPath;
        // Expand ~ and single-quote the rest to prevent shell injection
        var cmd;
        if (path === "~" || path.indexOf("~/") === 0) {
            var rest = path.substring(1).replace(/'/g, "'\\''");
            cmd = "timeout 5 cat \"$HOME\"'" + rest + "'";
        } else {
            cmd = "timeout 5 cat '" + path.replace(/'/g, "'\\''") + "'";
        }
        credentialsSource.connectSource(cmd);
    }

    function triggerTokenRefresh() {
        root.refreshingToken = true;
        root.errorMessage = i18n("Refreshing token...");
        // `claude -p ""` triggers the CLI's OAuth refresh during startup (which uses DPoP
        // internally) and writes the new token to the credentials file. An empty prompt
        // exits without making a model API call. timeout guards against hangs.
        refreshSource.connectSource("timeout 8 claude -p '' </dev/null");
    }

    function fetchUsage() {
        if (!root.accessToken) {
            root.fetching = false;
            return;
        }

        var xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.anthropic.com/api/oauth/usage");
        xhr.setRequestHeader("Authorization", "Bearer " + root.accessToken);
        xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20");
        xhr.timeout = 10000;

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
                root.fetching = false;
            } else if (xhr.status === 401) {
                // Token rejected by API — try refreshing via claude CLI
                root.accessToken = "";
                if (!root.refreshingToken) {
                    triggerTokenRefresh();
                } else {
                    root.errorMessage = i18n("Token expired, run claude to refresh");
                    root.fetching = false;
                    root.refreshingToken = false;
                }
            } else if (xhr.status === 0) {
                root.errorMessage = i18n("Network error: cannot reach API");
                root.fetching = false;
            } else {
                root.errorMessage = i18n("API error: HTTP %1", xhr.status);
                root.fetching = false;
            }
        };

        xhr.send();
    }

    function refresh() {
        root.refreshingToken = false;
        fetchCredentials();
    }
}
