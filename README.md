# Focusrite Volume Control

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
brew tap enum-labs/focusrite-volume-control
brew install --cask focusrite-volume-control
```

### Manual

Download the latest DMG from [Releases](https://github.com/enum-labs/focusrite-volume-control/releases/latest) and drag to Applications.

## Requirements

- macOS 14.5 (Sonoma) or later
- [Focusrite Control 2](https://focusrite.com/downloads) installed
- Accessibility permission (prompted on first launch)

## Features

- **Media key interception** — volume up/down/mute keys control your Focusrite instead of built-in speakers
- **Custom HUD** — floating volume overlay showing actual dB level
- **Perceptual volume curve** — 50% slider = -16 dB, matching how your ears perceive loudness
- **Custom hotkeys** — assign any keyboard shortcut to volume, mute, and direct monitor
- **Auto-detect** — activates only when a Focusrite Scarlett is the default output device
- **Direct monitor toggle** — control direct monitoring without opening Focusrite Control 2

## How it works

The app drives Focusrite Control 2 via UI automation (AppleScript + Accessibility API). It intercepts system media keys through a `CGEventTap` and routes them to FC2's sliders instead of macOS's built-in volume control.

## Known issues

- **Accessibility permission stuck:** If the app stops responding to media keys after an update or reinstall, macOS may have cached a stale accessibility grant. Reset it with:
  ```bash
  tccutil reset Accessibility solutions.enum.FocusriteVolumeControl
  ```
  Then relaunch the app and re-grant the permission when prompted.

## Build from source

```bash
xcodebuild -scheme "Focusrite Volume Control" -configuration Release \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
```

## Credits

The native Accessibility control path, rapid key-press handling and the shortcut recorder fix are ported from [William Chan's version](https://github.com/wc2184/focusrite-volume-control) (MIT).
