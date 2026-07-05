cask "cliplet" do
  version "0.3.0"
  sha256 "5152debb278e43243dabfb3d9e90028dfff973c60385665823d411f48fa20ec6"

  url "https://github.com/IncredibleJ1021/cliplet/releases/download/v#{version}/cliplet-macOS-v#{version}.zip"
  name "cliplet"
  desc "Lightweight macOS menu bar clipboard history"
  homepage "https://github.com/IncredibleJ1021/cliplet"

  depends_on macos: ">= :ventura"

  app "cliplet.app"

  zap trash: [
    "~/Library/Application Support/cliplet",
    "~/Library/Preferences/io.github.incrediblej1021.cliplet.plist",
  ]
end
