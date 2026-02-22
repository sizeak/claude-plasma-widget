# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

KDE Plasma 6 panel widget that displays Claude Code token usage (5-hour session and 7-day weekly) as color-coded progress bars. Reads OAuth credentials from `~/.claude/.credentials.json` and polls the Anthropic usage API.

**Plugin ID:** `com.github.claude-code-usage`

## Install / Update / Uninstall

```bash
# Install or update (handles both cases):
bash install.sh

# After install, clear QML cache and restart plasmashell to pick up changes:
rm -rf ~/.cache/plasmashell/qmlcache && plasmashell --replace &>/dev/null & disown

# Uninstall:
kpackagetool6 -t Plasma/Applet -r com.github.claude-code-usage
```

Installed location: `~/.local/share/plasma/plasmoids/com.github.claude-code-usage/`

There are no build steps or tests. QML is interpreted at runtime by plasmashell.

## Architecture

**main.qml** is the root `PlasmoidItem`. It owns all state (usage values, error message, access token) and handles the data pipeline:
- Timer fires → `fetchCredentials()` reads the JSON file via `Plasma5Support.DataSource` (executable engine running `cat`) → parses out the first `accessToken` → `fetchUsage()` does an `XMLHttpRequest` GET to `https://api.anthropic.com/api/oauth/usage` → updates properties → QML bindings propagate to both representations.

**CompactRepresentation.qml** (panel inline) and **FullRepresentation.qml** (click popup) both read state from `root.*` properties defined in main.qml. They don't fetch data themselves.

**UsageBar.qml** is a reusable progress bar component used by both representations. It takes a 0.0–1.0 `value` and applies threshold colors from `Kirigami.Theme` (green < 75%, yellow 75–90%, red >= 90%).

**Config system:** `config/main.xml` defines the schema (KConfigXT), `config/config.qml` registers the settings tab, `ui/configGeneral.qml` is the settings page UI. Settings use `cfg_` property aliases for automatic Plasma config binding.

**Usage history** is stored in `~/.local/share/claude-code-usage/history.json` (not in KConfig) to avoid risking widget config corruption. Written atomically via temp file + `mv`.

## API Details

- **Endpoint:** `GET https://api.anthropic.com/api/oauth/usage`
- **Auth:** `Authorization: Bearer {token}` + `anthropic-beta: oauth-2025-04-20`
- **Response fields:** `five_hour.utilization` and `seven_day.utilization` are percentages (0–100), divided by 100 in main.qml for the 0.0–1.0 bars. Reset times are in `*.resets_at` as ISO datetimes.

## Credentials File Format

`~/.claude/.credentials.json` has structure: `{ "claudeAiOauth": { "accessToken": "...", "refreshToken": "...", ... } }`. The code iterates top-level keys and picks the first object with an `accessToken` field.
