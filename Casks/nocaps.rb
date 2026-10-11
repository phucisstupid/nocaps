cask "nocaps" do
  version "1.6"
  sha256 "f7eaa94ef9079b0d26a55bf38884d624331fc2b19e1b1a7bf608479933e9c00c"

  url "https://github.com/phucisstupid/nocaps/releases/download/v#{version}/NoCaps.zip"
  name "NoCaps"
  desc "Tap Caps Lock for Escape, hold it for Control"
  homepage "https://github.com/phucisstupid/nocaps"

  depends_on macos: :ventura

  app "NoCaps.app"

  uninstall quit: "app.nocaps.NoCaps",
            login_item: "NoCaps"
end
