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
| WDA HTTP | 8100 | per device in devices.json |
| MJPEG | 9100 | `--mjpeg-port` on mirror |
| FastTouch | 9200 | `--touch-port` on mirror |

Do NOT compute ports as offsets (e.g. `wda_port + 1000`). These are independent services with fixed defaults. When multi-device support needs different MJPEG/FastTouch ports, add them to devices.json.

## Design rules

- **No sandbox/Claude awareness** — idb is a general CLI. Skills wrap it, idb doesn't know about skills.
- **No nosandbox calls** — xcodebuild is called directly. If the caller is sandboxed, the caller wraps.
- **Defaults + parameters** — never hardcode. Every port, path, and ID should have a sensible default and a flag to override.
- **Exit codes** — 0 success, 1 error. Scripts chain on exit codes.
- **Device resolution** — `-d name` everywhere. Auto-select if one device. List available if ambiguous.

## Gotchas

- Swift tuples pad for alignment — use explicit `Data` packing for the FastTouch binary protocol.
- WDA's `/source` XML contains unescaped quotes in attribute values — NSXMLParser silently fails. Use line-based regex parsing.
- `xcrun devicectl` uses CoreDevice UUIDs, `devices.json` uses UDID — these are different identifiers. Discover command shows CoreDevice IDs, not UDID.
- `xcodebuild build-for-testing` derived data path must match what `test-without-building` expects. Always use `--derived-data` consistently.
- MJPEG caps at ~30 FPS (WDA screenshot-based).
- FastTouch requires the WDA fork with FBFastTouchServer. Without it, HTTP fallback works but at ~300ms per touch.

## File layout

```
Sources/idb/
├── IDB.swift                  # @main, subcommand registration
├── DeviceRegistry.swift       # reads devices.json
├── WDAClient.swift            # WDA HTTP client
├── FastTouchClient.swift      # binary TCP client (port 9200)
├── Shell.swift                # shell() helper
├── Commands/
│   ├── Devices.swift          # list, status
│   ├── DevicesManage.swift    # add, remove, discover
│   ├── WDA.swift              # start, stop, build, log
│   ├── Touch.swift            # tap, swipe, type, button
│   ├── UI.swift               # UI tree dump
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
