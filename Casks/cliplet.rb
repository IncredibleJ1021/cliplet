cask "cliplet" do
  version "0.4.0"
  sha256 "c501f6887b8ac64949a2d0eae5e72b1250f82f61bc5c365c2fa63c3c520420f0"

  url "https://github.com/IncredibleJ1021/cliplet/releases/download/v#{version}/cliplet-macOS-v#{version}.zip"
  name "cliplet"
  desc "Lightweight macOS menu bar clipboard history"
  homepage "https://github.com/IncredibleJ1021/cliplet"

  depends_on macos: :ventura

  app "cliplet.app"

  zap trash: [
    "~/Library/Application Support/cliplet",
    "~/Library/Preferences/io.github.incrediblej1021.cliplet.plist",
  ]
end
