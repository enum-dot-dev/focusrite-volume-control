//
//  AppleScriptBackend.swift
//  Focusrite Volume Control
//
//  Controls Focusrite Control 2 via osascript (command-line AppleScript).
//  Uses the same approach as the working Node.js volume-control.js script.
//

import Foundation
import Combine
import os.log

/// AppleScript-based volume control backend using osascript subprocess
class AppleScriptBackend: VolumeBackend {

    // MARK: - Constants

    private let fc2Process = "Focusrite Control 2"
    private let logger = Logger(subsystem: "solutions.enum.FocusriteVolumeControl", category: "AppleScriptBackend")

    /// The Direct Monitor checkbox is titled "Direct Monitor" in some FC2 versions and
    /// "Direct Monitor mode" in others, so match on the prefix (issue #1)
    private var directMonitorCheckbox: String {
        "first checkbox of window \"\(fc2Process)\" whose name starts with \"Direct Monitor\""
    }

    // MARK: - State

    private var _state = VolumeState()
    private let stateSubject = CurrentValueSubject<VolumeState, Never>(VolumeState())

    /// Track if FC2 is verified ready (reset on errors)
    private var isFC2Verified = false

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
        var lastError: String = "Unknown error"
        for attempt in 1...3 {
            let result = await ensureDirectTab()
            if case .success = result {
                return await refresh()
            }
            if case .error(let msg) = result {
                lastError = msg
                logger.info("⏳ Connect attempt \(attempt) failed: \(msg, privacy: .public), retrying...")
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return .error(lastError)
    }

    func disconnect() {
        isFC2Verified = false
        _state.isConnected = false
        _state.statusMessage = "Disconnected"
        stateSubject.send(_state)
    }

    func refresh() async -> VolumeResult {
        do {
            let playbackVol = try await readSliderValue(channel: "Playback 1 - 2")
            let playbackMute = try await readMuteState(channel: "Playback 1 - 2")
            let input1Vol = try await readSliderValue(channel: "Analogue 1")
            let input1Mute = try await readMuteState(channel: "Analogue 1")
            let input2Vol = try await readSliderValue(channel: "Analogue 2")
            let input2Mute = try await readMuteState(channel: "Analogue 2")
            let directMon = try await readDirectMonitorState()

            _state.playbackVolume = playbackVol
            _state.playbackMuted = playbackMute
            _state.input1Volume = input1Vol
            _state.input1Muted = input1Mute
            _state.input2Volume = input2Vol
            _state.input2Muted = input2Mute
            _state.directMonitorEnabled = directMon
            _state.isConnected = true
            _state.statusMessage = "Connected"
            stateSubject.send(_state)
            return .success
        } catch {
            isFC2Verified = false  // Reset on error to force re-check next time
            _state.isConnected = false
            _state.statusMessage = error.localizedDescription
            stateSubject.send(_state)
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Playback Volume

    func getPlaybackVolume() async -> Result<Double, Error> {
        do {
            let vol = try await readSliderValue(channel: "Playback 1 - 2")
            return .success(vol)
        } catch {
            isFC2Verified = false
            return .failure(error)
        }
    }

    func setPlaybackVolume(_ db: Double) async -> VolumeResult {
        do {
            try await setSliderValue(channel: "Playback 1 - 2", db: db)
            _state.playbackVolume = db
            _state.playbackMuted = false
            stateSubject.send(_state)
            return .success
        } catch {
            isFC2Verified = false
            return .error(error.localizedDescription)
        }
    }

    func setPlaybackMuted(_ muted: Bool) async -> VolumeResult {
        do {
            try await setMuteState(channel: "Playback 1 - 2", muted: muted)
            _state.playbackMuted = muted
            stateSubject.send(_state)
            return .success
        } catch {
            isFC2Verified = false
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Input 1

    func getInput1Volume() async -> Result<Double, Error> {
        do {
            let vol = try await readSliderValue(channel: "Analogue 1")
            return .success(vol)
        } catch {
            isFC2Verified = false
            return .failure(error)
        }
    }

    func setInput1Volume(_ db: Double) async -> VolumeResult {
        do {
            try await setSliderValue(channel: "Analogue 1", db: db)
            _state.input1Volume = db
            stateSubject.send(_state)
            return .success
        } catch {
            isFC2Verified = false
            return .error(error.localizedDescription)
        }
    }

    func setInput1Muted(_ muted: Bool) async -> VolumeResult {
        do {
            try await setMuteState(channel: "Analogue 1", muted: muted)
            _state.input1Muted = muted
            stateSubject.send(_state)
            return .success
        } catch {
            isFC2Verified = false
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Input 2

    func getInput2Volume() async -> Result<Double, Error> {
        do {
            let vol = try await readSliderValue(channel: "Analogue 2")
            return .success(vol)
        } catch {
            isFC2Verified = false
            return .failure(error)
        }
    }

    func setInput2Volume(_ db: Double) async -> VolumeResult {
        do {
            try await setSliderValue(channel: "Analogue 2", db: db)
            _state.input2Volume = db
            stateSubject.send(_state)
            return .success
        } catch {
            isFC2Verified = false
            return .error(error.localizedDescription)
        }
    }

    func setInput2Muted(_ muted: Bool) async -> VolumeResult {
        do {
            try await setMuteState(channel: "Analogue 2", muted: muted)
            _state.input2Muted = muted
            stateSubject.send(_state)
            return .success
        } catch {
            isFC2Verified = false
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Direct Monitor

    func setDirectMonitorEnabled(_ enabled: Bool) async -> VolumeResult {
        do {
            try await setDirectMonitor(enabled: enabled)
            _state.directMonitorEnabled = enabled
            stateSubject.send(_state)
            return .success
        } catch {
            isFC2Verified = false
            return .error(error.localizedDescription)
        }
    }

    // MARK: - FC2 Window Control

    /// Minimize FC2 window to Dock (if not already minimized)
    /// Uses AXMinimized attribute for both detection and minimization (no focus stealing)
    func minimizeFC2IfNeeded() async {
        // Check and set AXMinimized attribute directly - avoids stealing focus from our popover
        let checkAndMinimizeScript = """
        tell application "System Events"
            tell process "\(fc2Process)"
                if (count of windows) = 0 then
                    return "no_windows"
                end if
                set isMin to value of attribute "AXMinimized" of window 1
                if isMin then
                    return "already_minimized"
                end if
                -- Minimize by setting AXMinimized directly (doesn't steal focus)
                set value of attribute "AXMinimized" of window 1 to true
                return "minimized"
            end tell
        end tell
        """

        do {
            let result = try await runOsascript(checkAndMinimizeScript)
            if result == "minimized" {
                logger.info("📦 FC2: \(result, privacy: .public)")
            }
        } catch {
            logger.warning("⚠️ Failed to minimize FC2: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - AppleScript Commands via osascript

    /// Ensure FC2 is running and Direct tab is active, minimize if needed
    private func ensureDirectTab() async -> VolumeResult {
        do {
            try await ensureFC2Ready()
            return .success
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Launch FC2 if not running, ensure Direct tab is active
    private func ensureFC2Ready() async throws {
        logger.info("🔧 ensureFC2Ready: checking if FC2 is running...")

        // Check if FC2 is running
        let checkScript = """
        tell application "System Events"
            return exists process "\(fc2Process)"
        end tell
        """
        let isRunning = try await runOsascript(checkScript) == "true"

        if !isRunning {
            logger.info("🚀 FC2 not running, launching...")
            // Launch FC2
            let launchScript = """
            tell application "\(fc2Process)" to launch
            """
            _ = try await runOsascript(launchScript)

            // Wait for FC2 to be ready (up to 10 seconds)
            for i in 1...20 {
                try await Task.sleep(for: .milliseconds(500))
                let ready = try await runOsascript(checkScript) == "true"
                if ready {
                    logger.info("✅ FC2 launched after \(i * 500)ms")
                    // Give it a moment more to fully initialize UI
                    try await Task.sleep(for: .milliseconds(1000))
                    break
                }
            }
        } else {
            logger.info("✅ FC2 already running")
        }

        // Check if Direct tab is already active (works even with minimized window)
        let tabCheckScript = """
        tell application "System Events"
            tell process "\(fc2Process)"
                if (count of windows) = 0 then
                    return "no_window"
                end if
                try
                    get group "Playback 1 - 2" of group 5 of window "\(fc2Process)"
                    return "ready"
                on error
                    return "wrong_tab"
                end try
            end tell
        end tell
        """

        let tabStatus = try await runOsascript(tabCheckScript)

        if tabStatus == "ready" {
            logger.info("✅ FC2 already on Direct tab")
            return
        }

        // Direct tab not active — need to switch
        logger.info("🔀 Switching to Direct tab...")
        let switchScript = """
        tell application "System Events"
            tell process "\(fc2Process)"
                if (count of windows) > 0 then
                    click checkbox "Direct" of group "Navigation bar" of window "\(fc2Process)"
                end if
            end tell
        end tell
        """
        _ = try await runOsascript(switchScript)
        logger.info("✅ FC2 ready on Direct tab")
    }

    /// Ensure FC2 is ready before performing an action
    private func ensureReady() async throws {
        // Skip check if already verified (fast path for repeated actions)
        if isFC2Verified {
            return
        }

        logger.info("🔍 ensureReady: checking FC2 status...")

        // Quick check if process exists and Direct tab is active
        let checkScript = """
        tell application "System Events"
            if not (exists process "\(fc2Process)") then
                return "not_running"
            end if
            tell process "\(fc2Process)"
                if (count of windows) = 0 then
                    return "no_window"
                end if
                -- Check if Direct tab is active by checking if expected elements exist
                try
                    get group "Playback 1 - 2" of group 5 of window "\(fc2Process)"
                    return "ready"
                on error
                    return "wrong_tab"
                end try
            end tell
        end tell
        """

        let status = try await runOsascript(checkScript)
        logger.info("📊 FC2 status: \(status, privacy: .public)")

        if status == "ready" {
            isFC2Verified = true
            logger.info("✅ FC2 verified ready")
        } else {
            logger.info("⚠️ FC2 not ready (status: \(status, privacy: .public)), setting up...")
            // Need to set up FC2
            try await ensureFC2Ready()
            isFC2Verified = true
        }
    }

    /// Reset the verified state (call on errors to force re-check)
    private func resetVerifiedState() {
        isFC2Verified = false
    }

    /// Read slider value from a channel group
    private func readSliderValue(channel: String) async throws -> Double {
        try await ensureReady()

        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                return value of slider "Level" of group "\(channel)" of group 5 of window "\(fc2Process)"
            end tell
        end tell
        """

        let result = try await runOsascript(script)
        return parseDbValue(result)
    }

    /// Set slider value for a channel group
    private func setSliderValue(channel: String, db: Double) async throws {
        try await ensureReady()

        let dbString = formatDbValue(db)
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                set value of slider "Level" of group "\(channel)" of group 5 of window "\(fc2Process)" to "\(dbString)"
            end tell
        end tell
        """

        _ = try await runOsascript(script)
    }

    /// Read mute state from a channel group
    private func readMuteState(channel: String) async throws -> Bool {
        try await ensureReady()

        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                return value of checkbox "Mute" of group "\(channel)" of group 5 of window "\(fc2Process)"
            end tell
        end tell
        """

        let result = try await runOsascript(script)
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    /// Set mute state for a channel group
    private func setMuteState(channel: String, muted: Bool) async throws {
        try await ensureReady()

        let targetValue = muted ? 1 : 0
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                set cb to checkbox "Mute" of group "\(channel)" of group 5 of window "\(fc2Process)"
                if (value of cb) is not \(targetValue) then
                    click cb
                end if
            end tell
        end tell
        """

        _ = try await runOsascript(script)
    }

    /// Read Direct Monitor state
    private func readDirectMonitorState() async throws -> Bool {
        try await ensureReady()

        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                return value of (\(directMonitorCheckbox))
            end tell
        end tell
        """

        let result = try await runOsascript(script)
        // FC2 returns "true" or "false" as strings
        return result.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
    }

    /// Set Direct Monitor state
    private func setDirectMonitor(enabled: Bool) async throws {
        try await ensureReady()

        // FC2 returns true/false for checkbox values
        let targetValue = enabled ? "true" : "false"
        let script = """
        tell application "System Events"
            tell process "\(fc2Process)"
                set cb to \(directMonitorCheckbox)
                if (value of cb) is not \(targetValue) then
                    click cb
                end if
            end tell
        end tell
        """

        _ = try await runOsascript(script)
    }

    // MARK: - osascript Execution

    /// Run AppleScript via osascript subprocess (same as Node.js script)
    private func runOsascript(_ script: String) async throws -> String {
        // Extract first line for logging (avoid logging full scripts)
        let scriptPreview = script.components(separatedBy: .newlines).first ?? "script"

        return try await withCheckedThrowingContinuation { [logger] continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]

                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

                    if process.terminationStatus != 0 {
                        let rawError = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        logger.error("❌ osascript failed: \(rawError, privacy: .public) | script: \(scriptPreview, privacy: .public)")

                        // Parse osascript error: "138:237: execution error: System Events got an error: ... (-600)"
                        // Extract the meaningful part after "execution error: "
                        var cleanMessage = rawError.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let range = cleanMessage.range(of: "execution error: ") {
                            cleanMessage = String(cleanMessage[range.upperBound...])
                        }
                        // Strip trailing error codes like "(-600)" and period
                        cleanMessage = cleanMessage.replacingOccurrences(
                            of: #"\s*\(-?\d+\)\s*$"#, with: "", options: .regularExpression)

                        // Map known errors to specific types
                        let error: VolumeBackendError
                        if cleanMessage.contains("Can\u{2019}t get process") || cleanMessage.contains("(-600)") || rawError.contains("(-600)") {
                            error = .fc2NotRunning
                        } else if cleanMessage.contains("Can\u{2019}t get window") || cleanMessage.contains("count of windows") {
                            error = .fc2WindowNotFound
                        } else {
                            error = .appleScriptError(cleanMessage)
                        }
                        continuation.resume(throwing: error)
                    } else {
                        let output = String(data: outputData, encoding: .utf8) ?? ""
                        continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                } catch {
                    logger.error("❌ osascript exception: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Utilities

    /// Parse dB string like "-6dB" or "0dB" to Double
    private func parseDbValue(_ str: String) -> Double {
        let cleaned = str.trimmingCharacters(in: .whitespacesAndNewlines)
        let numStr = cleaned.replacingOccurrences(of: "dB", with: "")
                            .replacingOccurrences(of: " ", with: "")
        return Double(numStr) ?? 0.0
    }

    /// Format Double to dB string like "-6dB"
    private func formatDbValue(_ db: Double) -> String {
        return "\(Int(round(db)))dB"
    }
}
