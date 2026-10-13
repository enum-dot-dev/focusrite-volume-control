//
//  MockVolumeBackend.swift
//  Focusrite Volume ControlTests
//
//  Mock implementation of VolumeBackend for unit testing.
//  Allows verifying VolumeController behavior without a real FC2.
//

import Foundation
import Combine
@testable import Focusrite_Volume_Control

/// Mock backend that tracks all calls and allows controlling responses
class MockVolumeBackend: VolumeBackend {

    // MARK: - State

    private var _state = VolumeState()
    private let stateSubject = CurrentValueSubject<VolumeState, Never>(VolumeState())

    var statePublisher: AnyPublisher<VolumeState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var state: VolumeState { _state }

    // MARK: - Call Tracking

    struct Call: Equatable {
        let method: String
        let parameters: [String: String]

        init(_ method: String, _ params: [String: String] = [:]) {
            self.method = method
            self.parameters = params
        }
    }

    private(set) var calls: [Call] = []

    func clearCalls() {
        calls = []
    }

    // MARK: - Response Configuration

    var shouldFailConnect = false
    var shouldFailSetVolume = false
    var connectError = "Mock connection failed"
    var setVolumeError = "Mock set volume failed"

    // MARK: - State Manipulation (for tests)

    func setMockState(_ newState: VolumeState) {
        _state = newState
        stateSubject.send(_state)
    }

    func setPlaybackVolumeState(_ db: Double) {
        _state.playbackVolume = db
        stateSubject.send(_state)
    }

    func setPlaybackMutedState(_ muted: Bool) {
        _state.playbackMuted = muted
        stateSubject.send(_state)
    }

    func setConnectedState(_ connected: Bool) {
        _state.isConnected = connected
        _state.statusMessage = connected ? "Connected" : "Disconnected"
        stateSubject.send(_state)
    }

    // MARK: - VolumeBackend Implementation

    func connect() async -> VolumeResult {
        calls.append(Call("connect"))
        if shouldFailConnect {
            _state.isConnected = false
            _state.statusMessage = connectError
            stateSubject.send(_state)
            return .error(connectError)
        }
        _state.isConnected = true
        _state.statusMessage = "Connected"
        _state.playbackVolume = -20.0  // Default starting volume
        stateSubject.send(_state)
        return .success
    }

    func disconnect() {
        calls.append(Call("disconnect"))
        _state.isConnected = false
        _state.statusMessage = "Disconnected"
        stateSubject.send(_state)
    }

    func refresh() async -> VolumeResult {
        calls.append(Call("refresh"))
        stateSubject.send(_state)
        return .success
    }

    // MARK: - Playback Volume

    func getPlaybackVolume() async -> Result<Double, Error> {
        calls.append(Call("getPlaybackVolume"))
        return .success(_state.playbackVolume)
    }

    func setPlaybackVolume(_ db: Double) async -> VolumeResult {
        calls.append(Call("setPlaybackVolume", ["db": String(format: "%.1f", db)]))
        if shouldFailSetVolume {
            return .error(setVolumeError)
        }
        _state.playbackVolume = db
        stateSubject.send(_state)
        return .success
    }

    func setPlaybackMuted(_ muted: Bool) async -> VolumeResult {
        calls.append(Call("setPlaybackMuted", ["muted": String(muted)]))
        _state.playbackMuted = muted
        stateSubject.send(_state)
        return .success
    }

    // MARK: - Input 1

    func getInput1Volume() async -> Result<Double, Error> {
        calls.append(Call("getInput1Volume"))
        return .success(_state.input1Volume)
    }

    func setInput1Volume(_ db: Double) async -> VolumeResult {
        calls.append(Call("setInput1Volume", ["db": String(format: "%.1f", db)]))
        _state.input1Volume = db
        stateSubject.send(_state)
        return .success
    }

    func setInput1Muted(_ muted: Bool) async -> VolumeResult {
        calls.append(Call("setInput1Muted", ["muted": String(muted)]))
        _state.input1Muted = muted
        stateSubject.send(_state)
        return .success
    }

    // MARK: - Input 2

    func getInput2Volume() async -> Result<Double, Error> {
        calls.append(Call("getInput2Volume"))
        return .success(_state.input2Volume)
    }

    func setInput2Volume(_ db: Double) async -> VolumeResult {
        calls.append(Call("setInput2Volume", ["db": String(format: "%.1f", db)]))
        _state.input2Volume = db
        stateSubject.send(_state)
        return .success
    }

    func setInput2Muted(_ muted: Bool) async -> VolumeResult {
        calls.append(Call("setInput2Muted", ["muted": String(muted)]))
        _state.input2Muted = muted
        stateSubject.send(_state)
        return .success
    }

    // MARK: - Direct Monitor

    func setDirectMonitorEnabled(_ enabled: Bool) async -> VolumeResult {
        calls.append(Call("setDirectMonitorEnabled", ["enabled": String(enabled)]))
        _state.directMonitorEnabled = enabled
        stateSubject.send(_state)
        return .success
    }

    // MARK: - FC2 Window Control

    func minimizeFC2IfNeeded() async {
        calls.append(Call("minimizeFC2IfNeeded"))
    }
}
