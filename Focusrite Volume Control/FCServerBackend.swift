//
//  FCServerBackend.swift
//  Focusrite Volume Control
//
//  Placeholder backend for future Focusrite Control Protocol/Server support.
//  This will use the AES70/OCA protocol to communicate directly with the device.
//
//  Currently NOT IMPLEMENTED - returns errors for all operations.
//

import Foundation
import Combine

class FCServerBackend: VolumeBackend {

    // MARK: - State

    private let stateSubject = CurrentValueSubject<VolumeState, Never>(VolumeState())

    var statePublisher: AnyPublisher<VolumeState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var state: VolumeState {
        stateSubject.value
    }

    // MARK: - Connection

    func connect() async -> VolumeResult {
        await MainActor.run {
            var newState = state
            newState.isConnected = false
            newState.statusMessage = "FC Server backend not yet implemented"
            stateSubject.send(newState)
        }
        return .error("FC Server backend is not yet implemented. Please use the Accessibility backend.")
    }

    func disconnect() {
        var newState = state
        newState.isConnected = false
        newState.statusMessage = "Disconnected"
        stateSubject.send(newState)
    }

    func refresh() async -> VolumeResult {
        return .error("FC Server backend is not yet implemented")
    }

    // MARK: - Playback Volume (Not Implemented)

    func getPlaybackVolume() async -> Result<Double, Error> {
        return .failure(VolumeBackendError.notConnected)
    }

    func setPlaybackVolume(_ db: Double) async -> VolumeResult {
        return .error("FC Server backend is not yet implemented")
    }

    func setPlaybackMuted(_ muted: Bool) async -> VolumeResult {
        return .error("FC Server backend is not yet implemented")
    }

    // MARK: - Input 1 (Not Implemented)

    func getInput1Volume() async -> Result<Double, Error> {
        return .failure(VolumeBackendError.notConnected)
    }

    func setInput1Volume(_ db: Double) async -> VolumeResult {
        return .error("FC Server backend is not yet implemented")
    }

    func setInput1Muted(_ muted: Bool) async -> VolumeResult {
        return .error("FC Server backend is not yet implemented")
    }

    // MARK: - Input 2 (Not Implemented)

    func getInput2Volume() async -> Result<Double, Error> {
        return .failure(VolumeBackendError.notConnected)
    }

    func setInput2Volume(_ db: Double) async -> VolumeResult {
        return .error("FC Server backend is not yet implemented")
    }

    func setInput2Muted(_ muted: Bool) async -> VolumeResult {
        return .error("FC Server backend is not yet implemented")
    }

    // MARK: - Direct Monitor (Not Implemented)

    func setDirectMonitorEnabled(_ enabled: Bool) async -> VolumeResult {
        return .error("FC Server backend is not yet implemented")
    }

    // MARK: - FC2 Window Control (Not Applicable)

    func minimizeFC2IfNeeded() async {
        // Not applicable for FC Server - no FC2 app needed
    }
}
