# idb — working TODO

## Done

- [x] nosandbox decoupled — `idb wda build` calls xcodebuild directly
- [x] `idb devices add/remove/discover`
- [x] `idb wda build` with `--wda-dir`, `--derived-data`, `--clean`, `--start`
- [x] `idb mirror` absorbed from ios-mirror — inline AppKit window, no subprocess
- [x] FastTouch/MJPEG ports: defaults (9200/9100) + `--touch-port`/`--mjpeg-port` flags
- [x] Doctor: signing check, WDA status with IP resolution, FastTouch check
- [x] UI parser handles WDA's broken XML (unescaped quotes)
- [x] WDA fork patch shipped as `wda-fork.patch`
- [x] CLAUDE.md with design rules and gotchas

## Architecture decisions

### Hardcoded paths
Current hardcoded paths that should be configurable:
- WDA source: `/Users/Shared/projects/device-tools/WebDriverAgent`
- Device registry: `~/.claude/daemons/wda/devices.json`
- WDA logs: `/tmp/wda-<name>.log`
- Derived data: `/tmp/wda-build-<name>`

**Action:** Add `~/.config/idb/config.json` for paths. Sensible defaults, overridable. `idb doctor` validates all paths exist.

### Multi-device port conflicts
MJPEG (9100) and FastTouch (9200) are fixed ports — can't run two WDA instances simultaneously without port conflicts. Need per-device port config in devices.json.

**Action:** Add optional `mjpeg_port` and `fast_touch_port` to devices.json. Default to 9100/9200.

### CoreDevice UUID vs UDID
`xcrun devicectl` uses CoreDevice UUIDs, `devices.json` uses UDID. `idb devices discover` can't match enrolled devices to connected ones.

**Action:** Store both identifiers in devices.json, or use pymobiledevice3 for UDID resolution.

## Gaps

### WDA lifecycle
- [ ] `idb wda serve <device>` — heartbeat daemon in Swift (replaces wda-ctl.sh)
  - Auto-restart on crash
  - Health check loop
  - Proper signal handling
- [ ] launchd plist generator: `idb wda install-service <device>`
- [ ] Remove dependency on wda-ctl.sh entirely
- [ ] `idb wda start` prompts for password — investigate keychain access

### App management
- [ ] `idb install <ipa/app> [-d device]`
- [ ] `idb app list [-d device]` — installed apps

### Convenience
- [ ] `idb home [-d device]` — alias for `idb button home`
- [ ] `idb back [-d device]` — left-edge swipe
- [ ] `idb scroll <up|down|left|right> [-d device]` — directional scroll

### Config
- [ ] `idb config init` — create `~/.config/idb/config.json` with defaults
- [ ] `idb config show` — print current config
- [ ] `idb config set <key> <value>`

### Doctor improvements
- [ ] Check WDA cert expiry date, warn if < 2 days
- [ ] Check Xcode command line tools version
- [ ] Validate all paths from config exist

### Cleanup
- [ ] Delete ios-mirror repo (absorbed into idb)
- [ ] Update wda-build skill to reference idb
- [ ] Update ios-control skill to use idb commands
- [ ] Update device-tools memory

## Design principles

1. **idb is a general-purpose CLI** — no Claude/skill/sandbox awareness
2. **Skills are thin wrappers** — `ios-control` skill calls `idb tap`, `idb ui`, etc.
3. **Config over convention** — paths, ports, teams are configurable, not hardcoded
4. **Defaults + parameters** — every port, path, and ID has a sensible default and a flag
5. **Single device flag** — `-d <name>` everywhere, auto-select if only one enrolled
6. **Exit codes matter** — 0 success, 1 error, so scripts can chain
7. **Quiet by default** — output only the result, not progress. `--verbose` for debug.
