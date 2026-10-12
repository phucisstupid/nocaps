cask "nocaps" do
  version "1.8"
  sha256 "7299f086610d6b7c2ea0913604744c4f2fcaf30a90ba7f9d657a88c494cc8487"

  url "https://github.com/phucisstupid/nocaps/releases/download/v#{version}/NoCaps.zip"
  name "NoCaps"
  desc "Tap Caps Lock for Escape, hold it for Control"
  homepage "https://github.com/phucisstupid/nocaps"

  depends_on macos: :ventura

  app "NoCaps.app"

  uninstall quit: "app.nocaps.NoCaps",
            login_item: "NoCaps"
end
