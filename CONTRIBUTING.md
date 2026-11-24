# Contributing to NotchIsland

Thanks for helping out.

## Getting started

1. Fork the repository and create a branch from `main`.
2. Build and run with `swift run`, or open `Package.swift` in Xcode.
3. Run `swift test` before you open a pull request.

## Guidelines

- **Keep idle cost near zero.** Do not add timers or polling that run while the island is closed. Prefer system notifications.
- **No new permissions without discussion.** Open an issue first if a feature needs Accessibility, Screen Recording, or similar.
- **No private frameworks** unless the feature degrades gracefully when the framework is missing or blocked.
- **Main actor:** UI state lives on the main actor. Do blocking work (AppleScript, file I/O) off the main thread.
- **Tests:** add unit tests for pure logic such as parsing, geometry and formatting.
- **Style:** follow the existing code. Four-space indentation, small types, comments that explain *why*.

## Adding a widget

1. Add a service in `Sources/NotchIsland/Services/` if the widget needs data.
2. Own the service in `NotchViewModel`.
3. Add a view in `Sources/NotchIsland/Views/` and place it in `HomeView`, or add a new `NotchTab`.
4. Add a toggle to `AppSettings` and `SettingsView`.
5. If the widget should show while closed, add a `ClosedActivity` case.

## Reporting bugs

Use the bug report template. Include your macOS version, Mac model, and whether your display has a notch.

## Code of conduct

Be kind and assume good intent. Harassment of any kind is not tolerated.
