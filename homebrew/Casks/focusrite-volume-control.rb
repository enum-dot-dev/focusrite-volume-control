# Template: the release workflow renders this with scripts/render_cask.py (version, sha256,
# and a quarantine postflight for unsigned builds) and pushes it to the tap repository.
cask "focusrite-volume-control" do
  version "1.5.1"
  sha256 :no_check

  url "https://github.com/enum-dot-dev/focusrite-volume-control/releases/download/v#{version}/FocusriteVolumeControl.dmg"
  name "Focusrite Volume Control"
  desc "Control Focusrite Scarlett 4th gen volume with media keys via Focusrite Control 2"
  homepage "https://enum.dev/focusrite-volume-control/"

  depends_on macos: ">= :sonoma"

  app "Focusrite Volume Control.app"

  caveats <<~EOS
    If media keys stop working after an update, reset the accessibility permission:
      tccutil reset Accessibility solutions.enum.FocusriteVolumeControl
    Then relaunch the app and re-grant the permission when prompted.
  EOS

  zap trash: [
    "~/Library/Preferences/net.nickmorozov.FocusriteVolumeControl.plist",
    "~/Library/Preferences/solutions.enum.FocusriteVolumeControl.plist",
  ]
end
