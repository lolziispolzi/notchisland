import AppKit

/// A window "space" that macOS draws above ordinary desktops and full-screen apps.
///
/// macOS has no public API for this. Like other notch apps, this uses the private
/// SkyLight framework: it creates a space with an absolute level and moves windows
/// into it. The functions are looked up at run time, so if a macOS update removes
/// them, the spaces are nil and the features that use them quietly turn off.
/// Function signatures follow the ones used by open-source window managers (yabai).
@MainActor
final class SkyLightSpace {
    /// Above the lock screen (level 400): the lock-screen player.
    static let lockScreen: SkyLightSpace? = SkyLightSpace(level: 400)
    /// Above full-screen apps and their menu bar, below the lock screen (level 100): the island.
    static let aboveFullScreen: SkyLightSpace? = SkyLightSpace(level: 100)

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    // These two return nothing useful (their "results" read as leftover register values).
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Void
    private typealias SpaceAddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Void

    private let connection: Int32
    private let space: UInt64
    private let addWindows: SpaceAddWindows

    let level: Int32

    /// Results of the setup calls, for the diagnostics in Settings.
    let setupSummary: String

    private init?(level: Int32) {
        self.level = level
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_LAZY)
        else { return nil }

        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: type)
        }

        guard let mainConnection = load("SLSMainConnectionID", as: MainConnectionID.self),
              let create = load("SLSSpaceCreate", as: SpaceCreate.self),
              let setLevel = load("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
              let show = load("SLSShowSpaces", as: ShowSpaces.self),
              let add = load("SLSSpaceAddWindowsAndRemoveFromSpaces", as: SpaceAddWindows.self)
        else { return nil }

        connection = mainConnection()
        space = create(connection, 1, 0)
        guard space != 0 else { return nil }
        let levelResult = setLevel(connection, space, level)
        show(connection, [NSNumber(value: space)] as CFArray)
        addWindows = add
        setupSummary = "space \(space) at level \(level) (set-level result \(levelResult), 0 means success)"
    }

    /// Moves an on-screen window into this space.
    func add(_ window: NSWindow) {
        guard window.windowNumber > 0 else { return }
        addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
    }
}
