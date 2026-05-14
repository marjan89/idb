# idb

iOS Device Bridge — unified CLI for iOS device control. Swift + ArgumentParser.

## Build

```bash
swift build -c release
```

If sandboxed: `nosandbox swift build -c release`. idb itself has no sandbox awareness — that's the caller's concern.

## Port defaults

WDA uses fixed ports, not offsets from the HTTP port:

| Service | Default port | Flag |
|---------|-------------|------|
| WDA HTTP | 8100 | per device in devices.toml |
| MJPEG | 9100 | `--mjpeg-port` on mirror |
| FastTouch | 9200 | `--touch-port` on mirror |

Do NOT compute ports as offsets (e.g. `wda_port + 1000`). These are independent services with fixed defaults. When multi-device support needs different MJPEG/FastTouch ports, add them to devices.toml.

## Design rules

- **No sandbox/Claude awareness** — idb is a general CLI. Skills wrap it, idb doesn't know about skills.
- **No nosandbox calls** — xcodebuild is called directly. If the caller is sandboxed, the caller wraps.
- **Defaults + parameters** — never hardcode. Every port, path, and ID should have a sensible default and a flag to override.
- **Exit codes** — 0 success, 1 error. Scripts chain on exit codes.
- **Device resolution** — `-d name` everywhere. Auto-select if one device. List available if ambiguous.

## Gotchas

- Swift tuples pad for alignment — use explicit `Data` packing for the FastTouch binary protocol.
- WDA's `/source` XML contains unescaped quotes in attribute values — NSXMLParser silently fails. Use line-based regex parsing.
- `xcrun devicectl` uses CoreDevice UUIDs, `devices.toml` uses UDID — these are different identifiers. Discover command shows CoreDevice IDs, not UDID.
- `xcodebuild build-for-testing` derived data path must match what `test-without-building` expects. Always use `--derived-data` consistently.
- `build-for-testing` MUST use `-destination id=<UDID>`, NOT `generic/platform=iOS`. The device-specific destination registers the UDID with Apple's provisioning system. Without it, the provisioning profile won't include the device and install fails with `0xe8008012`.
- xcodebuild (and codesign) calls `readpassphrase()` which opens `/dev/tty` directly, bypassing stdout/stderr redirects. Use `POSIX_SPAWN_SETSID` via `spawnDetached()` in Shell.swift to launch xcodebuild without a controlling terminal. Never use Foundation `Process` for xcodebuild — it leaks "Password:" prompts to the user's terminal.
- Xcode SDK version must be >= the device's iOS version. If `idb doctor` or `idb wda start` fails with DDI errors, update Xcode. Since Xcode 26, the iOS platform SDK must be downloaded separately via `xcodebuild -downloadPlatform iOS`.
- MJPEG caps at ~30 FPS (WDA screenshot-based).
- FastTouch requires the WDA fork with FBFastTouchServer. Without it, HTTP fallback works but at ~300ms per touch.
- Mirror drag: `dragThresholdRatio` and `MirrorCommandQueue` latest-wins interact — below ~1.5% threshold, micro-swipes flood the queue faster than FastTouch can drain, causing no visible movement. The 3% default is conservative but safe.
- `idb ui` times out on screens with MapKit — the `/source` endpoint does a full XCUI tree walk that hangs on map elements. Use `idb elements` instead, which queries via WDA `/elements` endpoint with class chain queries (no full-tree snapshot).

## File layout

```
Sources/idb/
├── IDB.swift                  # @main, subcommand registration
├── DeviceRegistry.swift       # reads devices.toml
├── WDAClient.swift            # WDA HTTP client
├── FastTouchClient.swift      # binary TCP client (port 9200)
├── Shell.swift                # shell() helper
├── Commands/
│   ├── Devices.swift          # list, status
│   ├── DevicesManage.swift    # add, remove, discover
│   ├── WDA.swift              # start, stop, build, log
│   ├── Touch.swift            # tap, swipe, type, button
│   ├── UI.swift               # UI tree dump (full /source snapshot)
│   ├── Elements.swift         # targeted element queries (class chain, predicate)
│   ├── Screenshot.swift
│   ├── App.swift              # launch, kill, active
│   ├── Syslog.swift
│   ├── Mirror.swift           # screen mirroring command
│   └── Doctor.swift           # system health check
└── Mirror/
    ├── MJPEGStream.swift      # MJPEG frame decoder
    ├── MirrorWindow.swift     # AppKit window + input handling
    └── MirrorWDABridge.swift  # bridges input to WDA/FastTouch
```
