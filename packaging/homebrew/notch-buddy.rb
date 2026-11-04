cask "notch-buddy" do
  version "0.2.0"
  sha256 "6c3a5842301e83054168c00584d3c64630c38ddff40e7903e82bf95c9b7a8136"

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
