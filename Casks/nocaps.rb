cask "nocaps" do
  version "1.0"
  sha256 "d8a3baa631042d917055c7d877673d916a1e8e342f857c6d30fddb0586449f79"

  url "https://github.com/phucisstupid/nocaps/releases/download/v#{version}/NoCaps.zip"
  name "NoCaps"
  desc "Tap Caps Lock for Escape, hold it for Control"
  homepage "https://github.com/phucisstupid/nocaps"

  depends_on macos: :ventura

  app "NoCaps.app"

  uninstall quit: "app.nocaps.NoCaps",
            login_item: "NoCaps"
end
