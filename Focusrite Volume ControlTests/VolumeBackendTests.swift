//
//  VolumeBackendTests.swift
//  Focusrite Volume ControlTests
//
//  Tests for VolumeBackend types, errors, and state structures.
//

import XCTest
@testable import Focusrite_Volume_Control

final class VolumeBackendTests: XCTestCase {

    // MARK: - VolumeState Tests

    func testVolumeState_DefaultValues() {
        let state = VolumeState()

        XCTAssertEqual(state.playbackVolume, 0.0)
        XCTAssertFalse(state.playbackMuted)
        XCTAssertEqual(state.input1Volume, 0.0)
        XCTAssertFalse(state.input1Muted)
        XCTAssertEqual(state.input2Volume, 0.0)
        XCTAssertFalse(state.input2Muted)
        XCTAssertFalse(state.directMonitorEnabled)
        XCTAssertFalse(state.isConnected)
        XCTAssertEqual(state.statusMessage, "Not connected")
    }

    func testVolumeState_InitWithValues() {
        let state = VolumeState(
            playbackVolume: -20.0,
            playbackMuted: true,
            input1Volume: -30.0,
            input1Muted: false,
            input2Volume: -40.0,
            input2Muted: true,
            directMonitorEnabled: true,
            isConnected: true,
            statusMessage: "Connected"
        )

        XCTAssertEqual(state.playbackVolume, -20.0)
        XCTAssertTrue(state.playbackMuted)
        XCTAssertEqual(state.input1Volume, -30.0)
        XCTAssertFalse(state.input1Muted)
        XCTAssertEqual(state.input2Volume, -40.0)
        XCTAssertTrue(state.input2Muted)
        XCTAssertTrue(state.directMonitorEnabled)
        XCTAssertTrue(state.isConnected)
        XCTAssertEqual(state.statusMessage, "Connected")
    }

    // MARK: - VolumeResult Tests

    func testVolumeResult_Success() {
        let result = VolumeResult.success

        switch result {
        case .success:
            // Expected
            break
        case .error:
            XCTFail("Expected success, got error")
        }
    }

    func testVolumeResult_Error() {
        let result = VolumeResult.error("Test error message")

        switch result {
        case .success:
            XCTFail("Expected error, got success")
        case .error(let message):
            XCTAssertEqual(message, "Test error message")
        }
    }

    // MARK: - VolumeBackendError Tests

    func testVolumeBackendError_FC2NotRunning_Description() {
        let error = VolumeBackendError.fc2NotRunning
        XCTAssertEqual(error.errorDescription, "Focusrite Control 2 is not running")
    }

    func testVolumeBackendError_FC2WindowNotFound_Description() {
        let error = VolumeBackendError.fc2WindowNotFound
        XCTAssertEqual(error.errorDescription, "Could not find Focusrite Control 2 window")
    }

    func testVolumeBackendError_SliderNotFound_Description() {
        let error = VolumeBackendError.sliderNotFound("Playback 1 - 2")
        XCTAssertEqual(error.errorDescription, "Could not find slider: Playback 1 - 2")
    }

    func testVolumeBackendError_AccessibilityError_Description() {
        let error = VolumeBackendError.accessibilityError("AXError -25204")
        XCTAssertEqual(error.errorDescription, "Accessibility error: AXError -25204")
    }

    func testVolumeBackendError_FC2NotInstalled_Description() {
        let error = VolumeBackendError.fc2NotInstalled
        XCTAssertEqual(error.errorDescription, "Focusrite Control 2 is not installed")
    }

    func testVolumeBackendError_AccessibilityNotGranted_Description() {
        let error = VolumeBackendError.accessibilityNotGranted
        XCTAssertEqual(error.errorDescription, "Accessibility permission is not granted")
    }

    func testVolumeBackendError_Timeout_Description() {
        let error = VolumeBackendError.timeout
        XCTAssertEqual(error.errorDescription, "Operation timed out")
    }

    func testVolumeBackendError_NotConnected_Description() {
        let error = VolumeBackendError.notConnected
        XCTAssertEqual(error.errorDescription, "Not connected to Focusrite Control 2")
    }

    func testVolumeBackendError_ConformsToLocalizedError() {
        let error: LocalizedError = VolumeBackendError.fc2NotRunning
        XCTAssertNotNil(error.errorDescription)
    }

    // MARK: - VolumeState Mutation Tests

    func testVolumeState_Mutation() {
        var state = VolumeState()

        state.playbackVolume = -50.0
        XCTAssertEqual(state.playbackVolume, -50.0)

        state.playbackMuted = true
        XCTAssertTrue(state.playbackMuted)

        state.isConnected = true
        XCTAssertTrue(state.isConnected)

        state.statusMessage = "Testing"
        XCTAssertEqual(state.statusMessage, "Testing")
    }

    // MARK: - Volume Range Tests

    func testVolumeState_AcceptsFulldBRange() {
        var state = VolumeState()

        // Test minimum
        state.playbackVolume = -127.0
        XCTAssertEqual(state.playbackVolume, -127.0)

        // Test maximum
        state.playbackVolume = 0.0
        XCTAssertEqual(state.playbackVolume, 0.0)

        // Test typical value
        state.playbackVolume = -20.0
        XCTAssertEqual(state.playbackVolume, -20.0)

        // Test negative extreme (shouldn't happen but struct allows it)
        state.playbackVolume = -200.0
        XCTAssertEqual(state.playbackVolume, -200.0)
    }
}
