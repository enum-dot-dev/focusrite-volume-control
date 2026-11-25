# Template: the release workflow renders this with scripts/render_cask.py (version, sha256,
# and quarantine-clearing postflight_steps for unsigned builds) and pushes it to the tap repository.
# The same template also renders focusrite-volume-control@beta (render_cask.py --beta).
cask "focusrite-volume-control" do
  version "1.5.1"
  sha256 :no_check

  url "https://github.com/enum-dot-dev/focusrite-volume-control/releases/download/v#{version}/VolumeControl.dmg"
  name "Volume Control"
  desc "Control Focusrite Scarlett 4th gen volume with media keys via Focusrite Control 2"
  homepage "https://enum.dev/focusrite-volume-control/"

  conflicts_with cask: "focusrite-volume-control@beta"
  depends_on macos: :sonoma

  app "Volume Control.app"

  zap trash: [
    "~/Library/Preferences/net.nickmorozov.FocusriteVolumeControl.plist",
    "~/Library/Preferences/solutions.enum.FocusriteVolumeControl.plist",
  ]

  caveats <<~EOS
    If media keys stop working after an update, reset the accessibility permission:
      tccutil reset Accessibility solutions.enum.FocusriteVolumeControl
    Then relaunch the app and re-grant the permission when prompted.
  EOS
end
