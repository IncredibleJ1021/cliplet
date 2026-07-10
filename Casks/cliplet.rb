cask "cliplet" do
  version "0.4.1"
  sha256 "e48aa013152b60d0fc97def20baabbbf43d8cb4a4c335e36c33a40d73cd4dcdb"

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
