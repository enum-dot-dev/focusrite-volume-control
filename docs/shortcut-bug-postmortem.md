# Shortcut recording bug: recap and fix

> Imported from William Chan's fork, [wc2184/focusrite-volume-control](https://github.com/wc2184/focusrite-volume-control), together with the fix. Version numbers and release notes below refer to that fork's releases.

October 12, 2026 · Fixed in v1.1.1

## What happened

A saved custom shortcut assigned **Left Arrow to Volume Up**, without any modifier keys. With Focusrite selected as the sound output, pressing Left Arrow could therefore change the interface volume while navigating another app. The normal defaults are the system volume and mute keys.

The affected setting contained `keyCode: 123`, `modifiersRaw: 0`, and `isMediaKey: false`. In native macOS key codes, **123 is Left Arrow and 111 is F12**. JavaScript's legacy `event.keyCode` uses 123 for F12, but this app records native `NSEvent.keyCode` values.

## Confirmed defects

The shortcut recorder tracked its visible recording state in SwiftUI, but its native keyboard handler did not check that state. After recording finished, or Escape canceled it, the native view could retain keyboard focus and keep capturing subsequent keys. The capture callback immediately saved those keys against the recorder's action.

This was reproduced in an isolated native window: Escape set the visible recording state to false, but a subsequent Left Arrow was still captured. The test used a mock callback and did not change actual audio or saved preferences.

The global shortcut handler also accepted unmodified navigation keys. Consequently, an accidentally recorded navigation key could become a persistent global volume shortcut. Its monitor-update subscription read the old published shortcut state, which could delay registration changes until another update or restart.

## Where the code originated

The recorder, shortcut model, and global handler came from [Nick Morozov's Focusrite Volume Control](https://github.com/enum-dot-dev/focusrite-volume-control). Before this fix, all three files were byte-identical to upstream revision `7972b39b21afa88ecff98a1a5395b3d4766f887c`.

The earliest upstream commit containing the defective recorder is [`739ab79d49ed9390bae2c51a6398f442a925b87a`](https://github.com/enum-dot-dev/focusrite-volume-control/commit/739ab79d49ed9390bae2c51a6398f442a925b87a), **January 27, 2026**, titled "Add customizable keyboard shortcuts with recorder UI." Since that commit, the three files changed only in project-name comments before they were copied into this version.

The earliest local commit containing them is `61bde8d0a37ba05dd1c93b49d7615f04d979a90e`, **October 10, 2026**, a checkpoint of existing work. The first available project investigation already found those files staged before its source edits. The first public commit, [`d56c23b`](https://github.com/wc2184/focusrite-volume-control/commit/d56c23b6fd649e2b21d47b7a63ff47ec5463f22b), included the same implementation.

The defect was inherited and missed during review. This identifies its source history, but does not establish how the particular saved Left Arrow assignment was created.

## What remains unknown

The available local Codex history was searched across 79 session transcripts, thread metadata, and cached conversation records, including sessions outside the project folder. No original command assigning 123 to Volume Up, instruction to bind F12, or JavaScript/native key-code conversion was found before the incident.

The original preference writer and creation time remain unknown. Accidental recorder capture and an externally seeded key-code mix-up are possible explanations; neither is established as the cause of this particular setting. Upstream's 46 available commits contain no hardcoded numeric 123 or `0x7B` in text files and default to media keys.

## The emergency fix also went wrong

The initial response changed the configuration to Left Arrow → Volume Down and Right Arrow → Volume Up. That fixed direction while preserving unwanted global arrow behavior and introduced a new Right Arrow shortcut without a request for one.

The verification checked that arrows moved one volume tick in the chosen direction. It failed to check the more important requirement: ordinary navigation keys should remain navigation keys. Both assignments were subsequently removed and the system media-key defaults restored.

Earlier volume tests covered tick movement, pending writes, mute, and the perceptual curve. They did not exercise recorder cancellation, completed recording, or ordinary-key pass-through. Their passing results did not establish keyboard-interaction correctness.

## What v1.1.1 changes

- The native recorder accepts keys only while explicitly recording. Completion and cancellation immediately stop capture and release keyboard focus. Losing responder focus cancels recording, and held-key repeats cannot become another assignment.
- One shared recording action keeps only one recorder active. Global custom shortcuts pause during recording so an existing shortcut cannot consume the key being recorded.
- Global arrow, navigation, and editing shortcuts require Command, Control, or Option. Shift alone is insufficient because it is used for normal text selection. Bare function keys, including native F12, remain supported.
- On launch, unsafe saved navigation bindings are replaced with the corresponding default. Valid custom shortcuts and other preferences are preserved. New unsafe assignments are rejected at capture, save, and dispatch boundaries.
- Monitor registration uses the newly published values so adding, changing, resetting, or recording a shortcut takes effect immediately.

## Verification and release status

Regression tests cover native F12/Left Arrow distinction, navigation-key policy, persisted-setting repair, rejection of unsafe assignments, cancellation and focus release, completion and repeat handling, focus-loss cancellation, and real AppKit event routing while shortcuts are added, recorded, and reset. The original volume-controller tests remain in place.

Modern, Ventura, and Monterey packages include the correction. Older published packages contain the recorder defect; their release notes identify v1.1.1 as the replacement. The preserved v1.0.1 Modern archive remains byte-identical as requested.

Ventura and Monterey builds remain experimental: build and test checks run on Sonoma do not establish behavior on those older operating systems.
