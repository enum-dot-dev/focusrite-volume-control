//
//  VolumeControllerTests.swift
//  Focusrite Volume ControlTests
//
//  Comprehensive tests for VolumeController covering all actions and conditions.
//

import XCTest
import Combine
@testable import Focusrite_Volume_Control

@MainActor
final class VolumeControllerTests: XCTestCase {

    var mockBackend: MockVolumeBackend!
    var controller: VolumeController!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        mockBackend = MockVolumeBackend()
        controller = VolumeController(backend: mockBackend)
        cancellables = []

        // Wait for initial state binding to settle
        try await Task.sleep(for: .milliseconds(50))
    }

    override func tearDown() {
        cancellables = nil
        controller = nil
        mockBackend = nil
    }

    // MARK: - Helper Methods

    /// Wait for state updates to propagate through Combine pipeline
    func waitForStateUpdate() async throws {
        try await Task.sleep(for: .milliseconds(20))
    }

    /// Get the last call to the mock backend
    func lastCall() -> MockVolumeBackend.Call? {
        mockBackend.calls.last
    }

    /// Get all calls matching a method name
    func calls(named method: String) -> [MockVolumeBackend.Call] {
        mockBackend.calls.filter { $0.method == method }
    }

    // MARK: - Connection Tests

    func testConnect_CallsBackend() async throws {
        controller.connect()
        try await waitForStateUpdate()

        XCTAssertTrue(mockBackend.calls.contains { $0.method == "connect" })
    }

    func testConnect_Success_UpdatesIsConnected() async throws {
        mockBackend.shouldFailConnect = false
        controller.connect()
        try await waitForStateUpdate()

        XCTAssertTrue(controller.isConnected)
        XCTAssertEqual(controller.statusMessage, "Connected")
    }

    func testConnect_Failure_UpdatesStatus() async throws {
        mockBackend.shouldFailConnect = true
        mockBackend.connectError = "FC2 not running"
        controller.connect()
        try await waitForStateUpdate()

        XCTAssertFalse(controller.isConnected)
        XCTAssertEqual(controller.statusMessage, "FC2 not running")
    }

    func testDisconnect_CallsBackend() {
        controller.disconnect()

        XCTAssertTrue(mockBackend.calls.contains { $0.method == "disconnect" })
    }

    func testRefresh_CallsBackend() async throws {
        controller.refresh()
        try await waitForStateUpdate()

        XCTAssertTrue(mockBackend.calls.contains { $0.method == "refresh" })
    }

    // MARK: - Set Playback Volume Tests

    func testSetPlaybackVolume_ClampsToMaximum() async throws {
        controller.setPlaybackVolume(10.0)  // Above max (0 dB)
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "0.0")
    }

    func testSetPlaybackVolume_ClampsToMinimum() async throws {
        controller.setPlaybackVolume(-200.0)  // Below min (-127 dB)
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-127.0")
    }

    func testSetPlaybackVolume_RoundsToInteger() async throws {
        controller.setPlaybackVolume(-20.7)  // Should round to -21
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-21.0")
    }

    func testSetPlaybackVolume_RoundsHalfAwayFromZero() async throws {
        controller.setPlaybackVolume(-20.5)  // Should round to -21 (away from zero)
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        // Swift's round() uses "round half away from zero": -20.5 -> -21
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-21.0")
    }

    func testSetPlaybackVolume_AtExactMinimum() async throws {
        controller.setPlaybackVolume(-127.0)
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-127.0")
    }

    func testSetPlaybackVolume_AtExactMaximum() async throws {
        controller.setPlaybackVolume(0.0)
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "0.0")
    }

    // MARK: - Volume Up Tests

    func testVolumeUp_IncreasesVolume() async throws {
        mockBackend.setPlaybackVolumeState(-50.0)
        try await waitForStateUpdate()

        controller.volumeUp()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        // At -50 dB, 5% step should increase by at least 1 dB
        if let dbString = volumeCalls.last?.parameters["db"],
           let db = Double(dbString) {
            XCTAssertGreaterThan(db, -50.0)
        } else {
            XCTFail("Could not parse volume")
        }
    }

    func testVolumeUp_WhenMuted_Unmutes() async throws {
        // Set up muted state (volume at minimum)
        mockBackend.setPlaybackVolumeState(-127.0)
        try await waitForStateUpdate()

        // Store pre-mute volume
        controller.setPlaybackVolume(-20.0)
        try await waitForStateUpdate()
        controller.mute()
        try await waitForStateUpdate()

        XCTAssertTrue(controller.playbackMuted)

        mockBackend.clearCalls()
        controller.volumeUp()
        try await waitForStateUpdate()

        // Should restore previous volume (unmute)
        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
    }

    func testVolumeUp_AtMaximum_StaysAtMaximum() async throws {
        mockBackend.setPlaybackVolumeState(0.0)  // Max volume
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.volumeUp()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        if !volumeCalls.isEmpty {
            XCTAssertEqual(volumeCalls.last?.parameters["db"], "0.0")
        }
    }

    func testVolumeUp_ForcesAtLeast1dBChange() async throws {
        // At a volume where small % change might round to same dB
        mockBackend.setPlaybackVolumeState(-5.0)
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.volumeUp()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        if let dbString = volumeCalls.last?.parameters["db"],
           let db = Double(dbString) {
            // Should be at least 1 dB higher or at max
            XCTAssertTrue(db >= -4.0 || db == 0.0)
        }
    }

    // MARK: - Volume Down Tests

    func testVolumeDown_DecreasesVolume() async throws {
        mockBackend.setPlaybackVolumeState(-50.0)
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.volumeDown()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        if let dbString = volumeCalls.last?.parameters["db"],
           let db = Double(dbString) {
            XCTAssertLessThan(db, -50.0)
        } else {
            XCTFail("Could not parse volume")
        }
    }

    func testVolumeDown_WhenMuted_DoesNothing() async throws {
        mockBackend.setPlaybackVolumeState(-127.0)  // Muted
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.volumeDown()
        try await waitForStateUpdate()

        // Should not call setPlaybackVolume when already muted
        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertTrue(volumeCalls.isEmpty)
    }

    func testVolumeDown_NearMinimum_Mutes() async throws {
        // Set to near minimum (should mute when going down)
        mockBackend.setPlaybackVolumeState(-126.0)
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.volumeDown()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-127.0")
    }

    func testVolumeDown_ForcesAtLeast1dBChange() async throws {
        mockBackend.setPlaybackVolumeState(-100.0)
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.volumeDown()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        if let dbString = volumeCalls.last?.parameters["db"],
           let db = Double(dbString) {
            // Should be at least 1 dB lower
            XCTAssertLessThanOrEqual(db, -101.0)
        }
    }

    // MARK: - Mute Tests

    func testMute_SetsVolumeToMinimum() async throws {
        mockBackend.setPlaybackVolumeState(-20.0)
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.mute()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-127.0")
    }

    func testMute_SavesPreMuteVolume() async throws {
        mockBackend.setPlaybackVolumeState(-35.0)
        try await waitForStateUpdate()

        controller.mute()
        try await waitForStateUpdate()

        // Now unmute and check if it restores
        mockBackend.clearCalls()
        controller.unmute()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-35.0")
    }

    func testMute_WhenAlreadyAtMinimum_DoesNotSavePreMute() async throws {
        // Start at minimum
        mockBackend.setPlaybackVolumeState(-127.0)
        try await waitForStateUpdate()

        // Set a known pre-mute volume first
        controller.setPlaybackVolume(-25.0)
        try await waitForStateUpdate()
        controller.mute()
        try await waitForStateUpdate()

        // Mute again from minimum
        mockBackend.setPlaybackVolumeState(-127.0)
        try await waitForStateUpdate()
        mockBackend.clearCalls()
        controller.mute()
        try await waitForStateUpdate()

        // Unmute should still restore the old pre-mute volume
        mockBackend.clearCalls()
        controller.unmute()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        // Should restore -25.0, not -127.0
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-25.0")
    }

    // MARK: - Unmute Tests

    func testUnmute_RestoresPreMuteVolume() async throws {
        mockBackend.setPlaybackVolumeState(-45.0)
        try await waitForStateUpdate()

        controller.mute()
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.unmute()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-45.0")
    }

    func testUnmute_WithDefaultPreMuteVolume() async throws {
        // Fresh controller uses default pre-mute of -20.0
        mockBackend.setPlaybackVolumeState(-127.0)
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.unmute()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-20.0")
    }

    // MARK: - Toggle Mute Tests

    func testToggleMute_WhenUnmuted_Mutes() async throws {
        mockBackend.setPlaybackVolumeState(-30.0)
        try await waitForStateUpdate()

        XCTAssertFalse(controller.playbackMuted)

        mockBackend.clearCalls()
        controller.toggleMute()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-127.0")
    }

    func testToggleMute_WhenMuted_Unmutes() async throws {
        mockBackend.setPlaybackVolumeState(-30.0)
        try await waitForStateUpdate()

        controller.mute()
        try await waitForStateUpdate()

        XCTAssertTrue(controller.playbackMuted)

        mockBackend.clearCalls()
        controller.toggleMute()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-30.0")
    }

    // MARK: - Muted State Derivation Tests

    func testPlaybackMuted_DerivedFromMinVolume() async throws {
        mockBackend.setPlaybackVolumeState(-127.0)
        try await waitForStateUpdate()

        XCTAssertTrue(controller.playbackMuted)
    }

    func testPlaybackMuted_FalseAboveMinVolume() async throws {
        mockBackend.setPlaybackVolumeState(-126.0)
        try await waitForStateUpdate()

        XCTAssertFalse(controller.playbackMuted)
    }

    func testPlaybackMuted_FalseAtMaxVolume() async throws {
        mockBackend.setPlaybackVolumeState(0.0)
        try await waitForStateUpdate()

        XCTAssertFalse(controller.playbackMuted)
    }

    // MARK: - Step Size Tests

    func testStepSize_MatchesSystemIncrement() {
        // Default is system: macOS system volume uses 16 steps: 100/16 = 6.25
        XCTAssertEqual(controller.stepSize, 6.25)
        XCTAssertEqual(controller.volumeStepSetting, .system)
    }

    func testStepSize_Fine() {
        controller.volumeStepSetting = .fine
        XCTAssertEqual(controller.stepSize, 3.125)  // 100/32
    }

    func testStepSize_Finest() {
        controller.volumeStepSetting = .finest
        XCTAssertEqual(controller.stepSize, 1.5625)  // 100/64
    }

    // MARK: - Input Channel Tests

    func testSetInput1Volume_CallsBackend() async throws {
        controller.setInput1Volume(-40.0)
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setInput1Volume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-40.0")
    }

    func testSetInput1Volume_ClampsToRange() async throws {
        controller.setInput1Volume(50.0)  // Above max
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setInput1Volume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "0.0")
    }

    func testToggleInput1Mute_CallsBackend() async throws {
        mockBackend.setMockState(VolumeState(input1Muted: false))
        try await waitForStateUpdate()

        controller.toggleInput1Mute()
        try await waitForStateUpdate()

        let muteCalls = calls(named: "setInput1Muted")
        XCTAssertFalse(muteCalls.isEmpty)
        XCTAssertEqual(muteCalls.last?.parameters["muted"], "true")
    }

    func testSetInput2Volume_CallsBackend() async throws {
        controller.setInput2Volume(-55.0)
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setInput2Volume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-55.0")
    }

    func testToggleInput2Mute_CallsBackend() async throws {
        mockBackend.setMockState(VolumeState(input2Muted: true))
        try await waitForStateUpdate()

        controller.toggleInput2Mute()
        try await waitForStateUpdate()

        let muteCalls = calls(named: "setInput2Muted")
        XCTAssertFalse(muteCalls.isEmpty)
        XCTAssertEqual(muteCalls.last?.parameters["muted"], "false")
    }

    // MARK: - Direct Monitor Tests

    func testToggleDirectMonitor_WhenDisabled_Enables() async throws {
        mockBackend.setMockState(VolumeState(directMonitorEnabled: false))
        try await waitForStateUpdate()

        controller.toggleDirectMonitor()
        try await waitForStateUpdate()

        let calls = calls(named: "setDirectMonitorEnabled")
        XCTAssertFalse(calls.isEmpty)
        XCTAssertEqual(calls.last?.parameters["enabled"], "true")
    }

    func testToggleDirectMonitor_WhenEnabled_Disables() async throws {
        mockBackend.setMockState(VolumeState(directMonitorEnabled: true))
        try await waitForStateUpdate()

        controller.toggleDirectMonitor()
        try await waitForStateUpdate()

        let calls = calls(named: "setDirectMonitorEnabled")
        XCTAssertFalse(calls.isEmpty)
        XCTAssertEqual(calls.last?.parameters["enabled"], "false")
    }

    func testEnableDirectMonitor_CallsBackend() async throws {
        controller.enableDirectMonitor()
        try await waitForStateUpdate()

        let calls = calls(named: "setDirectMonitorEnabled")
        XCTAssertFalse(calls.isEmpty)
        XCTAssertEqual(calls.last?.parameters["enabled"], "true")
    }

    func testDisableDirectMonitor_CallsBackend() async throws {
        controller.disableDirectMonitor()
        try await waitForStateUpdate()

        let calls = calls(named: "setDirectMonitorEnabled")
        XCTAssertFalse(calls.isEmpty)
        XCTAssertEqual(calls.last?.parameters["enabled"], "false")
    }

    // MARK: - Legacy Compatibility Tests

    func testVolume_GetterReturnsPlaybackVolume() async throws {
        mockBackend.setPlaybackVolumeState(-42.0)
        try await waitForStateUpdate()

        XCTAssertEqual(controller.volume, -42.0)
    }

    func testVolume_SetterCallsSetPlaybackVolume() async throws {
        controller.volume = -33.0
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "-33.0")
    }

    func testIsMuted_ReturnsPlaybackMuted() async throws {
        mockBackend.setPlaybackVolumeState(-127.0)
        try await waitForStateUpdate()

        XCTAssertTrue(controller.isMuted)

        mockBackend.setPlaybackVolumeState(-50.0)
        try await waitForStateUpdate()

        XCTAssertFalse(controller.isMuted)
    }

    func testIsDirectMonitorEnabled_ReturnsDirectMonitorEnabled() async throws {
        mockBackend.setMockState(VolumeState(directMonitorEnabled: true))
        try await waitForStateUpdate()

        XCTAssertTrue(controller.isDirectMonitorEnabled)

        mockBackend.setMockState(VolumeState(directMonitorEnabled: false))
        try await waitForStateUpdate()

        XCTAssertFalse(controller.isDirectMonitorEnabled)
    }

    // MARK: - Percentage Conversion Property Tests

    func testPlaybackPercent_ReturnsConvertedValue() async throws {
        mockBackend.setPlaybackVolumeState(0.0)  // Max = 100%
        try await waitForStateUpdate()

        XCTAssertEqual(controller.playbackPercent, 100.0, accuracy: 0.1)

        mockBackend.setPlaybackVolumeState(-127.0)  // Min = 0%
        try await waitForStateUpdate()

        XCTAssertEqual(controller.playbackPercent, 0.0, accuracy: 0.1)
    }

    func testSetPlaybackPercent_SetsConvertedValue() async throws {
        mockBackend.clearCalls()
        controller.setPlaybackPercent(50.0)
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        // 50% should be approximately -16 dB
        if let dbString = volumeCalls.last?.parameters["db"],
           let db = Double(dbString) {
            XCTAssertEqual(db, -16.0, accuracy: 1.0)
        }
    }

    // MARK: - Allow Gain Tests

    func testAllowGain_DefaultIsFalse() {
        XCTAssertFalse(controller.allowGain)
    }

    func testMaxVolume_WhenAllowGainFalse_IsZero() {
        controller.allowGain = false
        XCTAssertEqual(controller.maxVolume, 0.0)
    }

    func testMaxVolume_WhenAllowGainTrue_IsSix() {
        controller.allowGain = true
        XCTAssertEqual(controller.maxVolume, 6.0)
    }

    func testSetPlaybackVolume_WhenAllowGainFalse_ClampsToZero() async throws {
        controller.allowGain = false
        controller.setPlaybackVolume(5.0)  // Try to set above 0 dB
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "0.0")
    }

    func testSetPlaybackVolume_WhenAllowGainTrue_AllowsPositiveDb() async throws {
        controller.allowGain = true
        controller.setPlaybackVolume(5.0)
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "5.0")
    }

    func testSetPlaybackVolume_WhenAllowGainTrue_ClampsToSixDb() async throws {
        controller.allowGain = true
        controller.setPlaybackVolume(10.0)  // Above +6 dB max
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        XCTAssertFalse(volumeCalls.isEmpty)
        XCTAssertEqual(volumeCalls.last?.parameters["db"], "6.0")
    }

    func testVolumeUp_WhenAllowGainTrue_CanGoAboveZero() async throws {
        controller.allowGain = true
        mockBackend.setPlaybackVolumeState(0.0)
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.volumeUp()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        if !volumeCalls.isEmpty {
            if let dbString = volumeCalls.last?.parameters["db"],
               let db = Double(dbString) {
                XCTAssertGreaterThan(db, 0.0)
            }
        }
    }

    func testVolumeUp_WhenAllowGainFalse_StopsAtZero() async throws {
        controller.allowGain = false
        mockBackend.setPlaybackVolumeState(-1.0)
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.volumeUp()
        try await waitForStateUpdate()

        let volumeCalls = calls(named: "setPlaybackVolume")
        if !volumeCalls.isEmpty {
            if let dbString = volumeCalls.last?.parameters["db"],
               let db = Double(dbString) {
                XCTAssertLessThanOrEqual(db, 0.0)
            }
        }
    }

    // MARK: - Backend Type Tests

    func testBackendType_DefaultIsAccessibility() {
        XCTAssertEqual(controller.backendType, .accessibility)
    }

    func testRestart_CallsDisconnectThenConnect() async throws {
        mockBackend.clearCalls()
        controller.restart()
        try await waitForStateUpdate()

        let disconnectCalls = calls(named: "disconnect")
        let connectCalls = calls(named: "connect")

        XCTAssertFalse(disconnectCalls.isEmpty, "restart should call disconnect")
        XCTAssertFalse(connectCalls.isEmpty, "restart should call connect")

        // Verify disconnect happens before connect
        if let disconnectIndex = mockBackend.calls.firstIndex(where: { $0.method == "disconnect" }),
           let connectIndex = mockBackend.calls.firstIndex(where: { $0.method == "connect" }) {
            XCTAssertLessThan(disconnectIndex, connectIndex, "disconnect should happen before connect")
        }
    }

    // MARK: - Ensure Direct Monitor Tests

    func testEnsureDirectMonitorOn_DefaultIsTrue() {
        XCTAssertTrue(controller.ensureDirectMonitorOn)
    }

    func testSetPlaybackVolume_WhenEnsureDirectMonitorOn_EnablesDirectMonitor() async throws {
        controller.ensureDirectMonitorOn = true
        mockBackend.setMockState(VolumeState(directMonitorEnabled: false, isConnected: true))
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.setPlaybackVolume(-20.0)
        try await waitForStateUpdate()

        let directMonitorCalls = calls(named: "setDirectMonitorEnabled")
        XCTAssertFalse(directMonitorCalls.isEmpty, "should enable direct monitor before volume change")
        XCTAssertEqual(directMonitorCalls.first?.parameters["enabled"], "true")
    }

    func testSetPlaybackVolume_WhenEnsureDirectMonitorOff_DoesNotEnableDirectMonitor() async throws {
        controller.ensureDirectMonitorOn = false
        mockBackend.setMockState(VolumeState(directMonitorEnabled: false, isConnected: true))
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.setPlaybackVolume(-20.0)
        try await waitForStateUpdate()

        let directMonitorCalls = calls(named: "setDirectMonitorEnabled")
        XCTAssertTrue(directMonitorCalls.isEmpty, "should not enable direct monitor when setting is off")
    }

    func testSetPlaybackVolume_WhenDirectMonitorAlreadyOn_DoesNotCallAgain() async throws {
        controller.ensureDirectMonitorOn = true
        mockBackend.setMockState(VolumeState(directMonitorEnabled: true, isConnected: true))
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.setPlaybackVolume(-20.0)
        try await waitForStateUpdate()

        let directMonitorCalls = calls(named: "setDirectMonitorEnabled")
        XCTAssertTrue(directMonitorCalls.isEmpty, "should not call setDirectMonitorEnabled when already on")
    }

    // MARK: - Rapid Write Coalescing Tests

    func testSetPlaybackVolume_RapidCalls_CoalesceToNewestValue() async throws {
        mockBackend.setPlaybackVolumeState(-40.0)
        try await waitForStateUpdate()

        mockBackend.clearCalls()
        controller.setPlaybackVolume(-30.0)
        controller.setPlaybackVolume(-25.0)
        controller.setPlaybackVolume(-20.0)
        try await waitForStateUpdate()

        // Presses made before the writer starts collapse into a single write of the newest value
        let written = calls(named: "setPlaybackVolume").compactMap { $0.parameters["db"] }
        XCTAssertEqual(written, ["-20.0"])
        XCTAssertEqual(controller.playbackVolume, -20.0)
    }
}
