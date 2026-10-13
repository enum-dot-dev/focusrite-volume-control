//
//  ShortcutRecorderTests.swift
//  Focusrite Volume ControlTests
//
//  Regression tests for the shortcut recorder lifecycle bug (docs/shortcut-bug-postmortem.md).
//  Ported from https://github.com/wc2184/focusrite-volume-control (MIT, William Chan).
//

import XCTest
import AppKit
import Carbon.HIToolbox
import class SwiftUI.NSHostingView
@testable import Focusrite_Volume_Control

final class ShortcutRecorderTests: XCTestCase {
    func testNativeF12AndLeftArrowAreDistinctAndOnlyF12IsAllowedBare() {
        let left = KeyboardShortcut(keyCode: UInt16(kVK_LeftArrow), modifiers: [])
        let f12 = KeyboardShortcut(keyCode: UInt16(kVK_F12), modifiers: [])
        XCTAssertEqual(left.keyCode, 123)
        XCTAssertEqual(f12.keyCode, 111)
        XCTAssertEqual(left.displayString, "←")
        XCTAssertEqual(f12.displayString, "F12")
        XCTAssertFalse(left.isAllowedGlobalShortcut)
        XCTAssertTrue(f12.isAllowedGlobalShortcut)
    }

    func testNavigationNeedsAnExplicitShortcutModifier() {
        for code in [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
                     kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
                     kVK_Tab, kVK_Return, kVK_Delete, kVK_ForwardDelete, kVK_Escape] {
            XCTAssertFalse(KeyboardShortcut(keyCode: UInt16(code), modifiers: []).isAllowedGlobalShortcut)
            XCTAssertFalse(KeyboardShortcut(keyCode: UInt16(code), modifiers: [.shift]).isAllowedGlobalShortcut)
            for modifier: NSEvent.ModifierFlags in [.command, .control, .option] {
                XCTAssertTrue(KeyboardShortcut(keyCode: UInt16(code), modifiers: modifier).isAllowedGlobalShortcut)
            }
        }
    }

    func testLoadingRepairsUnsafeSavedNavigationAndPreservesValidShortcuts() throws {
        let domain = "FocusriteShortcutTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        let saved: [String: KeyboardShortcut] = [
            "volumeUp": KeyboardShortcut(keyCode: UInt16(kVK_LeftArrow), modifiers: []),
            "volumeDown": KeyboardShortcut(keyCode: UInt16(kVK_F12), modifiers: []),
            "mute": KeyboardShortcut(keyCode: UInt16(kVK_RightArrow), modifiers: [.option]),
            "directMonitor": KeyboardShortcut(keyCode: UInt16(kVK_UpArrow), modifiers: [.shift])
        ]
        preferences.set(try JSONEncoder().encode(saved), forKey: "keyboardShortcuts")
        for manager in [ShortcutManager(preferences: preferences), ShortcutManager(preferences: preferences)] {
            XCTAssertEqual(manager.shortcut(for: .volumeUp), ShortcutAction.volumeUp.defaultShortcut)
            XCTAssertEqual(manager.shortcut(for: .volumeDown), saved["volumeDown"])
            XCTAssertEqual(manager.shortcut(for: .mute), saved["mute"])
            XCTAssertNil(manager.shortcut(for: .directMonitor))
        }
    }

    func testSettingRejectsBareNavigationWithoutReplacingExistingShortcut() {
        let manager = ShortcutManager(preferences: nil)
        manager.setShortcut(KeyboardShortcut(keyCode: UInt16(kVK_LeftArrow), modifiers: []), for: .volumeUp)
        XCTAssertEqual(manager.shortcut(for: .volumeUp), ShortcutAction.volumeUp.defaultShortcut)
    }

    @MainActor
    func testRecorderCancellationReleasesFocusAndCannotCaptureAnotherKey() {
        let recorder = ShortcutRecorderNSView()
        var captures: [KeyboardShortcut] = []
        var cancellations = 0
        recorder.onShortcutRecorded = { captures.append($0) }
        recorder.onCancel = { cancellations += 1 }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = recorder
        recorder.isRecording = true
        XCTAssertTrue(window.makeFirstResponder(recorder))
        recorder.keyDown(with: keyEvent(UInt16(kVK_Escape), window: window))
        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(window.firstResponder === recorder)
        recorder.keyDown(with: keyEvent(UInt16(kVK_F12), window: window))
        XCTAssertEqual(cancellations, 1)
        XCTAssertTrue(captures.isEmpty)
    }

    @MainActor
    func testRecorderCompletesExactlyOnceAndIgnoresInactiveAndRepeatedKeys() {
        let recorder = ShortcutRecorderNSView()
        var captures: [KeyboardShortcut] = []
        recorder.onShortcutRecorded = { captures.append($0) }
        recorder.keyDown(with: keyEvent(UInt16(kVK_F12)))
        XCTAssertTrue(captures.isEmpty)
        recorder.isRecording = true
        recorder.keyDown(with: keyEvent(UInt16(kVK_F12), repeated: true))
        XCTAssertTrue(captures.isEmpty)
        recorder.keyDown(with: keyEvent(UInt16(kVK_F12)))
        XCTAssertFalse(recorder.isRecording)
        recorder.keyDown(with: keyEvent(UInt16(kVK_F11)))
        XCTAssertEqual(captures.map(\.keyCode), [UInt16(kVK_F12)])
    }

    @MainActor
    func testRecorderLosingFocusCancelsRecording() {
        let recorder = ShortcutRecorderNSView()
        var cancellations = 0
        recorder.onCancel = { cancellations += 1 }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = recorder
        recorder.isRecording = true
        XCTAssertTrue(window.makeFirstResponder(recorder))
        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(cancellations, 1)
    }

    @MainActor
    func testSwiftUIRecorderBindingCancelsAndCompletesWithoutLaterAssignments() throws {
        let shortcuts = ShortcutManager(preferences: nil)
        let host = NSHostingView(rootView: ShortcutRecorderView(action: .volumeUp, shortcutManager: shortcuts))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 50),
                              styleMask: .titled, backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        func recorder(in view: NSView) -> ShortcutRecorderNSView? {
            if let found = view as? ShortcutRecorderNSView { return found }
            return view.subviews.lazy.compactMap { recorder(in: $0) }.first
        }
        shortcuts.recordingAction = .volumeUp
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let native = try XCTUnwrap(recorder(in: host))
        XCTAssertTrue(native.isRecording)
        XCTAssertTrue(window.firstResponder === native)
        native.keyDown(with: keyEvent(UInt16(kVK_Escape), window: window))
        XCTAssertNil(shortcuts.recordingAction)
        XCTAssertFalse(window.firstResponder === native)
        native.keyDown(with: keyEvent(UInt16(kVK_LeftArrow), window: window))
        XCTAssertEqual(shortcuts.shortcut(for: .volumeUp), ShortcutAction.volumeUp.defaultShortcut)

        shortcuts.recordingAction = .volumeUp
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertTrue(native.isRecording)
        native.keyDown(with: keyEvent(UInt16(kVK_F12), window: window))
        XCTAssertNil(shortcuts.recordingAction)
        native.keyDown(with: keyEvent(UInt16(kVK_F11), window: window))
        XCTAssertEqual(shortcuts.shortcut(for: .volumeUp)?.keyCode, UInt16(kVK_F12))
    }

    @MainActor
    func testHotkeysUpdateImmediatelyPauseForRecordingAndPassOrdinaryArrows() {
        let shortcuts = ShortcutManager(preferences: nil)
        let hotkeys = HotkeyManager(shortcutManager: shortcuts)
        var increases = 0
        hotkeys.onVolumeUp = { increases += 1 }
        hotkeys.start()
        defer { hotkeys.stop() }
        let sink = KeyEventSinkView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
                              styleMask: .titled, backing: .buffered, defer: false)
        window.contentView = sink
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        window.makeFirstResponder(sink)
        func press(_ code: Int) {
            let app = NSApplication.shared
            app.postEvent(keyEvent(UInt16(code), window: window), atStart: true)
            if let event = app.nextEvent(matching: .keyDown, until: Date().addingTimeInterval(0.03),
                                         inMode: .default, dequeue: true) { app.sendEvent(event) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        shortcuts.setShortcut(KeyboardShortcut(keyCode: UInt16(kVK_F12), modifiers: []), for: .volumeUp)
        press(kVK_F12)
        XCTAssertEqual(increases, 1)
        shortcuts.recordingAction = .volumeDown
        press(kVK_F12)
        XCTAssertEqual(increases, 1)
        shortcuts.recordingAction = nil
        press(kVK_F12)
        XCTAssertEqual(increases, 2)
        for code in [kVK_LeftArrow, kVK_RightArrow] { press(code) }
        XCTAssertEqual(increases, 2)
        XCTAssertTrue(sink.receivedKeys.contains(UInt16(kVK_LeftArrow)))
        XCTAssertTrue(sink.receivedKeys.contains(UInt16(kVK_RightArrow)))
        shortcuts.resetToDefault(for: .volumeUp)
        press(kVK_F12)
        XCTAssertEqual(increases, 2)
    }

    private func keyEvent(_ code: UInt16, window: NSWindow? = nil, repeated: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: window?.windowNumber ?? 0, context: nil,
                        characters: "", charactersIgnoringModifiers: "", isARepeat: repeated, keyCode: code)!
    }
}

private final class KeyEventSinkView: NSView {
    var receivedKeys: [UInt16] = []
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { receivedKeys.append(event.keyCode) }
}
