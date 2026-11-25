//
//  VolumeController.swift
//  Focusrite Volume Control
//
//  High-level volume control logic for Focusrite devices.
//  Uses a pluggable backend (Accessibility control of FC2 now, AES70 API later).
//

import Foundation
import Combine
import AppKit  // For NSSound

/// Volume step granularity: how many key presses to traverse the full range
enum VolumeStepSize: String, CaseIterable, Identifiable {
    case system = "System"    // 16 steps (6.25%)
    case fine = "Fine"        // 32 steps (3.125%)
    case finest = "Finest"    // 64 steps (1.5625%)

    var id: String { rawValue }

    var percentage: Double {
        switch self {
        case .system: return 6.25      // 100/16
        case .fine:   return 3.125     // 100/32
        case .finest: return 1.5625    // 100/64
        }
    }

    var description: String {
        switch self {
        case .system: return "16 steps (matches macOS)"
        case .fine:   return "32 steps"
        case .finest: return "64 steps"
        }
    }
}

/// Available backend types for volume control
enum BackendType: String, CaseIterable, Identifiable {
    case accessibility = "Accessibility"
    case fcServer = "FC Server"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .accessibility:
            return "Controls via Focusrite Control 2 app"
        case .fcServer:
            return "Direct protocol (not yet implemented)"
        }
    }
}

/// Manages volume, mute, and direct monitor controls
/// This is the Controller in our MVC architecture
class VolumeController: ObservableObject {

    // MARK: - Published State (for UI binding)

    @Published var playbackVolume: Double = 0.0  // dB
    @Published var playbackMuted: Bool = false

    @Published var input1Volume: Double = 0.0
    @Published var input1Muted: Bool = false

    @Published var input2Volume: Double = 0.0
    @Published var input2Muted: Bool = false

    @Published var directMonitorEnabled: Bool = false

    @Published var isConnected: Bool = false
    @Published var statusMessage: String = "Initializing..."

    // MARK: - Configuration

    @Published var volumeStepSetting: VolumeStepSize = .system
    var stepSize: Double { volumeStepSetting.percentage }
    @Published var keepFC2Minimized: Bool = true  // Minimize FC2 on connect (user can unminimize manually)
    /// Reads macOS "Play feedback when volume is changed" from System Settings → Sound
    var playVolumeSound: Bool {
        UserDefaults.standard.bool(forKey: "com.apple.sound.beep.feedback")
    }
    @Published var ensureDirectMonitorOn: Bool = true  // Auto-enable Direct Monitor before volume changes
    @Published var allowGain: Bool = false  // Allow volume above 0dB (up to +6dB)
    @Published var backendType: BackendType = .accessibility  // Which backend to use
    let minVolume: Double = -127.0  // FC2's actual minimum

    /// Maximum volume depends on allowGain setting
    var maxVolume: Double { allowGain ? 6.0 : 0.0 }

    // MARK: - Private Properties

    private var backend: VolumeBackend
    private var cancellables = Set<AnyCancellable>()

    // Pre-mute volume for restore
    private var preMuteVolume: Double = -20.0

    // Tracks the most recent pending volume to prevent stale backend responses
    // from overwriting optimistic updates during rapid key presses
    private var pendingVolume: Double?
    private var volumeWriteTask: Task<Void, Never>?

    // MARK: - Initialization

    init(backend: VolumeBackend, backendType: BackendType = .accessibility) {
        self.backend = backend
        self.backendType = backendType
        setupBindings()
    }

    /// Convenience init with default Accessibility backend
    convenience init() {
        self.init(backend: AccessibilityBackend(), backendType: .accessibility)
    }

    private func setupBindings() {
        // Observe backend state changes
        // Use RunLoop.main.next to ensure updates happen after current view cycle
        backend.statePublisher
            .debounce(for: .milliseconds(10), scheduler: RunLoop.main)
            .sink { [weak self] state in
                self?.updateFromBackendState(state)
            }
            .store(in: &cancellables)
    }

    private func updateFromBackendState(_ state: VolumeState) {
        // Don't overwrite optimistic volume while rapid changes are pending
        if pendingVolume == nil {
            if playbackVolume != state.playbackVolume { playbackVolume = state.playbackVolume }
            let isMuted = state.playbackVolume <= minVolume
            if playbackMuted != isMuted { playbackMuted = isMuted }
        }
        if input1Volume != state.input1Volume { input1Volume = state.input1Volume }
        if input1Muted != state.input1Muted { input1Muted = state.input1Muted }
        if input2Volume != state.input2Volume { input2Volume = state.input2Volume }
        if input2Muted != state.input2Muted { input2Muted = state.input2Muted }
        if directMonitorEnabled != state.directMonitorEnabled { directMonitorEnabled = state.directMonitorEnabled }
        if isConnected != state.isConnected { isConnected = state.isConnected }
        if statusMessage != state.statusMessage { statusMessage = state.statusMessage }
    }

    // MARK: - Connection

    func connect() {
        Task {
            let result = await backend.connect()
            if case .error(let msg) = result {
                await MainActor.run {
                    self.statusMessage = msg
                    self.isConnected = false
                }
            } else {
                // Minimize FC2 after successful connect if setting is enabled
                let shouldMinimize = await MainActor.run { keepFC2Minimized }
                if shouldMinimize {
                    await backend.minimizeFC2IfNeeded()
                }
            }
        }
    }

    func disconnect() {
        volumeWriteTask?.cancel()
        volumeWriteTask = nil
        pendingVolume = nil
        backend.disconnect()
    }

    func refresh() {
        // A read started mid-write could report the old value
        guard pendingVolume == nil else { return }
        Task {
            _ = await backend.refresh()
        }
    }

    /// Restart the current backend connection
    func restart() {
        disconnect()
        connect()
    }

    /// Switch to a different backend type
    func switchBackend(to newType: BackendType) {
        guard newType != backendType else { return }

        // Disconnect current backend
        disconnect()

        // Clear existing bindings
        cancellables.removeAll()

        // Create new backend
        switch newType {
        case .accessibility:
            backend = AccessibilityBackend()
        case .fcServer:
            backend = FCServerBackend()
        }

        backendType = newType

        // Re-setup bindings for new backend
        setupBindings()

        // Connect with new backend
        connect()
    }

    // MARK: - Playback Volume Control

    func setPlaybackVolume(_ newVolume: Double) {
        // FC2 only accepts integer dB values - round to nearest int
        let rounded = round(newVolume)
        let clamped = max(minVolume, min(maxVolume, rounded))

        // Optimistic update so rapid key presses accumulate correctly
        playbackVolume = clamped
        playbackMuted = clamped <= minVolume
        pendingVolume = clamped

        // A single writer preserves key-press order. Presses that arrive while FC2
        // is busy only update pendingVolume, so the next write sends the newest value
        guard volumeWriteTask == nil else { return }
        volumeWriteTask = Task { [weak self] in
            guard let self else { return }
            while let target = self.pendingVolume, !Task.isCancelled {
                let result = await self.backend.setPlaybackVolume(
                    target, ensureDirectMonitor: self.ensureDirectMonitorOn)
                if case .error(let msg) = result {
                    print("Failed to set playback volume: \(msg)")
                }
                if self.pendingVolume == target {
                    self.pendingVolume = nil
                }
            }
            self.volumeWriteTask = nil
            await self.minimizeFC2IfNeeded()
        }
    }

    /// Minimize FC2 if the setting is enabled
    private func minimizeFC2IfNeeded() async {
        let shouldMinimize = await MainActor.run { keepFC2Minimized }
        if shouldMinimize {
            await backend.minimizeFC2IfNeeded()
        }
    }

    /// Play system sound for volume feedback if enabled
    private func playVolumeFeedback() {
        guard playVolumeSound else { return }
        NSSound.beep()
    }

    func playbackVolumeUp() {
        if playbackMuted {
            // Unmute and restore previous volume
            unmute()
            return
        }
        // Step in percentage, ensure at least 1 dB change
        let currentDb = round(playbackVolume)
        let currentPercent = dbToPercent(currentDb)
        let newPercent = min(100, currentPercent + stepSize)
        var newDb = round(percentToDb(newPercent))

        // If rounding resulted in same dB, force at least 1 dB change
        if newDb <= currentDb && currentDb < maxVolume {
            newDb = currentDb + 1
        }
        if newDb > maxVolume { newDb = maxVolume }
        setPlaybackVolume(newDb)
    }

    func playbackVolumeDown() {
        if playbackMuted {
            return
        }
        // Step in percentage, ensure at least 1 dB change
        let currentDb = round(playbackVolume)
        let currentPercent = dbToPercent(currentDb)
        let newPercent = max(0, currentPercent - stepSize)
        var newDb = round(percentToDb(newPercent))

        // If rounding resulted in same dB, force at least 1 dB change
        if newDb >= currentDb && currentDb > minVolume {
            newDb = currentDb - 1
        }
        if newDb < minVolume { newDb = minVolume }

        if newDb <= minVolume {
            mute()
        } else {
            setPlaybackVolume(newDb)
        }
    }

    // MARK: - Mute Control (volume-based: min volume = muted)

    func toggleMute() {
        if playbackMuted {
            unmute()
        } else {
            mute()
        }
    }

    func mute() {
        // Save current volume before muting (only if not already at min)
        if playbackVolume > minVolume {
            preMuteVolume = playbackVolume
        }

        // Set to minimum volume (acts as mute)
        // playbackMuted will be derived from volume in updateFromBackendState
        setPlaybackVolume(minVolume)
    }

    func unmute() {
        // Restore previous volume
        // playbackMuted will be derived from volume in updateFromBackendState
        setPlaybackVolume(preMuteVolume)
    }

    // MARK: - Input 1 Control

    func setInput1Volume(_ newVolume: Double) {
        let clamped = max(minVolume, min(maxVolume, newVolume))
        Task {
            _ = await backend.setInput1Volume(clamped)
            await minimizeFC2IfNeeded()
        }
    }

    func toggleInput1Mute() {
        Task {
            _ = await backend.setInput1Muted(!input1Muted)
            await minimizeFC2IfNeeded()
        }
    }

    // MARK: - Input 2 Control

    func setInput2Volume(_ newVolume: Double) {
        let clamped = max(minVolume, min(maxVolume, newVolume))
        Task {
            _ = await backend.setInput2Volume(clamped)
            await minimizeFC2IfNeeded()
        }
    }

    func toggleInput2Mute() {
        Task {
            _ = await backend.setInput2Muted(!input2Muted)
            await minimizeFC2IfNeeded()
        }
    }

    // MARK: - Direct Monitor Control

    func toggleDirectMonitor() {
        Task {
            _ = await backend.setDirectMonitorEnabled(!directMonitorEnabled)
            await minimizeFC2IfNeeded()
        }
    }

    func enableDirectMonitor() {
        Task {
            _ = await backend.setDirectMonitorEnabled(true)
            await minimizeFC2IfNeeded()
        }
    }

    func disableDirectMonitor() {
        Task {
            _ = await backend.setDirectMonitorEnabled(false)
            await minimizeFC2IfNeeded()
        }
    }

    // MARK: - dB to Percentage Conversion (Perceptual Curve)
    // 0% = -127 dB (silence), 50% = -16 dB (half volume), 100% = 0 dB (full)
    // Uses power curve where 50% of travel = -16 dB
    // Exponent ~0.197 satisfies: 127 * 0.5^0.197 - 127 = -16

    private let curveExponent: Double = 0.197  // Calculated for 50% = -16 dB with 127 range

    /// Convert dB to percentage (0-100) - perceptual curve
    func dbToPercent(_ db: Double) -> Double {
        // Inverse: percent = 100 * ((dB + 127) / 127)^(1/exponent)
        guard db < 0 else { return 100 }
        guard db > -127 else { return 0 }
        let normalized = (db + 127) / 127  // 0 to 1
        return max(0, min(100, 100 * pow(normalized, 1 / curveExponent)))
    }

    /// Convert percentage (0-100) to dB - perceptual curve
    func percentToDb(_ percent: Double) -> Double {
        // dB = 127 * (percent/100)^exponent - 127
        // At 50%: 127 * 0.5^0.197 - 127 ≈ -16 dB
        guard percent > 0 else { return -127 }
        guard percent < 100 else { return 0 }
        let p = percent / 100
        return max(-127, min(0, 127 * pow(p, curveExponent) - 127))
    }

    /// Get playback volume as percentage
    var playbackPercent: Double {
        get { dbToPercent(playbackVolume) }
    }

    /// Set playback volume from percentage
    func setPlaybackPercent(_ percent: Double) {
        setPlaybackVolume(percentToDb(percent))
    }

    // MARK: - Legacy Compatibility

    var volume: Double {
        get { playbackVolume }
        set { setPlaybackVolume(newValue) }
    }

    var isMuted: Bool {
        get { playbackMuted }
    }

    var isDirectMonitorEnabled: Bool {
        get { directMonitorEnabled }
    }

    func volumeUp() {
        playVolumeFeedback()
        playbackVolumeUp()
    }
    func volumeDown() {
        playVolumeFeedback()
        playbackVolumeDown()
    }
}
