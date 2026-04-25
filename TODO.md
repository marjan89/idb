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
- [x] Native WDA lifecycle — `start`, `stop`, `status`, `serve`, `install-service`, `log`
- [x] launchd service generation and verified working
- [x] Zero dependency on wda-ctl.sh

## Gaps

### Architecture
- [ ] `~/.config/idb/config.json` for paths (WDA dir, registry, logs, derived data)
- [ ] Multi-device port conflicts — MJPEG/FastTouch are fixed at 9100/9200, need per-device config
- [ ] CoreDevice UUID vs UDID mismatch in `idb devices discover`

### App management
- [ ] `idb install <ipa/app> [-d device]`
- [ ] `idb app list [-d device]`

### Convenience
- [ ] `idb home [-d device]`
- [ ] `idb back [-d device]`
- [ ] `idb scroll <up|down|left|right> [-d device]`

### Config
- [ ] `idb config init/show/set`

### Doctor
- [ ] Check WDA cert expiry date, warn if < 2 days
- [ ] Validate config paths exist

### Cleanup
- [ ] Delete ios-mirror repo (absorbed into idb)
- [ ] Update wda-build skill to use idb
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
