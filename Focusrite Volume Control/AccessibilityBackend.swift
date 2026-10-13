//
//  AccessibilityBackend.swift
//  Focusrite Volume Control
//
//  Controls Focusrite Control 2 in-process through the Accessibility API (AXUIElement).
//  Element lookups are cached, so a key press touches only the controls it changes
//  instead of spawning osascript and routing through System Events.
//
//  The native Accessibility approach is ported from William Chan's version
//  (https://github.com/wc2184/focusrite-volume-control, MIT).
//

import Foundation
import Combine
import os.log
import AppKit
import ApplicationServices

/// Accessibility-based volume control backend
class AccessibilityBackend: VolumeBackend {

    // MARK: - Constants

    private let logger = Logger(subsystem: "solutions.enum.FocusriteVolumeControl", category: "AccessibilityBackend")

    // MARK: - State

    private var _state = VolumeState()
    private let stateSubject = CurrentValueSubject<VolumeState, Never>(VolumeState())
    private let fc2 = FC2Accessibility()

    /// Track if FC2 is verified ready (reset on errors)
    private var isFC2Verified = false

    /// Bumped on every playback write so a refresh that started earlier can't overwrite it
    private var playbackWriteVersion = 0

    var statePublisher: AnyPublisher<VolumeState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var state: VolumeState {
        _state
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Connection

    func connect() async -> VolumeResult {
        // Ensure FC2 is running and Direct tab is active (retry for startup timing)
        var lastError = "Unknown error"
        for attempt in 1...3 {
            do {
                try await ensureFC2Ready()
                isFC2Verified = true
                return await refresh()
            } catch {
                lastError = error.localizedDescription
                logger.info("⏳ Connect attempt \(attempt) failed: \(lastError, privacy: .public), retrying...")
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return .error(lastError)
    }

    func disconnect() {
        isFC2Verified = false
        fc2.invalidate()
        _state.isConnected = false
        _state.statusMessage = "Disconnected"
        stateSubject.send(_state)
    }

    func refresh() async -> VolumeResult {
        do {
            let writeVersion = playbackWriteVersion
            try await ensureReady()
            let snapshot = try await perform { try $0.readSnapshot() }

            // A refresh started before a key press must not replace the newer value
            if writeVersion == playbackWriteVersion {
                _state.playbackVolume = snapshot.playback.volume
                _state.playbackMuted = snapshot.playback.muted
            }
            _state.input1Volume = snapshot.input1.volume
            _state.input1Muted = snapshot.input1.muted
            _state.input2Volume = snapshot.input2.volume
            _state.input2Muted = snapshot.input2.muted
            _state.directMonitorEnabled = snapshot.directMonitorEnabled
            _state.isConnected = true
            _state.statusMessage = "Connected"
            stateSubject.send(_state)
            return .success
        } catch {
            _state.isConnected = false
            _state.statusMessage = error.localizedDescription
            stateSubject.send(_state)
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Playback Volume

    func getPlaybackVolume() async -> Result<Double, Error> {
        await read { try $0.level(of: .playback) }
    }

    func setPlaybackVolume(_ db: Double) async -> VolumeResult {
        await setPlaybackVolume(db, ensureDirectMonitor: false)
    }

    /// Checks Direct Monitor at write time, so a change made in FC2 can't leave
    /// the keyboard writing to a slider that is no longer audible
    func setPlaybackVolume(_ db: Double, ensureDirectMonitor: Bool) async -> VolumeResult {
        playbackWriteVersion += 1
        do {
            try await ensureReady()
            let actual = try await perform { fc2 -> Double in
                if ensureDirectMonitor { try fc2.setDirectMonitor(true) }
                return try fc2.setLevel(db, of: .playback)
            }
            _state.playbackVolume = actual
            _state.playbackMuted = false
            if ensureDirectMonitor { _state.directMonitorEnabled = true }
            stateSubject.send(_state)
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    func setPlaybackMuted(_ muted: Bool) async -> VolumeResult {
        await write { try $0.setMuted(muted, of: .playback) } apply: { $0.playbackMuted = muted }
    }

    // MARK: - Input 1

    func getInput1Volume() async -> Result<Double, Error> {
        await read { try $0.level(of: .input1) }
    }

    func setInput1Volume(_ db: Double) async -> VolumeResult {
        await write { _ = try $0.setLevel(db, of: .input1) } apply: { $0.input1Volume = db }
    }

    func setInput1Muted(_ muted: Bool) async -> VolumeResult {
        await write { try $0.setMuted(muted, of: .input1) } apply: { $0.input1Muted = muted }
    }

    // MARK: - Input 2

    func getInput2Volume() async -> Result<Double, Error> {
        await read { try $0.level(of: .input2) }
    }

    func setInput2Volume(_ db: Double) async -> VolumeResult {
        await write { _ = try $0.setLevel(db, of: .input2) } apply: { $0.input2Volume = db }
    }

    func setInput2Muted(_ muted: Bool) async -> VolumeResult {
        await write { try $0.setMuted(muted, of: .input2) } apply: { $0.input2Muted = muted }
    }

    // MARK: - Direct Monitor

    func setDirectMonitorEnabled(_ enabled: Bool) async -> VolumeResult {
        await write { try $0.setDirectMonitor(enabled) } apply: { $0.directMonitorEnabled = enabled }
    }

    // MARK: - FC2 Window Control

    /// Minimize FC2's window via AXMinimized, which doesn't steal focus from our popover
    func minimizeFC2IfNeeded() async {
        do {
            if try await perform({ try $0.minimizeWindowIfNeeded() }) {
                logger.info("📦 FC2: minimized")
            }
        } catch {
            logger.warning("⚠️ Failed to minimize FC2: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Readiness

    /// Ensure FC2 is ready before performing an action (fast path once verified)
    private func ensureReady() async throws {
        if isFC2Verified { return }
        logger.info("🔍 ensureReady: checking FC2 status...")
        try await ensureFC2Ready()
        isFC2Verified = true
    }

    /// Launch FC2 if needed, reopen its window if it was closed, and switch to the Direct tab
    private func ensureFC2Ready() async throws {
        guard AXIsProcessTrusted() else { throw VolumeBackendError.accessibilityNotGranted }

        if !FC2Accessibility.isRunning {
            logger.info("🚀 FC2 not running, launching...")
            try await openFC2(activate: false)
            // Wait for FC2 to start (up to 10 seconds), then give its UI a moment
            for i in 1...20 {
                try await Task.sleep(for: .milliseconds(500))
                if FC2Accessibility.isRunning {
                    logger.info("✅ FC2 launched after \(i * 500)ms")
                    try await Task.sleep(for: .milliseconds(1000))
                    break
                }
            }
            guard FC2Accessibility.isRunning else { throw VolumeBackendError.fc2NotRunning }
        }

        // A closed FC2 window disappears from the AX tree, while a minimized one stays
        // accessible, so reopen FC2 only when it has no window at all
        if try await perform({ $0.windowCount() }) == 0 {
            logger.info("🪟 FC2 has no window, reopening...")
            try await openFC2(activate: true)
            var foundWindow = false
            for _ in 1...15 {
                if try await perform({ $0.windowCount() }) > 0 {
                    foundWindow = true
                    break
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            if !foundWindow { throw VolumeBackendError.fc2WindowNotFound }
        }

        if try await perform({ $0.isOnDirectTab() }) {
            return
        }
        logger.info("🔀 Switching to Direct tab...")
        try await perform { try $0.switchToDirectTab() }
        // Give FC2 a moment to build the Direct tab's controls
        for _ in 1...10 {
            if try await perform({ $0.isOnDirectTab() }) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw VolumeBackendError.sliderNotFound("Playback 1 - 2")
    }

    /// Launch FC2, or send it a reopen event if it's already running (recreates a closed window)
    private func openFC2(activate: Bool) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: FC2Accessibility.bundleIdentifier) else {
            throw VolumeBackendError.fc2NotInstalled
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    // MARK: - Helpers

    /// Run AX work off the main actor, mapping AX failures to backend errors
    private func perform<T: Sendable>(_ body: @escaping @Sendable (FC2Accessibility) throws -> T) async throws -> T {
        do {
            return try await fc2.run(body)
        } catch let error as FC2AccessibilityError {
            // FC2 may have changed tabs or relaunched; re-check before the next action
            isFC2Verified = false
            throw backendError(for: error)
        }
    }

    private func backendError(for error: FC2AccessibilityError) -> VolumeBackendError {
        switch error {
        case .notRunning: return .fc2NotRunning
        case .windowNotFound: return .fc2WindowNotFound
        case .elementNotFound(let name): return .sliderNotFound(name)
        case .unexpectedValue(let detail): return .accessibilityError("Unexpected value: \(detail)")
        case .ax(let code): return .accessibilityError("AXError \(code)")
        }
    }

    private func read(_ body: @escaping @Sendable (FC2Accessibility) throws -> Double) async -> Result<Double, Error> {
        do {
            try await ensureReady()
            return .success(try await perform(body))
        } catch {
            return .failure(error)
        }
    }

    private func write(_ body: @escaping @Sendable (FC2Accessibility) throws -> Void,
                       apply: (inout VolumeState) -> Void) async -> VolumeResult {
        do {
            try await ensureReady()
            try await perform(body)
            apply(&_state)
            stateSubject.send(_state)
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

// MARK: - FC2 Accessibility Tree

/// Errors raised while walking FC2's accessibility tree
nonisolated enum FC2AccessibilityError: Error {
    case notRunning
    case windowNotFound
    case elementNotFound(String)
    case unexpectedValue(String)
    case ax(Int32)
}

/// FC2 channel strips on the Direct tab
nonisolated enum FC2Channel: String, Sendable {
    case playback = "Playback 1 - 2"
    case input1 = "Analogue 1"
    case input2 = "Analogue 2"
}

nonisolated struct FC2ChannelReading: Sendable {
    let volume: Double
    let muted: Bool
}

nonisolated struct FC2Snapshot: Sendable {
    let playback: FC2ChannelReading
    let input1: FC2ChannelReading
    let input2: FC2ChannelReading
    let directMonitorEnabled: Bool
}

/// Walks and caches FC2's accessibility tree on a private serial queue. Elements are
/// cached per FC2 process and dropped on any failure, so a relaunch or a tab change
/// costs one fresh lookup instead of breaking later key presses.
nonisolated final class FC2Accessibility {
    static let bundleIdentifier = "com.focusrite.control"
    private static let windowTitle = "Focusrite Control 2"

    private let queue = DispatchQueue(label: "solutions.enum.FocusriteVolumeControl.fc2-ax", qos: .userInitiated)

    // Accessed only on queue
    private var pid: pid_t = 0
    private var cache: [String: AXUIElement] = [:]

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    func invalidate() {
        queue.async { self.reset() }
    }

    func run<T: Sendable>(_ body: @escaping @Sendable (FC2Accessibility) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try body(self))
                } catch {
                    self.reset()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Operations (call only through run)

    func windowCount() -> Int {
        guard let app = try? application() else { return 0 }
        return (try? elements(kAXWindowsAttribute, of: app))?.count ?? 0
    }

    /// The Direct tab is active when its playback strip exists (works while minimized)
    func isOnDirectTab() -> Bool {
        (try? channelGroup(.playback)) != nil
    }

    func switchToDirectTab() throws {
        let navigation = try child(of: try window(), role: kAXGroupRole, named: "Navigation bar")
        let direct = try child(of: navigation, role: kAXCheckBoxRole, named: "Direct")
        try check(AXUIElementPerformAction(direct, kAXPressAction as CFString))
        // The Direct tab builds new elements; look them up fresh
        cache = cache.filter { $0.key == "window" }
    }

    func readSnapshot() throws -> FC2Snapshot {
        FC2Snapshot(
            playback: try reading(of: .playback),
            input1: try reading(of: .input1),
            input2: try reading(of: .input2),
            directMonitorEnabled: try boolValue(of: try directMonitor())
        )
    }

    func level(of channel: FC2Channel) throws -> Double {
        try parseDb(try stringValue(of: try slider(of: channel)))
    }

    /// Writes an integer dB value and returns what FC2 reports back
    func setLevel(_ db: Double, of channel: FC2Channel) throws -> Double {
        let slider = try slider(of: channel)
        try check(AXUIElementSetAttributeValue(slider, kAXValueAttribute as CFString,
                                               "\(Int(db.rounded()))dB" as CFString))
        let actual = try parseDb(try stringValue(of: slider))
        guard abs(actual - db.rounded()) < 0.5 else {
            throw FC2AccessibilityError.unexpectedValue("\(channel.rawValue) is \(actual) dB after writing \(db) dB")
        }
        return actual
    }

    func setMuted(_ muted: Bool, of channel: FC2Channel) throws {
        let mute = try muteCheckbox(of: channel)
        if try boolValue(of: mute) != muted {
            try check(AXUIElementPerformAction(mute, kAXPressAction as CFString))
        }
    }

    func setDirectMonitor(_ enabled: Bool) throws {
        let checkbox = try directMonitor()
        if try boolValue(of: checkbox) != enabled {
            try check(AXUIElementPerformAction(checkbox, kAXPressAction as CFString))
        }
    }

    /// Returns true if the window was minimized by this call
    func minimizeWindowIfNeeded() throws -> Bool {
        let window = try window()
        let minimized = try attribute(kAXMinimizedAttribute, of: window)
        if (minimized as? NSNumber)?.boolValue == true { return false }
        try check(AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue))
        return true
    }

    // MARK: Element lookup

    private func reset() {
        pid = 0
        cache = [:]
    }

    private func application() throws -> AXUIElement {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier).first else {
            throw FC2AccessibilityError.notRunning
        }
        if app.processIdentifier != pid {
            reset()
            pid = app.processIdentifier
        }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.5)
        return element
    }

    private func cached(_ key: String, _ lookup: () throws -> AXUIElement) throws -> AXUIElement {
        _ = try application()  // resets the cache if FC2 relaunched
        if let element = cache[key] { return element }
        let element = try lookup()
        cache[key] = element
        return element
    }

    private func window() throws -> AXUIElement {
        try cached("window") {
            let windows = try elements(kAXWindowsAttribute, of: try application())
            guard let window = windows.first(where: { name(of: $0) == Self.windowTitle }) ?? windows.first else {
                throw FC2AccessibilityError.windowNotFound
            }
            return window
        }
    }

    /// The Direct tab's channel strips live in the window's fifth group
    private func directGroup() throws -> AXUIElement {
        try cached("direct") {
            let groups = try elements(kAXChildrenAttribute, of: try window())
                .filter { role(of: $0) == kAXGroupRole }
            guard groups.count >= 5 else { throw FC2AccessibilityError.elementNotFound("Direct tab") }
            return groups[4]
        }
    }

    private func channelGroup(_ channel: FC2Channel) throws -> AXUIElement {
        try cached("group:\(channel.rawValue)") {
            try child(of: try directGroup(), role: kAXGroupRole, named: channel.rawValue)
        }
    }

    private func slider(of channel: FC2Channel) throws -> AXUIElement {
        try cached("slider:\(channel.rawValue)") {
            try child(of: try channelGroup(channel), role: kAXSliderRole, named: "Level")
        }
    }

    private func muteCheckbox(of channel: FC2Channel) throws -> AXUIElement {
        try cached("mute:\(channel.rawValue)") {
            try child(of: try channelGroup(channel), role: kAXCheckBoxRole, named: "Mute")
        }
    }

    /// Titled "Direct Monitor" in some FC2 versions and "Direct Monitor mode" in others (issue #1)
    private func directMonitor() throws -> AXUIElement {
        try cached("directMonitor") {
            let match = try elements(kAXChildrenAttribute, of: try window()).first {
                role(of: $0) == kAXCheckBoxRole && name(of: $0)?.hasPrefix("Direct Monitor") == true
            }
            guard let match else { throw FC2AccessibilityError.elementNotFound("Direct Monitor") }
            return match
        }
    }

    private func child(of parent: AXUIElement, role wanted: String, named title: String) throws -> AXUIElement {
        let match = try elements(kAXChildrenAttribute, of: parent).first {
            role(of: $0) == wanted && name(of: $0) == title
        }
        guard let match else { throw FC2AccessibilityError.elementNotFound(title) }
        return match
    }

    private func reading(of channel: FC2Channel) throws -> FC2ChannelReading {
        FC2ChannelReading(volume: try level(of: channel),
                          muted: try boolValue(of: try muteCheckbox(of: channel)))
    }

    // MARK: Attribute access

    private func elements(_ key: String, of element: AXUIElement) throws -> [AXUIElement] {
        guard let result = try attribute(key, of: element) as? [AXUIElement] else {
            throw FC2AccessibilityError.unexpectedValue(key)
        }
        return result
    }

    private func attribute(_ key: String, of element: AXUIElement) throws -> CFTypeRef {
        var value: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(element, key as CFString, &value))
        guard let value else { throw FC2AccessibilityError.unexpectedValue(key) }
        return value
    }

    private func stringValue(of element: AXUIElement) throws -> String {
        let value = try attribute(kAXValueAttribute, of: element)
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        throw FC2AccessibilityError.unexpectedValue("value of \(name(of: element) ?? "element")")
    }

    /// FC2 reports checkbox state as a number or as "true"/"false" depending on the control
    private func boolValue(of element: AXUIElement) throws -> Bool {
        let value = try attribute(kAXValueAttribute, of: element)
        if let number = value as? NSNumber { return number.boolValue }
        if let string = (value as? String)?.lowercased() { return string == "true" || string == "1" }
        throw FC2AccessibilityError.unexpectedValue("state of \(name(of: element) ?? "checkbox")")
    }

    private func role(of element: AXUIElement) -> String? {
        try? attribute(kAXRoleAttribute, of: element) as? String
    }

    private func name(of element: AXUIElement) -> String? {
        for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute] {
            if let value = try? attribute(key, of: element) as? String, !value.isEmpty { return value }
        }
        return nil
    }

    /// Parse "-6dB" or "0 dB" into a number; never default to 0 dB, which is full volume
    private func parseDb(_ text: String) throws -> Double {
        let numeric = text.replacingOccurrences(of: "dB", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(numeric) else { throw FC2AccessibilityError.unexpectedValue(text) }
        return value
    }

    private func check(_ error: AXError) throws {
        guard error == .success else { throw FC2AccessibilityError.ax(error.rawValue) }
    }
}
