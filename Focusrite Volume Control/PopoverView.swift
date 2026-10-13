//
//  PopoverView.swift
//  Focusrite Volume Control
//
//  Menu bar popover UI - minimal volume-focused design
//

import SwiftUI

struct PopoverView: View {
    @ObservedObject var volumeController: VolumeController
    var onOpenPreferences: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Header with connection status
            HeaderView(volumeController: volumeController, onOpenPreferences: onOpenPreferences)

            Divider()

            if volumeController.isConnected {
                // Volume controls
                VolumeControlView(volumeController: volumeController)
            } else {
                // Not connected
                NotConnectedView(volumeController: volumeController)
            }

            Divider()

            // Footer with shortcuts info and quit
            FooterView()
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Header View

struct HeaderView: View {
    @ObservedObject var volumeController: VolumeController
    var onOpenPreferences: () -> Void

    var body: some View {
        HStack {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("Volume Control")
                    .font(.headline)

                Text(volumeController.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Refresh button
            Button(action: { volumeController.refresh() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")

            // Preferences button (cog icon)
            Button(action: onOpenPreferences) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Preferences")
        }
    }

    private var statusColor: Color {
        volumeController.isConnected ? .green : .red
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var volumeController: VolumeController

    // Local state for smooth slider dragging
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var pendingValue: Double? = nil  // Value waiting for backend confirmation

    /// The value to display - uses pending value until backend catches up
    private var displayValue: Double {
        if isDragging {
            return dragValue
        } else if let pending = pendingValue {
            // Show pending until backend confirms (within 1 dB tolerance)
            if abs(volumeController.playbackVolume - pending) < 1.5 {
                return volumeController.playbackVolume
            }
            return pending
        }
        return volumeController.playbackVolume
    }

    var body: some View {
        // Single row: [Mute] [Vol-] ---slider--- [Vol+]  -20 dB
        HStack(spacing: 8) {
            // Mute button - ZStack keeps both icons in layout to prevent shift
            Button(action: { volumeController.toggleMute() }) {
                ZStack {
                    Image(systemName: "speaker.slash")
                        .opacity(volumeController.playbackMuted ? 0 : 1)
                    Image(systemName: "speaker.slash.fill")
                        .opacity(volumeController.playbackMuted ? 1 : 0)
                }
                .foregroundColor(volumeController.playbackMuted ? .red : .primary)
            }
            .buttonStyle(.plain)
            .help(volumeController.playbackMuted ? "Unmute" : "Mute")

            // Volume down button
            Button(action: { volumeController.volumeDown() }) {
                Image(systemName: "speaker.wave.1")
            }
            .buttonStyle(.plain)
            .help("Volume Down")
            .disabled(volumeController.playbackMuted)

            // Volume slider with 0dB tick mark
            ZStack(alignment: .top) {
                Slider(
                    value: Binding(
                        get: { displayValue },
                        set: { newValue in
                            // Clamp to 0dB unless gain is allowed
                            dragValue = volumeController.allowGain ? newValue : min(newValue, 0)
                        }
                    ),
                    in: -127...6,
                    onEditingChanged: { editing in
                        isDragging = editing
                        if editing {
                            // Start dragging - capture current value
                            dragValue = volumeController.playbackVolume
                            pendingValue = nil
                        } else {
                            // End dragging - commit final value
                            pendingValue = dragValue
                            volumeController.setPlaybackVolume(dragValue)
                        }
                    }
                )
                .disabled(volumeController.playbackMuted)

                // 0dB tick mark overlay
                GeometryReader { geo in
                    // Account for slider thumb padding (thumb doesn't go to edges)
                    let thumbRadius: CGFloat = 10
                    let trackWidth = geo.size.width - 2 * thumbRadius
                    let tickPositionInTrack = trackWidth * (127.0 / 133.0)  // 0dB is 127 units from -127 in a 133 unit range
                    let tickPosition = thumbRadius + tickPositionInTrack
                    Rectangle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 1, height: 6)
                        .offset(x: tickPosition - 0.5, y: geo.size.height - 3)
                }
            }
            .frame(height: 22)
            .onChange(of: volumeController.playbackVolume) { _, newValue in
                // Clear pending when backend confirms (within tolerance)
                if let pending = pendingValue, abs(newValue - pending) < 1.5 {
                    pendingValue = nil
                }
            }

            // Volume up button
            Button(action: { volumeController.volumeUp() }) {
                Image(systemName: "speaker.wave.3")
            }
            .buttonStyle(.plain)
            .help("Volume Up")
            .disabled(volumeController.playbackMuted)

            // Volume display
            Text(volumeString)
                .font(.system(.body, design: .monospaced))
                .frame(width: 55, alignment: .trailing)
        }
    }

    private var volumeString: String {
        if volumeController.playbackMuted {
            return "MUTE"
        } else if displayValue > 0 {
            return String(format: "+%.0f dB", displayValue)
        } else {
            return String(format: "%.0f dB", displayValue)
        }
    }
}

// MARK: - Not Connected View

struct NotConnectedView: View {
    @ObservedObject var volumeController: VolumeController

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.yellow)

            Text("Not Connected")
                .font(.headline)

            Text(volumeController.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Connect") {
                volumeController.connect()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - Footer View

struct FooterView: View {
    @ObservedObject private var shortcutManager = ShortcutManager.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Shortcuts")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(shortcutsDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    private var shortcutsDescription: String {
        let volUp = shortcutManager.displayString(for: .volumeUp)
        let volDown = shortcutManager.displayString(for: .volumeDown)
        let mute = shortcutManager.displayString(for: .mute)

        // Simplify display for default media keys
        if volUp == "Volume Up Key" && volDown == "Volume Down Key" && mute == "Mute Key" {
            return "System Volume Keys"
        }

        return "Volume: \(volDown)/\(volUp)  Mute: \(mute)"
    }
}

// MARK: - Preview

#Preview {
    PopoverView(volumeController: VolumeController(), onOpenPreferences: {})
}
