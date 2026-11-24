<p align="center">
  <img src="Packaging/AppIcon.png" width="128" alt="NotchIsland icon">
</p>

<h1 align="center">NotchIsland</h1>

<p align="center">
  A Dynamic Island for the MacBook camera notch. Native Swift, free and open source.
</p>

---

Hover over the notch and it expands into a small panel with what's playing, the time, your battery and a file shelf. While closed, it can show live activities next to the notch.

## Features

- **Expands from the notch** with a spring animation, on hover or on click.
- **Now playing** for Apple Music and Spotify: artwork, title, artist, progress, and play/pause/next/previous.
- **Live activities while closed:** artwork and animated bars while music plays; a "Charging" pill when you plug in.
- **File shelf:** drag files onto the notch to park them, then drag them out anywhere later. AirDrop them in one click.
- **Clock and battery.**
- **Works without a notch:** draws a notch-shaped island on external displays and older Macs.
- **Light on resources:** no polling. Updates come from system notifications, and timers run only while the island is open.
- **Settings:** launch at login, display choice, hover delay, haptics, and per-widget toggles.

## Requirements

- macOS 14 Sonoma or later
- Apple silicon or Intel

## Install

1. Download the latest `NotchIsland-x.y.z.dmg` from the [Releases](../../releases) page.
2. Open it and drag **NotchIsland** to **Applications**.
3. Open NotchIsland. A capsule icon appears in the menu bar. There is no Dock icon.

> **Unsigned builds:** if a release was built without a Developer ID certificate, macOS blocks it on first launch.
> Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**. Only do this for builds you downloaded from this repository's Releases page.

## Permissions

| Permission | When it is asked | Why |
|---|---|---|
| Automation: Music / Spotify | First time a player is running | Read artwork and position, send play/pause/next/previous |

No other permissions are needed. Hover detection uses mouse-move events, which do not require Accessibility access.

## Privacy

NotchIsland has no analytics, no accounts and no network calls, with one exception: Spotify artwork is downloaded from Spotify's image server (`i.scdn.co`). Shelf items are stored as file paths in the app's preferences. Files are never copied or uploaded.

## Build from source

You need Xcode 16 or later.

```bash
git clone <this-repo-url>
cd NotchIsland
swift run
```

You can also open `Package.swift` in Xcode and press **Run**.

Run the tests:

```bash
swift test
```

Build a distributable `.app`, `.zip` and `.dmg` into `build/`:

```bash
./scripts/build-app.sh
```

The default build is ad-hoc signed. See [docs/RELEASING.md](docs/RELEASING.md) for Developer ID signing and notarization.

> **Note:** "Launch at login" only works from the built `NotchIsland.app`, not from `swift run`.

## How it works

| Piece | File |
|---|---|
| Entry point; accessory app with no Dock icon | `App/NotchIslandMain.swift` |
| Menu bar item, screen changes, settings window | `App/AppDelegate.swift`, `App/SettingsWindowController.swift` |
| Notch detection from `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` | `Core/NotchGeometry.swift` |
| Borderless, transparent `NSPanel` above the menu bar on every Space | `Core/NotchPanel.swift` |
| Global mouse monitors, open/close timing, click-through while closed | `Core/NotchController.swift` |
| Shared state, live-activity logic | `Core/NotchViewModel.swift` |
| Preferences | `Core/AppSettings.swift` |
| Now playing from Music/Spotify distributed notifications plus AppleScript | `Services/NowPlayingService.swift` |
| Battery from IOKit power-source notifications | `Services/BatteryService.swift` |
| File shelf | `Services/ShelfStore.swift` |
| Animated notch outline | `Views/NotchShape.swift` |
| SwiftUI views | `Views/` |

### Why not MediaRemote?

Most notch apps used the private `MediaRemote` framework to read now-playing info from any app. Since macOS 15.4, Apple blocks it for third-party apps. NotchIsland supports Music and Spotify through their public notifications and AppleScript dictionaries instead. Support for other players is a welcome contribution.

## Roadmap

- [ ] More players (browsers, VLC, IINA)
- [ ] Calendar widget (EventKit)
- [ ] Volume and brightness HUD replacement
- [ ] Per-display islands on multi-monitor setups
- [ ] Sparkle auto-updates
- [ ] Localization

## Contributing

Pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

[MIT](LICENSE)
