cask "focusrite-volume-control" do
  version "1.2"
  sha256 :no_check # Updated automatically by release workflow

  url "https://github.com/enum-labs/focusrite-volume-control/releases/download/v#{version}/FocusriteVolumeControl.dmg"
  name "Focusrite Volume Control"
  desc "Control Focusrite Scarlett 4th gen volume with media keys via Focusrite Control 2"
  homepage "https://enum-labs.github.io/focusrite-volume-control/"

  depends_on macos: ">= :sonoma"

  app "Focusrite Volume Control.app"

  caveats <<~EOS
    If media keys stop working after an update, reset the accessibility permission:
      tccutil reset Accessibility solutions.enum.FocusriteVolumeControl
    Then relaunch the app and re-grant the permission when prompted.
  EOS

  zap trash: [
    "~/Library/Preferences/solutions.enum.FocusriteVolumeControl.plist",
  ]
end
