# Token Dashboard GUI Design

> Date: 2026-06-18

## Overview

Extend token-dashboard from CLI-only to a macOS native GUI app with menu bar presence, control center widget, and credential management. The Python CLI remains as-is; the Swift GUI is a separate project under `gui/`.

## Architecture

```
TokenDashboard (macOS App, LSUIElement=true)
├── App Entry (SwiftUI App)
├── MenuBar
│   ├── Status Icon (usage percentage of most constrained provider)
│   └── Popover Panel (control-center-style, all providers)
├── ControlWidget Extension (macOS 26+, system Control Center)
├── Adapter Layer (Swift rewrite of Python adapters)
│   ├── AdapterProtocol
│   ├── OpenCodeAdapter
│   ├── MiniMaxAdapter
│   ├── MiMoAdapter
│   ├── XunfeiAdapter
│   └── DeepSeekAdapter
├── Models (mirrors Python models.py)
├── CredentialStore (Keychain)
├── ConfigStore (reads ~/.token-dashboard/config.yaml)
└── Settings Window (credential management, configuration)
```

### Key Decisions

- **LSUIElement=true**: No Dock icon, pure menu bar app
- **Popover panel**: Control-center-style rounded cards with blur background, ~320px wide
- **ControlWidget Extension**: Separate target, reads data via App Group SharedDefaults
- **No Python dependency**: All adapters rewritten in Swift
- **Config compatibility**: Reads same `~/.token-dashboard/` directory as CLI

## UI Design

### Menu Bar Icon

- Shows usage percentage of the most constrained provider (e.g. `72%`)
- Color-coded: green (<70%) → yellow (70-90%) → red (>90%)
- Falls back to `TD` text icon when no data

### Popover Panel

- Control-center aesthetic: rounded cards, vibrancy background, compact layout
- Each provider card contains:
  - Provider name + icon
  - Progress bars per window (5h / week / month)
  - Balance (if pay-as-you-go)
  - Reset time
  - Warning state (expired cookie, etc.)
- Footer: refresh button + last update timestamp + settings gear icon

### ControlWidget (macOS 26+)

- Compact usage card in system Control Center
- Shows most constrained provider percentage + progress bar
- Tap opens main app popover

### Settings Window

- Provider list with credential management (add API key / Cookie)
- Refresh interval configuration
- Alert threshold configuration

## Data Flow

```
Timer (60s default) → Adapter.fetch() → UsageSnapshot →
  ├→ Update MenuBar icon
  ├→ Update Popover content
  ├→ Write to App Group SharedDefaults (ControlWidget reads this)
  └→ Check alert thresholds → macOS Notification
```

ControlWidget never makes network calls; it reads from SharedDefaults.

## Credential Storage

| Type | Storage | Key Format |
|------|---------|------------|
| API Key | macOS Keychain | `com.token-dashboard.<provider>.<account>.api_key` |
| Cookie | macOS Keychain | `com.token-dashboard.<provider>.<account>.cookie` |
| Config | `~/.token-dashboard/config.yaml` | (same as CLI) |

### Migration

On first launch, detect `~/.token-dashboard/credentials.json` and prompt migration to Keychain.

## Models

Swift models mirror Python models.py:

- `ProviderId` enum: opencode, minimax, mimo, xunfei, deepseek
- `PlanKind` enum: coding_plan, token_plan, pay_as_you_go
- `QuotaUnit` enum: credits, tokens, requests, usd, cny, prompts, percent, unknown
- `WindowKind` enum: rolling_5h, rolling_week, rolling_month, calendar_month, calendar_day, fixed_period, balance
- `QuotaWindow` struct: kind, label, used, limit, remaining, unit, usedPct, resetAt, periodStart, periodEnd, raw
- `UsageSnapshot` struct: provider, fetchedAt, planName, planKind, balance, balanceUnit, windows, accountEmail, accountName, authMode, warnings, raw

## Tech Stack

- Swift 5.9+ / SwiftUI
- Minimum: macOS 13 (Ventura); ControlWidget requires macOS 26 (Tahoe)
- Dependencies (SPM):
  - SwiftSoup (HTML parsing for OpenCode adapter)
  - Yams (YAML parsing for config.yaml)
  - KeychainAccess (simplified Keychain access)

## Project Structure

```
gui/
├── TokenDashboard.xcodeproj
├── TokenDashboard/
│   ├── App.swift
│   ├── MenuBar/
│   │   ├── MenuBarView.swift
│   │   └── PopoverView.swift
│   ├── ControlWidget/
│   │   └── TokenDashboardControlWidget.swift
│   ├── Adapters/
│   │   ├── AdapterProtocol.swift
│   │   ├── OpenCodeAdapter.swift
│   │   ├── MiniMaxAdapter.swift
│   │   ├── MiMoAdapter.swift
│   │   ├── XunfeiAdapter.swift
│   │   └── DeepSeekAdapter.swift
│   ├── Models/
│   │   ├── ProviderId.swift
│   │   ├── QuotaWindow.swift
│   │   └── UsageSnapshot.swift
│   ├── Store/
│   │   ├── CredentialStore.swift
│   │   ├── ConfigStore.swift
│   │   └── SharedDefaults.swift
│   ├── Views/
│   │   ├── ProviderCardView.swift
│   │   ├── UsageBarView.swift
│   │   └── SettingsView.swift
│   └── Assets.xcassets/
├── TokenDashboardControlWidget/  (Extension target)
│   └── ControlWidgetEntry.swift
└── TokenDashboardTests/
```

## Relationship with Python CLI

- Both projects coexist in the same repo
- Python CLI under `src/td/` (unchanged)
- Swift GUI under `gui/`
- Shared config directory: `~/.token-dashboard/`
- JSON export format is compatible between both
- Swift GUI can import credentials from Python CLI's credentials.json on first run
