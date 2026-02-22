# Claude Code Usage — KDE Plasma 6 Widget

A panel widget that shows your Claude Code token usage at a glance. Sits alongside your clock, network widget, etc.

![Compact view shows two progress bars: 5-hour session and 7-day weekly usage]

## Features

- **Compact panel view** — stacked progress bars with color-coded thresholds (green/yellow/red)
- **Click to expand** — detailed percentages, reset times, and a refresh button
- **Burn rate** — shows usage velocity (%/hr) with warnings when you're on pace to hit the limit
- **Usage graphs** — interactive historical charts with Session / 24h / 7d / 30d time ranges, threshold lines, gap detection, and burn rate projection
- **Auto-refreshing** — polls the Anthropic usage API on a configurable interval (default 10 min)
- **Configurable** — toggle weekly bar, percentage text overlay, usage graphs, refresh interval, credentials path
- **Theme-aware** — uses Kirigami/Plasma theme colors

## Requirements

- KDE Plasma 6
- Claude Code with OAuth login (`~/.claude/.credentials.json` must exist)

## Install

```bash
git clone <repo-url>
cd claude-plasma-widget
bash install.sh
```

Then right-click your panel → **Add Widgets** → search **Claude Code Usage** → drag to panel.

## Update

```bash
bash install.sh
rm -rf ~/.cache/plasmashell/qmlcache
plasmashell --replace &>/dev/null & disown
```

## Uninstall

```bash
kpackagetool6 -t Plasma/Applet -r com.github.claude-code-usage
```

## Configuration

Right-click the widget → **Configure**:

| Setting | Default | Description |
|---------|---------|-------------|
| Show weekly usage | On | Show/hide the 7-day bar |
| Show percentage | Off | Overlay % text on bars |
| Show usage graphs | On | Display historical usage charts in the expanded view |
| Refresh interval | 600s | Seconds between API polls (15–600) |
| Credentials file | `~/.claude/.credentials.json` | Path to Claude Code credentials |
