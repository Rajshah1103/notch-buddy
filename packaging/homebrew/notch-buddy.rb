cask "notch-buddy" do
  version "1.0.0"
  sha256 "524eee3111ef98c21fcbbf98fb17c30e3d60273e2657a12d1c50e71af10eb8ff"

  url "https://github.com/Rajshah1103/notch-buddy/releases/download/v#{version}/NotchBuddy-#{version}-arm64.zip"
  name "Notch Buddy"
  desc "Turns the Mac notch into a live hub with a buddy that tells you what needs you"
  homepage "https://github.com/Rajshah1103/notch-buddy"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Notch Hub.app"
  binary "#{appdir}/Notch Hub.app/Contents/MacOS/NotchHub", target: "notchhub"

  # The app is signed ad hoc and not notarized, so macOS would refuse to open a downloaded copy.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Notch Hub.app"]
  end

  zap trash: [
    "~/Library/Application Support/NotchHub",
    "~/Library/Caches/dev.notchhub.app",
    "~/Library/Preferences/dev.notchhub.app.plist",
  ]

  caveats <<~EOS
    Notch Buddy is not notarized. Homebrew removes the download quarantine for you, so it opens normally.
    On first launch, allow Accessibility, Automation and Screen Recording when asked, and Calendar if you use it.
    Send a bubble from any script with: notchhub emit --source demo --headline "Hello"
  EOS
end
