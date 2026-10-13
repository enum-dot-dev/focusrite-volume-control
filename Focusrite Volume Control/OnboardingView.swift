//
//  OnboardingView.swift
//  Focusrite Volume Control
//
//  Permission onboarding wizard — shown on launch until the
//  Accessibility permission is granted.
//

import SwiftUI
import Combine
import ApplicationServices

// MARK: - Permission Checks

func isAccessibilityGranted() -> Bool {
    AXIsProcessTrusted()
}

func areAllPermissionsGranted() -> Bool {
    // FC2 is controlled in-process through the Accessibility API, so this is the only permission
    isAccessibilityGranted()
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @State private var accessibilityGranted = false
    @State private var isChecking = false

    var onContinue: () -> Void

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text("Volume Control Setup")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("This app needs Accessibility permission to intercept volume keys.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 24)

            // Accessibility permission
            VStack(spacing: 16) {
                PermissionRow(
                    step: 1,
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    description: "Intercepts your Mac's volume keys so they control your Focusrite instead of the built-in speakers.",
                    isGranted: accessibilityGranted,
                    buttonTitle: "Grant Accessibility Access",
                    action: requestAccessibility,
                    fallbackAction: openAccessibilitySettings,
                    fallbackTitle: "Open System Settings"
                )
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 24)

            Divider()
                .padding(.horizontal, 24)

            // Footer buttons
            HStack {
                Button(action: recheckPermissions) {
                    HStack(spacing: 4) {
                        if isChecking {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Re-check")
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Skip") {
                    onContinue()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)

                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!accessibilityGranted)
            }
            .padding(24)
        }
        .frame(width: 480)
        .fixedSize(horizontal: true, vertical: true)
        .onAppear {
            recheckPermissions()
        }
        .onReceive(timer) { _ in
            refreshStatus()
        }
    }

    // MARK: - Actions

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            refreshStatus()
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func recheckPermissions() {
        isChecking = true
        accessibilityGranted = isAccessibilityGranted()
        isChecking = false
    }

    private func refreshStatus() {
        accessibilityGranted = isAccessibilityGranted()
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let step: Int
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let buttonTitle: String
    let action: () -> Void
    let fallbackAction: () -> Void
    let fallbackTitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.15) : Color.yellow.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isGranted ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Step \(step): \(title)")
                        .font(.headline)

                    Spacer()

                    Text(isGranted ? "Granted" : "Required")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isGranted ? .green : .orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        )
                }

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !isGranted {
                    HStack(spacing: 8) {
                        Button(buttonTitle, action: action)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                        Button(fallbackTitle, action: fallbackAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.top, 2)

                    Text("If already enabled, toggle it OFF then ON in System Settings (the app binary changed).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

#Preview {
    OnboardingView(onContinue: {})
}
