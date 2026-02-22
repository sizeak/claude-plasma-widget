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

    // Burn rate (percentage per hour, for display)
    property real fiveHourBurnRate: -1  // -1 = not yet calculated
    property real sevenDayBurnRate: -1

    // Unified history for graphs — array of {t: timestamp_ms, fh: 0-100, sd: 0-100}
    property var usageHistory: []

    // Internal state
    property string accessToken: ""
    property bool fetching: false
    property double tokenExpiresAt: 0

    // Internal burn rate tracking
    property real _prevFiveHourUsage: -1
    property double _prevFiveHourTime: 0
    property real _prevSevenDayUsage: -1
    property double _prevSevenDayTime: 0
    property real _smoothedFiveHourRate: 0
    property real _smoothedSevenDayRate: 0

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
                fetchUsage();
            } catch (e) {
                root.errorMessage = i18n("Invalid JSON in credentials file: %1", e.message);
                root.fetching = false;
            }
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

    function fetchUsage() {
        if (!root.accessToken) {
            root.fetching = false;
            return;
        }

        // Token expired — re-read credentials immediately for a fresh token
        if (root.tokenExpiresAt > 0 && Date.now() > root.tokenExpiresAt) {
            root.accessToken = "";
            root.fetching = false;
            fetchCredentials();
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
                    root.recordDataPoint();
                    // On fresh install, schedule a quick follow-up for burn rate
                    if (root.fiveHourBurnRate < 0 && !bootstrapTimer.running) {
                        bootstrapTimer.start();
                    }
                } catch (e) {
                    root.errorMessage = i18n("Failed to parse usage response: %1", e.message);
                }
            } else if (xhr.status === 401) {
                // Token rejected — re-read credentials for a fresh token
                root.accessToken = "";
                root.fetching = false;
                fetchCredentials();
                return;
            } else if (xhr.status === 0) {
                root.errorMessage = i18n("Network error: cannot reach API");
            } else {
                root.errorMessage = i18n("API error: HTTP %1", xhr.status);
            }
            root.fetching = false;
        };

        xhr.send();
    }

    function refresh() {
        fetchCredentials();
    }

    // One-shot timer for quick follow-up poll on fresh installs
    Timer {
        id: bootstrapTimer
        interval: 60000
        running: false
        repeat: false
        onTriggered: {
            if (root.fiveHourBurnRate < 0) fetchCredentials();
        }
    }

    // Data source for reading history file
    Plasma5Support.DataSource {
        id: historyReadSource
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            historyReadSource.disconnectSource(source);
            var stdout = data["stdout"] || "";
            try {
                var parsed = (stdout.trim() !== "") ? JSON.parse(stdout) : [];
                root._applyLoadedHistory(parsed);
            } catch (e) {
                root._applyLoadedHistory([]);
            }
        }
    }

    // Data source for writing history file (fire-and-forget)
    Plasma5Support.DataSource {
        id: historyWriteSource
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            historyWriteSource.disconnectSource(source);
        }
    }

    function loadHistory() {
        var cmd = "timeout 5 cat \"$HOME\"'/.local/share/claude-code-usage/history.json' 2>/dev/null || echo '[]'";
        historyReadSource.connectSource(cmd);
    }

    function _applyLoadedHistory(hist) {
        root.usageHistory = hist;
        // Compute burn rate from recent history so it's available immediately
        if (hist.length >= 2) {
            var last = hist[hist.length - 1];
            root._prevFiveHourUsage = last.fh;
            root._prevFiveHourTime = last.t;
            root._prevSevenDayUsage = last.sd;
            root._prevSevenDayTime = last.t;

            // Average rate over last few data points
            var lookback = Math.min(5, hist.length);
            var first = hist[hist.length - lookback];
            var dtHours = (last.t - first.t) / 3600000;
            if (dtHours > 0) {
                var fhRate = Math.max(0, (last.fh - first.fh) / dtHours);
                root._smoothedFiveHourRate = fhRate;
                root.fiveHourBurnRate = fhRate;
            }
        } else if (hist.length === 1) {
            var pt = hist[0];
            root._prevFiveHourUsage = pt.fh;
            root._prevFiveHourTime = pt.t;
            root._prevSevenDayUsage = pt.sd;
            root._prevSevenDayTime = pt.t;
        }
    }

    function persistHistory() {
        // JSON uses only double quotes, so single-quote wrapping is safe.
        // Atomic write: write to .tmp then mv to prevent corruption.
        var json = JSON.stringify(root.usageHistory);
        var cmd = "mkdir -p \"$HOME\"'/.local/share/claude-code-usage' && " +
                  "printf '%s' '" + json + "' > \"$HOME\"'/.local/share/claude-code-usage/history.json.tmp' && " +
                  "mv \"$HOME\"'/.local/share/claude-code-usage/history.json.tmp' \"$HOME\"'/.local/share/claude-code-usage/history.json'";
        historyWriteSource.connectSource(cmd);
    }

    function recordDataPoint() {
        var now = Date.now();
        var fhPct = root.fiveHourUsage * 100;
        var sdPct = root.sevenDayUsage * 100;

        // --- Five hour burn rate ---
        if (root._prevFiveHourUsage >= 0 && root._prevFiveHourTime > 0) {
            var dtH = (now - root._prevFiveHourTime) / 3600000; // hours
            if (dtH > 0) {
                var rawFh = (fhPct - root._prevFiveHourUsage) / dtH;
                if (rawFh < 0) rawFh = 0; // clamp on reset
                root._smoothedFiveHourRate = 0.3 * rawFh + 0.7 * root._smoothedFiveHourRate;
                root.fiveHourBurnRate = Math.max(0, root._smoothedFiveHourRate);
            }
        }
        root._prevFiveHourUsage = fhPct;
        root._prevFiveHourTime = now;

        // --- Seven day burn rate ---
        if (root._prevSevenDayUsage >= 0 && root._prevSevenDayTime > 0) {
            var dtH2 = (now - root._prevSevenDayTime) / 3600000;
            if (dtH2 > 0) {
                var rawSd = (sdPct - root._prevSevenDayUsage) / dtH2;
                if (rawSd < 0) rawSd = 0;
                root._smoothedSevenDayRate = 0.3 * rawSd + 0.7 * root._smoothedSevenDayRate;
                root.sevenDayBurnRate = Math.max(0, root._smoothedSevenDayRate);
            }
        }
        root._prevSevenDayUsage = sdPct;
        root._prevSevenDayTime = now;

        // --- Append to unified history ---
        var arr = root.usageHistory.slice();
        arr.push({t: now, fh: fhPct, sd: sdPct});
        if (arr.length > 5000) arr = arr.slice(arr.length - 5000);
        root.usageHistory = arr;

        persistHistory();
    }

    Component.onCompleted: loadHistory()
}
