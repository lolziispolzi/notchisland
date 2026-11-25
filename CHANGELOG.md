# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
- Buttons and tabs in the island needed the window to be active and ignored clicks.
- The island showed below the menu bar instead of in the notch.
- The app could start without running its setup in release builds.

### Added
- Notes widget: sticky notes with colors and pinning, saved locally.
- Lyrics: synced lyrics from LRCLIB in the Music tab, the current line under the closed notch, and desktop lyrics in three styles with album-color backgrounds. Timing offset in Settings.
- Lock-screen status readout in Settings, and a second way of placing windows above the lock screen.
- `scripts/install-latest.sh` installs the newest CI build without the "Not Opened" warning.
- `scripts/setup-local-signing.sh` so rebuilt copies keep their macOS permissions.
- Stars lyrics style, edge glow that follows the notch, and an experimental lock-screen player with lyrics.
- Header buttons beside the notch work even when macOS gives the click to the menu bar.
- Weather widget: current location or a searched city, current conditions and 5-day forecast, °C or °F.
- Calendar widget: upcoming events, add events with an alert from the notch, delete from the context menu.
- Heads-up next to the notch before your next event.
- Sports widget: pick a league and favorite team for live scores, results and upcoming games. Live score shows next to the notch.
- Drop zone: copy or move files to Desktop, Downloads, iCloud Drive, Dropbox, Google Drive, OneDrive or custom folders; share menu; copy to clipboard.
- Now playing: shuffle, repeat, drag to seek, click artwork to open the player.
- Customize bar in the island to show, hide and reorder widgets and change the island size.
- Island sizes: compact, regular, large.
- Settings window with tabs for General, Layout, Weather, Sports, Calendar and Drop Zone.
- `scripts/run-app.sh` to build and launch the app bundle locally.

### Changed
- The file shelf is now the Drop Zone widget.
- The home tab is now the Now Playing widget.

## [0.1.0]

### Added
- Island that expands from the notch on hover or click.
- Now playing for Apple Music and Spotify with artwork and playback controls.
- Live activities while closed: now playing and charging.
- File shelf with drag in, drag out and AirDrop.
- Clock and battery widgets.
- Fake notch on displays without one.
- Settings window: launch at login, display choice, hover behavior, haptics, widget toggles.
- Build script producing a signed `.app`, `.zip` and `.dmg`, with optional notarization.
- CI and tag-based release workflows.
