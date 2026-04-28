# idb -- iOS Device Bridge

Unified CLI for iOS device control over WebDriverAgent (WDA). Built in Swift with ArgumentParser.

idb talks to WDA's HTTP API for touch, navigation, screenshots, UI inspection, and app management. An optional FastTouch binary protocol provides low-latency input for screen mirroring.

## Quick start

```bash
# Build
swift build -c release

# Set up config and point to your WDA checkout
idb config init
idb config set wdaDir /path/to/WebDriverAgent

# Enroll a device (auto-detects if one USB device connected)
idb devices add phone

# Build WDA and start it
idb wda build phone --start

# Verify everything works
idb doctor

# Use it
idb tap -d phone 200 400
idb screenshot -d phone screen.png
idb mirror phone
```

## Build

Requires macOS 13+ and Swift 5.9+.

```bash
swift build -c release
```

Optionally copy to PATH:

```bash
cp .build/release/idb /usr/local/bin/
```

## Setup

### 1. Initialize config

```bash
idb config init
```

Creates `~/.config/idb/config.json` with default paths, ports, and signing settings. View it with:

```bash
idb config show
```

Override individual values:

```bash
idb config set wdaDir /path/to/WebDriverAgent
idb config set registryPath ~/.config/idb/devices.json
```

### 2. Enroll devices

Add a device with its name, UDID, and WDA port:

```bash
idb devices add myphone --udid 00008101-XXXXXXXXXXXX --port 8100
```

Optional per-device MJPEG and FastTouch ports (defaults: 9100, 9200):

```bash
idb devices add myphone --udid 00008101-XXXX --port 8100 --mjpeg-port 9100 --fast-touch-port 9200
```

Auto-discover connected USB devices:

```bash
idb devices discover
```

List enrolled devices:

```bash
idb devices list
```

Remove a device:

```bash
idb devices remove myphone
```

### 3. Build and start WDA

Build WDA for the device:

```bash
idb wda build -d myphone
```

Start WDA:

```bash
idb wda start myphone
```

Check WDA status:

```bash
idb wda status myphone
```

Install as a launchd service for auto-start:

```bash
idb wda install-service myphone
```

## Commands

### Device management

| Command | Description |
|---------|-------------|
| `idb devices list` | List enrolled devices |
| `idb devices status` | Show WDA status for all devices |
| `idb devices add <name>` | Enroll a device |
| `idb devices remove <name>` | Remove a device |
| `idb devices discover` | Auto-discover USB devices |

### WDA lifecycle

| Command | Description |
|---------|-------------|
| `idb wda start <name>` | Start WDA on a device |
| `idb wda stop <name>` | Stop WDA |
| `idb wda status <name>` | Check if WDA is running |
| `idb wda build -d <name>` | Build WDA for the device |
| `idb wda serve <name>` | Run WDA in foreground |
| `idb wda install-service <name>` | Create launchd plist |
| `idb wda log <name>` | Tail WDA log output |

### Touch input

| Command | Description |
|---------|-------------|
| `idb tap <x> <y> [-d dev]` | Tap at WDA point coordinates |
| `idb swipe <x1> <y1> <x2> <y2> [-d dev]` | Swipe between coordinates |
| `idb type <text> [-d dev]` | Type text on the keyboard |
| `idb button <name> [-d dev]` | Press a hardware button (home, volumeUp, volumeDown) |

Touch commands try the FastTouch binary protocol first, falling back to WDA HTTP. Use `--http` to force HTTP.

### Convenience

| Command | Description |
|---------|-------------|
| `idb home [-d dev]` | Press the home button |
| `idb back [-d dev]` | Swipe from left edge (iOS back gesture) |
| `idb scroll <direction> [-d dev]` | Scroll up, down, left, or right |

Examples:

```bash
idb home
idb back -d myphone
idb scroll down
idb scroll left -d myphone
```

### Clipboard

| Command | Description |
|---------|-------------|
| `idb copy [-d dev]` | Copy device clipboard to Mac clipboard |
| `idb paste [-d dev] [--type]` | Paste Mac clipboard to device clipboard |

`--type` also types the pasted text into the focused field.

### UI inspection

```bash
idb ui [-d dev]           # Compact UI tree
idb ui --raw [-d dev]     # Raw WDA XML
```

### Screenshots

```bash
idb screenshot [-d dev] [output.png]
```

### App management

| Command | Description |
|---------|-------------|
| `idb app launch <bundleId> [-d dev]` | Launch an app |
| `idb app kill <bundleId> [-d dev]` | Terminate an app |
| `idb app active [-d dev]` | Show the foreground app |
| `idb app install <path> [-d dev]` | Install .ipa or .app |
| `idb app list [-d dev]` | List installed apps |

Examples:

```bash
idb app launch com.apple.Preferences
idb app kill com.apple.mobilesafari -d myphone
idb app active
idb app install ~/Downloads/MyApp.ipa -d myphone
idb app list
```

### Screen mirroring

```bash
idb mirror [device] [--scale 0.5] [--mjpeg-port 9100] [--touch-port 9200]
```

Opens an AppKit window with live MJPEG video and interactive input. Click to tap, drag to swipe, scroll wheel to scroll, Option+scroll to pinch zoom, ESC for home, Cmd+C to copy device clipboard to Mac, Cmd+V to paste Mac clipboard to device (and type it), Cmd+Q to quit.

### Device logs

```bash
idb syslog <device> [-p processName]
```

Tails device syslog via pymobiledevice3.

### System health

```bash
idb doctor
```

Checks tools, WDA status, signing, FastTouch, config paths, cert expiry, and disk space.

### Configuration

| Command | Description |
|---------|-------------|
| `idb config init` | Create config with defaults |
| `idb config show` | Print current config |
| `idb config set <key> <value>` | Update a config value |
| `idb config path` | Print config file path |

## WDA fork patch

idb works with stock WebDriverAgent but gets much better touch latency with the FBFastTouchServer fork. The patch is included as `wda-fork.patch`.

To apply it to a WDA checkout:

```bash
cd /path/to/WebDriverAgent
git apply /path/to/idb/wda-fork.patch
```

The fork adds a binary TCP server on port 9200 that accepts raw touch events, bypassing the HTTP overhead. Without it, touch input goes through WDA's HTTP API (~300ms per touch). With it, touch latency drops to under 10ms.

## Architecture

```
idb (Swift CLI)
 |
 +-- ArgumentParser          Command routing and flag parsing
 |
 +-- DeviceRegistry          devices.json read/write, device resolution
 |
 +-- IDBConfig               ~/.config/idb/config.json management
 |
 +-- WDAClient               WDA HTTP API (sessions, touch, buttons, screenshots)
 |
 +-- FastTouchClient          Binary TCP protocol for low-latency touch
 |
 +-- Commands/
 |    +-- Devices             list, status
 |    +-- DevicesManage       add, remove, discover
 |    +-- WDA                 start, stop, build, serve, install-service, log
 |    +-- Touch               tap, swipe, type, button (+ DeviceOption, helpers)
 |    +-- Convenience         home, back, scroll
 |    +-- Clipboard           copy, paste
 |    +-- UI                  UI tree dump
 |    +-- Screenshot          PNG capture
 |    +-- App                 launch, kill, active, install, list
 |    +-- Syslog              device log tailing
 |    +-- Mirror              MJPEG + interactive window
 |    +-- Doctor              system health checks
 |    +-- ConfigCmd           config init/show/set/path
 |
 +-- Mirror/
      +-- MJPEGStream         MJPEG frame decoder
      +-- MirrorWindow        AppKit NSWindow with input handling
      +-- MirrorWDABridge     Routes input to FastTouch or WDA HTTP
```

All commands that target a device accept `-d <name>`. If only one device is enrolled, it auto-selects. If multiple are enrolled and none specified, the command lists available devices and exits.

Port layout per device:

| Service | Default | Config key |
|---------|---------|------------|
| WDA HTTP | 8100 | `port` in devices.json |
| MJPEG | 9100 | `mjpeg_port` in devices.json |
| FastTouch | 9200 | `fast_touch_port` in devices.json |

Ports are independent fixed values, not computed as offsets from the WDA port.
