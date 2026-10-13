//
//  KeyboardShortcuts.swift
//  Focusrite Volume Control
//
//  Keyboard shortcut model and recorder for custom hotkeys
//

import SwiftUI
import Combine
import Carbon.HIToolbox

// MARK: - Shortcut Action

enum ShortcutAction: String, CaseIterable, Identifiable {
    case volumeUp = "volumeUp"
    case volumeDown = "volumeDown"
    case mute = "mute"
    case directMonitor = "directMonitor"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        case .directMonitor: return "Direct Monitor"
        }
    }

    var defaultShortcut: KeyboardShortcut? {
        switch self {
        case .volumeUp: return KeyboardShortcut(keyCode: nil, modifiers: [], isMediaKey: true, mediaKeyType: .volumeUp)
        case .volumeDown: return KeyboardShortcut(keyCode: nil, modifiers: [], isMediaKey: true, mediaKeyType: .volumeDown)
        case .mute: return KeyboardShortcut(keyCode: nil, modifiers: [], isMediaKey: true, mediaKeyType: .mute)
        case .directMonitor: return nil  // Unset by default
        }
    }
}

// MARK: - Media Key Type

enum MediaKeyType: String, Codable {
    case volumeUp
    case volumeDown
    case mute
}

// MARK: - Keyboard Shortcut

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt16?
    var modifiers: NSEvent.ModifierFlags
    var isMediaKey: Bool
    var mediaKeyType: MediaKeyType?

    init(keyCode: UInt16?, modifiers: NSEvent.ModifierFlags, isMediaKey: Bool = false, mediaKeyType: MediaKeyType? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isMediaKey = isMediaKey
        self.mediaKeyType = mediaKeyType
    }

    /// Navigation keys belong to the focused app unless an explicit modifier
    /// distinguishes the global shortcut from ordinary navigation/selection.
    var isAllowedGlobalShortcut: Bool {
        if isMediaKey { return mediaKeyType != nil }
        guard let keyCode else { return false }
        let navigationKeys: Set<UInt16> = [
            UInt16(kVK_LeftArrow), UInt16(kVK_RightArrow),
            UInt16(kVK_UpArrow), UInt16(kVK_DownArrow),
            UInt16(kVK_Home), UInt16(kVK_End),
            UInt16(kVK_PageUp), UInt16(kVK_PageDown),
            UInt16(kVK_Tab), UInt16(kVK_Return),
            UInt16(kVK_Delete), UInt16(kVK_ForwardDelete), UInt16(kVK_Escape)
        ]
        return !navigationKeys.contains(keyCode)
            || !modifiers.intersection([.command, .control, .option]).isEmpty
    }

    // Custom Codable for NSEvent.ModifierFlags
    enum CodingKeys: String, CodingKey {
        case keyCode, modifiersRaw, isMediaKey, mediaKeyType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode)
        let raw = try container.decode(UInt.self, forKey: .modifiersRaw)
        modifiers = NSEvent.ModifierFlags(rawValue: raw)
        isMediaKey = try container.decode(Bool.self, forKey: .isMediaKey)
        mediaKeyType = try container.decodeIfPresent(MediaKeyType.self, forKey: .mediaKeyType)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifiersRaw)
        try container.encode(isMediaKey, forKey: .isMediaKey)
        try container.encodeIfPresent(mediaKeyType, forKey: .mediaKeyType)
    }

    var displayString: String {
        if isMediaKey {
            switch mediaKeyType {
            case .volumeUp: return "Volume Up Key"
            case .volumeDown: return "Volume Down Key"
            case .mute: return "Mute Key"
            case .none: return "Media Key"
            }
        }

        guard let keyCode = keyCode else { return "Not Set" }

        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        parts.append(keyCodeToString(keyCode))

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        // Common key codes
        switch Int(keyCode) {
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_Tab: return "⇥"
        case kVK_Return: return "↩"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        default:
            // Try to get character from key code
            if let char = characterForKeyCode(keyCode) {
                return char.uppercased()
            }
            return "Key \(keyCode)"
        }
    }

    private func characterForKeyCode(_ keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0

        let error = UCKeyTranslate(
            keyboardLayout,
            keyCode,
            UInt16(kUCKeyActionDown),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )

        guard error == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

// MARK: - Shortcut Manager

class ShortcutManager: ObservableObject {
    static let shared = ShortcutManager()

    @Published var shortcuts: [ShortcutAction: KeyboardShortcut?] = [:]
    @Published var recordingAction: ShortcutAction?

    private let userDefaultsKey = "keyboardShortcuts"
    private let preferences: UserDefaults?

    init(preferences: UserDefaults? = .standard) {
        self.preferences = preferences
        loadShortcuts()
    }

    func loadShortcuts() {
        if let data = preferences?.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: KeyboardShortcut].self, from: data) {
            var repaired = false
            for action in ShortcutAction.allCases {
                if let shortcut = decoded[action.rawValue] {
                    if shortcut.isAllowedGlobalShortcut {
                        shortcuts[action] = shortcut
                    } else {
                        shortcuts[action] = action.defaultShortcut
                        repaired = true
                    }
                } else {
                    shortcuts[action] = action.defaultShortcut
                }
            }
            if repaired { saveShortcuts() }
        } else {
            // Set defaults
            for action in ShortcutAction.allCases {
                shortcuts[action] = action.defaultShortcut
            }
        }
    }

    func saveShortcuts() {
        var toEncode: [String: KeyboardShortcut] = [:]
        for (action, shortcut) in shortcuts {
            if let shortcut = shortcut {
                toEncode[action.rawValue] = shortcut
            }
        }
        if let data = try? JSONEncoder().encode(toEncode) {
            preferences?.set(data, forKey: userDefaultsKey)
        }
    }

    func setShortcut(_ shortcut: KeyboardShortcut?, for action: ShortcutAction) {
        guard shortcut?.isAllowedGlobalShortcut != false else { return }
        shortcuts[action] = shortcut
        saveShortcuts()
    }

    func resetToDefault(for action: ShortcutAction) {
        shortcuts[action] = action.defaultShortcut
        saveShortcuts()
    }

    func resetAllToDefaults() {
        for action in ShortcutAction.allCases {
            shortcuts[action] = action.defaultShortcut
        }
        saveShortcuts()
    }

    func shortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        return shortcuts[action] ?? action.defaultShortcut
    }

    func displayString(for action: ShortcutAction) -> String {
        if let shortcut = shortcuts[action] {
            return shortcut?.displayString ?? "Not Set"
        }
        return action.defaultShortcut?.displayString ?? "Not Set"
    }
}
