//
//  ShortcutRecorderView.swift
//  Focusrite Volume Control
//
//  A view for recording keyboard shortcuts
//

import SwiftUI
import AppKit

// MARK: - Shortcut Recorder View

struct ShortcutRecorderView: View {
    let action: ShortcutAction
    @ObservedObject var shortcutManager: ShortcutManager
    private var isRecording: Bool { shortcutManager.recordingAction == action }

    private var recordingBinding: Binding<Bool> {
        Binding(
            get: { isRecording },
            set: { recording in
                if recording {
                    shortcutManager.recordingAction = action
                } else if isRecording {
                    shortcutManager.recordingAction = nil
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(action.displayName)
                .frame(width: 100, alignment: .leading)

            ShortcutRecorderButton(
                shortcut: shortcutManager.shortcuts[action] ?? nil,
                isRecording: recordingBinding,
                onShortcutRecorded: { shortcut in
                    shortcutManager.setShortcut(shortcut, for: action)
                }
            )
            .frame(width: 140)

            Button(action: {
                shortcutManager.resetToDefault(for: action)
            }) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .help("Reset to default")
            .opacity(isDefault ? 0.3 : 1.0)
            .disabled(isDefault)
        }
        .onDisappear {
            if isRecording { shortcutManager.recordingAction = nil }
        }
    }

    private var isDefault: Bool {
        let current = shortcutManager.shortcuts[action] ?? nil
        let defaultShortcut = action.defaultShortcut
        return current == defaultShortcut
    }
}

// MARK: - Shortcut Recorder Button

struct ShortcutRecorderButton: View {
    let shortcut: KeyboardShortcut?
    @Binding var isRecording: Bool
    let onShortcutRecorded: (KeyboardShortcut?) -> Void

    var body: some View {
        Button(action: {
            isRecording = true
        }) {
            HStack {
                if isRecording {
                    Text("Press shortcut...")
                        .foregroundColor(.secondary)
                } else {
                    Text(shortcut?.displayString ?? "Not Set")
                        .foregroundColor(shortcut == nil ? .secondary : .primary)
                }
                Spacer()
                if !isRecording && shortcut != nil {
                    Button(action: {
                        onShortcutRecorded(nil)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isRecording ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isRecording ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: 1)
        )
        .background(
            ShortcutRecorderEventHandler(
                isRecording: $isRecording,
                onShortcutRecorded: onShortcutRecorded
            )
        )
    }
}

// MARK: - Event Handler (NSViewRepresentable)

struct ShortcutRecorderEventHandler: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onShortcutRecorded: (KeyboardShortcut?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        configure(view)
        return view
    }

    private func configure(_ view: ShortcutRecorderNSView) {
        view.isRecording = isRecording
        view.onShortcutRecorded = { shortcut in
            onShortcutRecorded(shortcut)
            isRecording = false
        }
        view.onCancel = {
            isRecording = false
        }
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        configure(nsView)
        if isRecording {
            DispatchQueue.main.async { [weak nsView] in
                guard let nsView, nsView.isRecording else { return }
                nsView.window?.makeFirstResponder(nsView)
            }
        } else if nsView.window?.firstResponder === nsView {
            nsView.window?.makeFirstResponder(nil)
        }
    }
}

// MARK: - NSView for Key Event Handling

class ShortcutRecorderNSView: NSView {
    var isRecording = false
    var onShortcutRecorded: ((KeyboardShortcut) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { isRecording }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned && isRecording {
            isRecording = false
            onCancel?()
        }
        return resigned
    }

    private func finishRecording() {
        isRecording = false
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording, !event.isARepeat else { return }
        // Escape cancels recording
        if event.keyCode == 53 { // Escape key
            finishRecording()
            onCancel?()
            return
        }

        // Ignore modifier-only key presses
        let modifierOnlyKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63] // Modifier key codes
        if modifierOnlyKeys.contains(event.keyCode) {
            return
        }

        // Create shortcut from event
        let shortcut = KeyboardShortcut(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection([.control, .option, .shift, .command]),
            isMediaKey: false,
            mediaKeyType: nil
        )

        guard shortcut.isAllowedGlobalShortcut else {
            NSSound.beep()
            return
        }
        finishRecording()
        onShortcutRecorded?(shortcut)
    }

    override func flagsChanged(with event: NSEvent) {
        // Don't handle modifier-only changes
    }
}

// MARK: - Shortcuts Section View

struct ShortcutsSectionView: View {
    @ObservedObject var shortcutManager: ShortcutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard Shortcuts")
                .font(.headline)

            Text("System volume keys are the default. Click to record a shortcut; Esc cancels. Navigation keys require Command, Control, or Option.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(ShortcutAction.allCases) { action in
                    ShortcutRecorderView(action: action, shortcutManager: shortcutManager)
                }
            }

            HStack {
                Spacer()
                Button("Reset All to Defaults") {
                    shortcutManager.resetAllToDefaults()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }
}
