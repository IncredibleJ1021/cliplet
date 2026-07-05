cask "cliplet" do
  version "0.3.1"
  sha256 "12786e6310b1a197963a3b8b03d0e31f8f7f1fb32b36740c5306829f3e2b97f8"

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
