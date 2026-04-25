# idb — working TODO

## Done

- [x] nosandbox decoupled — `idb wda build` calls xcodebuild directly
- [x] `idb devices add/remove/discover`
- [x] `idb wda build` with `--wda-dir`, `--derived-data`, `--clean`, `--start`
- [x] `idb mirror` absorbed from ios-mirror — inline AppKit window, no subprocess
- [x] Per-device `mjpeg_port`/`fast_touch_port` in devices.json, falls back to global config
- [x] Doctor: signing, WDA status, FastTouch, disk space
- [x] UI parser handles WDA's broken XML
- [x] WDA fork patch shipped as `wda-fork.patch`
- [x] CLAUDE.md with design rules and gotchas
- [x] Native WDA lifecycle — `start`, `stop`, `status`, `serve`, `install-service`, `log`
- [x] launchd service generation — verified working
- [x] Zero dependency on wda-ctl.sh
- [x] `idb config init/show/set/path` — `~/.config/idb/config.json`
- [x] All hardcoded paths moved to config
- [x] Multi-device port conflicts resolved — per-device ports in devices.json
- [x] Centralized `DeviceRegistry.save()`

## Gaps

### Device discovery
- [x] CoreDevice UUID vs UDID mismatch in `idb devices discover`

### App management
- [x] `idb install <ipa/app> [-d device]`
- [x] `idb app list [-d device]`

### Convenience
- [x] `idb home [-d device]`
- [x] `idb back [-d device]`
- [x] `idb scroll <up|down|left|right> [-d device]`

### Doctor
- [x] Check WDA cert expiry date, warn if < 2 days
- [x] Validate config paths exist

### Cleanup
- [x] Delete ios-mirror repo (absorbed into idb)
- [x] Update wda-build skill to use idb
- [x] Update ios-control skill to use idb commands
- [x] Update device-tools memory
- [x] idb README

## Design principles

1. **idb is a general-purpose CLI** — no Claude/skill/sandbox awareness
2. **Skills are thin wrappers** — `ios-control` skill calls `idb tap`, `idb ui`, etc.
3. **Config over convention** — paths, ports, teams are configurable, not hardcoded
4. **Defaults + parameters** — every port, path, and ID has a sensible default and a flag
5. **Single device flag** — `-d <name>` everywhere, auto-select if only one enrolled
6. **Exit codes matter** — 0 success, 1 error, so scripts can chain
7. **Quiet by default** — output only the result, not progress. `--verbose` for debug.
