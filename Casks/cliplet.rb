cask "cliplet" do
  version "0.3.2"
  sha256 "696082bec6101b2daeb38df3062c1d0e4a4391a0042e5ae98b4bb2a400cc4d2f"

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
