import AppKit

/// Puts windows above the lock screen.
///
/// macOS has no public API for this. Like other notch apps, this uses the private
/// SkyLight framework: it creates a window "space" with a level above the lock
/// screen and moves windows into it. The functions are looked up at run time, so if
/// a macOS update removes them, `shared` is nil and the feature quietly turns off.
/// Function signatures follow the ones used by open-source window managers (yabai).
@MainActor
final class LockScreenSpace {
    static let shared: LockScreenSpace? = LockScreenSpace()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> UInt64
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, UInt64, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias SpaceAddWindows = @convention(c) (Int32, UInt64, CFArray, Int32) -> Int32

    private let connection: Int32
    private let space: UInt64
    private let addWindows: SpaceAddWindows

    /// Results of the setup calls, for the diagnostics in Settings. 0 means success.
    let setupSummary: String
    /// Result of the most recent `add`. 0 means success.
    private(set) var lastAddResult: Int32?

    private init?() {
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
        // 100 sits above the lock screen.
        let levelResult = setLevel(connection, space, 100)
        let showResult = show(connection, [NSNumber(value: space)] as CFArray)
        addWindows = add
        setupSummary = "connection \(connection), space \(space), level \(levelResult), show \(showResult)"
    }

    /// Moves an on-screen window into the lock-screen space.
    func add(_ window: NSWindow) {
        guard window.windowNumber > 0 else { return }
        lastAddResult = addWindows(connection, space, [NSNumber(value: window.windowNumber)] as CFArray, 7)
    }
}
