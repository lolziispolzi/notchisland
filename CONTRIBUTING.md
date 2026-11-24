# Contributing to NotchIsland

Thanks for helping out.

## Getting started

1. Fork the repository and create a branch from `main`.
2. Build and run with `./scripts/run-app.sh`. Use `swift run` only for UI work that does not need location or calendar access.
3. Run `swift test` before you open a pull request.

## Guidelines

- **Keep idle cost near zero.** Do not add timers or polling that run while the island is closed. Prefer system notifications.
- **No new permissions without discussion.** Open an issue first if a feature needs Accessibility, Screen Recording, or similar.
- **No private frameworks** unless the feature degrades gracefully when the framework is missing or blocked.
- **Main actor:** UI state lives on the main actor. Do blocking work (AppleScript, file I/O) off the main thread.
- **Tests:** add unit tests for pure logic such as parsing, geometry and formatting.
- **Style:** follow the existing code. Four-space indentation, small types, comments that explain *why*.

## Adding a widget

1. Add a case to `WidgetKind` in `Core/AppSettings.swift`, with a title, short title and SF Symbol.
2. Add a service in `Sources/NotchIsland/Services/` if the widget needs data. Fetch on open, not on a timer.
3. Own the service in `NotchViewModel` and add it to the change-forwarding list there.
4. Add a view in `Sources/NotchIsland/Views/` and a case in `OpenView.content`.
5. If it needs settings, add a tab in `SettingsView`.
6. If it should show while closed, add a `ClosedActivity` case and give it a place in `closedActivity`'s priority order.
7. If it needs a new permission, add the usage string to `Packaging/Info.plist` and the entitlement to `Packaging/NotchIsland.entitlements`.

## Reporting bugs

Use the bug report template. Include your macOS version, Mac model, and whether your display has a notch.

## Code of conduct

Be kind and assume good intent. Harassment of any kind is not tolerated.
