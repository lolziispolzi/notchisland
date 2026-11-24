# NotchIsland

A Dynamic Island–style overlay for the MacBook camera notch.

## Requirements

- macOS 14 or later
- Xcode 16 or later (or the Xcode Command Line Tools)

## Run

```bash
cd NotchIsland
swift run
```

Or open `Package.swift` in Xcode and press Run.

Hover the notch to expand the island. Move the mouse away to collapse it.
Quit from the capsule icon in the menu bar.

On Macs without a notch, a fake notch is drawn at the top center of the main screen.

## Layout

| File | Purpose |
|---|---|
| `main.swift` | Entry point; runs as an accessory app (no Dock icon) |
| `AppDelegate.swift` | Menu bar item, screen-change handling |
| `NotchGeometry.swift` | Notch detection and all rects |
| `NotchPanel.swift` | Transparent borderless panel above the menu bar |
| `NotchController.swift` | Mouse tracking, open/close logic |
| `NotchViewModel.swift` | Shared state |
| `NotchShape.swift` | Animated notch outline |
| `NotchView.swift` | Island view and expanded content |
| `Widgets.swift` | Clock and battery widgets |
