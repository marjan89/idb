# idb — working TODO

## Architecture decisions

### nosandbox coupling
`idb wda build` currently hardcodes `~/.claude/bin/nosandbox` as a wrapper. This is wrong — nosandbox is a Claude sandbox escape mechanism, not an idb concern. idb should call `xcodebuild` directly. If the caller is sandboxed, the caller handles that (skill wraps with nosandbox, user doesn't need to).

**Action:** Remove nosandbox from idb. `idb wda build` calls xcodebuild directly. Skills that invoke idb from sandbox wrap the call: `nosandbox idb wda build phone`.

### Hardcoded paths
Current hardcoded paths that should be configurable:
- WDA source: `/Users/Shared/projects/device-tools/WebDriverAgent`
- Device registry: `~/.claude/daemons/wda/devices.json`
- WDA logs: `/tmp/wda-<name>.log`
- Derived data: `/tmp/wda-build-<name>`
- ios-mirror binary: `../ios-mirror/.build/release/ios-mirror`

**Action:** Add `~/.config/idb/config.json` for paths. Sensible defaults, overridable. `idb doctor` validates all paths exist.

### FastTouch port mapping
Currently `wda_port + 1100` (e.g. 8100 → 9200). Should be explicit in device registry or derived from WDA's actual FastTouch port.

**Action:** Add `fast_touch_port` to devices.json. Default to `wda_port + 1100` if not set.

## Gaps

### Device management
- [ ] `idb devices add <name> --udid <udid>` — interactive enrollment, auto-detect model/iOS version
- [ ] `idb devices remove <name>`
- [ ] `idb devices discover` — list connected devices not yet enrolled (via `xcrun devicectl`)

### WDA lifecycle
- [ ] `idb wda serve <device>` — heartbeat daemon in Swift (replaces wda-ctl.sh)
  - Auto-restart on crash
  - Health check loop
  - Proper signal handling
- [ ] launchd plist generator: `idb wda install-service <device>`
- [ ] Remove dependency on wda-ctl.sh entirely

### Build
- [ ] `idb wda build` calls xcodebuild directly (no nosandbox)
- [ ] `--derived-data <path>` flag (default: `/tmp/wda-build-<name>`)
- [ ] `--team <id>` flag (default from config or devices.json)
- [ ] `--clean` already exists

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
- [ ] Check disk space for derived data specifically
- [ ] Validate all paths from config exist

## Design principles

1. **idb is a general-purpose CLI** — no Claude/skill/sandbox awareness
2. **Skills are thin wrappers** — `ios-control` skill calls `idb tap`, `idb ui`, etc.
3. **Config over convention** — paths, ports, teams are configurable, not hardcoded
4. **Single device flag** — `-d <name>` everywhere, auto-select if only one enrolled
5. **Exit codes matter** — 0 success, 1 error, so scripts can chain
6. **Quiet by default** — output only the result, not progress. `--verbose` for debug.
