# YallaMaster

**Pure controller for Yalla Lite — multi-account mic management**  
**ماستر تحكم — إدارة فتحات المايك لحسابات يالا لايت المتعددة**

## Overview

iOS tweak that controls **10 microphone slots** across multiple Yalla Lite accounts. The master is a **pure controller** — never enters rooms, only sends commands via Darwin notifications to slave instances.

يتحكم في **10 فتحات ميكرفون** لحسابات يالا لايت المتعددة. الماستر **ما يدخل غرف** — بس يرسل أوامر للسلاف عبر Darwin notifications.

## Features

| Feature | Description |
|---------|-------------|
| **10 mic slots** | Single-select number picker (1-10) |
| **Pure controller** | No room entry — only broadcasts commands |
| **CXX freeze** | Freezes mic display via method swizzling |
| **LiTE counters** | Live connected/total slave count display |
| **Speed cycle** | 50ms → 25ms → 10ms → 5ms → 1ms |
| **Passcode lock** | Unlock with `515`, press-hold to show |
| **Crash protection** | Exception handlers + signal handlers + `@try/@catch` |
| **Background persistence** | Auto-restart on background task expiration |
| **Slave heartbeat** | UUID-based tap tracking with 12s timeout |
| **No jailbreak needed** | TrollStore / Sideloadly compatible |

## Requirements

- iOS 14.0+
- Theos (for building)
- No jailbreak required — works via TrollStore or sideloading

## Build

```bash
git clone <repo-url>
cd Master
make package
```

or build + install:

```bash
make package install
```

## Architecture

```
┌──────────────┐   Darwin Notification     ┌──────────────┐
│   Master     │  ──────────────────────▶  │   Slaves     │
│  (controller)│   mic.N / run.on/off      │  (accounts)  │
│              │   cxx.face/safe           │  1 — 10      │
│              │   speed.N                 │              │
│              │  ◀──── UUID tap ────────  │  (heartbeat) │
└──────────────┘                           └──────────────┘
```

Master targets `com.yalla.yallalite` only.

## Files

```
Master/
├── Tweak.xm           # ~985 lines — full master logic
├── Makefile            # Theos build config
├── YallaMaster.plist   # Bundle filter
├── control             # Package metadata
├── mockup_final.html   # Interactive UI prototype
├── README.md
└── .gitignore
```

## Credits

- **Author**: Abdulilah
- **Build system**: Theos
- **Method names & patterns**: Reverse-engineered from reference dylib via `strings`

---

> **Disclaimer**: For educational purposes only. Use at your own risk.
