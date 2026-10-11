import Foundation

func checkAppRestart() throws {
    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent("nocaps-restart-\(UUID().uuidString)")
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: directory) }
    let openerURL = directory.appendingPathComponent("fake opener 'quoted'.sh")
    let argumentsURL = URL(fileURLWithPath: openerURL.path + ".arguments")
    let bundleURL = directory.appendingPathComponent("NoCaps 'single' \"double\" spaces.app")
    try files.createDirectory(at: bundleURL, withIntermediateDirectories: true)
    let openerScript = """
        #!/bin/sh
        printf '%s\\000' "$@" > "$0.arguments"

        """
    try Data(openerScript.utf8).write(to: openerURL)
    try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: openerURL.path)

    let parent = Process()
    parent.executableURL = URL(fileURLWithPath: "/bin/sleep")
    parent.arguments = ["60"]
    try parent.run()
    defer {
        if parent.isRunning {
            parent.terminate()
            parent.waitUntilExit()
        }
    }
    let restart = try restartAppAfterExit(of: parent.processIdentifier, bundleURL: bundleURL, openerURL: openerURL)
    defer {
        if restart.isRunning {
            restart.terminate()
            restart.waitUntilExit()
        }
    }
    Thread.sleep(forTimeInterval: 0.15)
    assert(parent.isRunning)
    assert(!files.fileExists(atPath: argumentsURL.path))
    parent.terminate()
    parent.waitUntilExit()
    restart.waitUntilExit()
    assert(restart.terminationReason == .exit && restart.terminationStatus == 0)
    let arguments = String(decoding: try Data(contentsOf: argumentsURL), as: UTF8.self)
        .split(separator: "\0").map(String.init)
    assert(arguments == ["-n", bundleURL.path])
    print("App restart: waits for exit and preserves quoted paths with a fake opener passed")
}
