# YallaSlave

**Command executor for Yalla Lite — multi-account mic sync**  
**عبد يالا لايت — ينفذ أوامر رفع/خفض المايك للحسابات المتعددة**

## Overview

iOS tweak that receives Darwin commands from the **Master** and executes mic actions on Yalla Lite accounts. Each slave targets a specific account bundle (`yallalite`, `yallalite11`–`yallalite99`).

سليف ينفذ أوامر الماستر على حسابات يالا لايت. كل سليف يستهدف حساب معين.

## Commands Handled

| Command | Action |
|---------|--------|
| `lite.on` | enable |
| `lite.off` | disable |
| `cxx.face` | freeze mic display |
| `cxx.safe` | restore mic display |
| `run.on` | raise mic for slot |
| `run.off` | lower mic for slot |
| `mic.N` | select mic slot (1-10) |
| `speed.N` | set speed (50/25/10/5/1 ms) |
| `tap.*` | heartbeat (UUID-based every 3s) |

## Requirements

- iOS 14.0+
- Theos (for building)
- No jailbreak required

## Build

```bash
git clone <repo-url>
cd Slave
make package
```

## Bundle Filter

The slave injects into **10 account bundles**:

| Bundle ID | Slot |
|-----------|------|
| `com.yalla.yallalite` | 1 |
| `com.yalla.yallalite11` | 2 |
| `com.yalla.yallalite22` | 3 |
| `com.yalla.yallalite33` | 4 |
| `com.yalla.yallalite44` | 5 |
| `com.yalla.yallalite55` | 6 |
| `com.yalla.yallalite66` | 7 |
| `com.yalla.yallalite77` | 8 |
| `com.yalla.yallalite88` | 9 |
| `com.yalla.yallalite99` | 10 |

## Files

```
Slave/
├── Tweak.xm           # ~302 lines — full slave logic
├── Makefile            # Theos build config
├── YallaSlave.plist    # Bundle filter (10 accounts)
├── control             # Package metadata
├── README.md
└── .gitignore
```

## Credits

- **Author**: Abdulilah
- **Build system**: Theos
- **Method names & patterns**: Reverse-engineered from reference dylib via `strings`

---

> **Disclaimer**: For educational purposes only. Use at your own risk.
