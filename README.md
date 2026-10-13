# Volume Control

A macOS menu bar app that lets you control your Focusrite Scarlett Solo volume with your keyboard's media keys and custom shortcuts.

<p align="center">
  <img src="site/images/hud.png" alt="Volume HUD" height="60">
</p>

<p align="center">
  <img src="site/images/popover.png" alt="Menu bar popover" width="340">
  &nbsp;&nbsp;
  <img src="site/images/preferences.png" alt="Preferences window" width="340">
</p>

## Install

### Homebrew

```bash
brew install --cask enum-dot-dev/focusrite-volume-control/focusrite-volume-control
```

Homebrew 6.0 and later only load casks from third-party taps you've trusted. Installing by the full name, as above, adds the tap and trusts just this cask. If you'd rather tap first and install by the short name, run `brew trust --cask enum-dot-dev/focusrite-volume-control/focusrite-volume-control` before `brew install --cask focusrite-volume-control`.

### Manual

Download the latest DMG from [Releases](https://github.com/enum-dot-dev/focusrite-volume-control/releases/latest) and drag to Applications.

Releases are moving to Developer ID signing and notarization. Until a release says it is signed, macOS will block the first launch: right-click the app and choose **Open**. Signed releases update themselves through **Check for Updates...** in the menu bar menu.

## Requirements

- macOS 14.5 (Sonoma) or later
- A Focusrite interface managed by [Focusrite Control 2](https://focusrite.com/downloads) (Scarlett 4th Gen), with FC2 installed
- Accessibility permission (prompted on first launch). No Automation permission is needed.

## Compatibility

This has only been tested with a **Scarlett Solo 4th Gen**. Older Scarlett models (3rd Gen and earlier) aren't supported by Focusrite Control 2, so they can't work with this app either.

If you use a larger interface (2i2, 4i4, 16i16 and up) and something doesn't work, its FC2 window is probably laid out differently. [Open an issue](https://github.com/enum-dot-dev/focusrite-volume-control/issues) with your model and FC2 version and I'll try to patch it. Requests for things like preset key bindings are welcome there too.

## Features

- **Media key interception** — volume up/down/mute keys control your Focusrite instead of built-in speakers
- **Custom HUD** — floating volume overlay showing actual dB level
- **Perceptual volume curve** — 50% slider = -16 dB, matching how your ears perceive loudness
- **Custom hotkeys** — assign any keyboard shortcut to volume, mute, and direct monitor
- **Auto-detect** — activates only when a Focusrite Scarlett is the default output device
- **Direct monitor toggle** — control direct monitoring without opening Focusrite Control 2

## How it works

The app drives Focusrite Control 2's window in-process through the macOS Accessibility API, caching the controls it looks up so rapid key presses stay fast and in order. It intercepts system media keys through a `CGEventTap` and routes them to FC2's sliders instead of macOS's built-in volume control. Only the Accessibility permission is needed; there is no Automation (Apple Events) prompt.

## Known issues

- **Accessibility permission stuck:** If the app stops responding to media keys after an update or reinstall, macOS may have cached a stale accessibility grant. Reset it with:
  ```bash
  tccutil reset Accessibility solutions.enum.FocusriteVolumeControl
  ```
  Then relaunch the app and re-grant the permission when prompted.

## Build from source

Requires Xcode 26. Swift Package Manager fetches [Sparkle](https://sparkle-project.org) on the first build.

```bash
xcodebuild -scheme "Focusrite Volume Control" -configuration Release \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
```

`bash scripts/build-dmg.sh` builds and packages a DMG; see the script header for signing and notarization options.

## Credits

The native Accessibility control path, rapid key-press handling and the shortcut recorder fix are ported from [William Chan's version](https://github.com/wc2184/focusrite-volume-control) (MIT). His write-up of the shortcut bug is in [docs/shortcut-bug-postmortem.md](docs/shortcut-bug-postmortem.md).
