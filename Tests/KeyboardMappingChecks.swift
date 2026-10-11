import Foundation

private struct StoredMappingJournal: Decodable {
    let bootSession: String
    let originalCaps: [String: [KeyboardMapping.Entry]]
}

private struct SimulatedMappingFailure: Error {}

private func readMappingJournal(_ url: URL) throws -> StoredMappingJournal {
    try PropertyListDecoder().decode(StoredMappingJournal.self, from: Data(contentsOf: url))
}

private func expectRecoveryFailure(_ operation: () throws -> Void) {
    do {
        try operation()
        assertionFailure("Expected keyboard recovery to fail")
    } catch {}
}

func checkKeyboardMappingRecovery() throws {
    let files = FileManager.default
    let directory = files.temporaryDirectory.appendingPathComponent("nocaps-recovery-\(UUID().uuidString)")
    try files.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? files.removeItem(at: directory) }
    let journalURL = directory.appendingPathComponent("NoCaps/keyboard-mapping.plist")
    let source = KeyboardMapping.sourceKey
    let destination = KeyboardMapping.destinationKey
    let caps: KeyboardMapping.Entry = [source: KeyboardMapping.capsUsage, destination: 0x7_0000_0004, "vendor": 7]
    let unrelated: KeyboardMapping.Entry = [source: 0x7_0000_00E3, destination: 0x7_0000_00E0, "vendor": 99]
    let owned: KeyboardMapping.Entry = [source: KeyboardMapping.capsUsage, destination: KeyboardMapping.reservedUsage]
    var current = ["first": [caps, unrelated], "second": [unrelated]]
    var writes: [String] = []
    var failFirstRestore = false
    var failSecondInstallAfterChange: Bool?
    let keyboards = ["first", "second"].map { id in
        KeyboardMapping.Keyboard(
            id: id,
            readMappings: { current[id]! },
            writeMappings: { updated in
                // Every write must already have durable recovery data, including an empty original mapping.
                let journal = try readMappingJournal(journalURL)
                assert(!journal.bootSession.isEmpty)
                assert(journal.originalCaps[id] == (id == "first" ? [caps] : []))
                writes.append(id)
                if failFirstRestore && id == "first" { throw SimulatedMappingFailure() }
                if id == "second", failSecondInstallAfterChange == false { throw SimulatedMappingFailure() }
                current[id] = updated
                if id == "second", failSecondInstallAfterChange == true { throw SimulatedMappingFailure() }
            }
        )
    }
    let mapping = KeyboardMapping(journalURL: journalURL, keyboards: { keyboards })
    let count = try mapping.apply()
    assert(count == 2)
    assert(current == ["first": [unrelated, owned], "second": [unrelated, owned]])
    let installedJournal = try readMappingJournal(journalURL)
    assert(installedJournal.originalCaps == ["first": [caps], "second": []])
    try mapping.verify()
    let repeatedCount = try mapping.apply()
    assert(repeatedCount == 2 && writes == ["first", "second"])

    let changedUnrelated: KeyboardMapping.Entry = [source: 0x7_0000_00E3, destination: 0x7_0000_00E1, "vendor": 101]
    let addedUnrelated: KeyboardMapping.Entry = [source: 0x7_0000_0005, destination: 0x7_0000_0006]
    current["first"] = [changedUnrelated, owned, addedUnrelated]
    failFirstRestore = true
    expectRecoveryFailure { try mapping.restore() }
    assert(current["first"] == [changedUnrelated, owned, addedUnrelated])
    assert(current["second"] == [unrelated])
    let retainedJournal = try readMappingJournal(journalURL)
    assert(retainedJournal.originalCaps == ["first": [caps]])

    // A new instance must recover from disk after the failed restore, preserving later unrelated edits.
    failFirstRestore = false
    let recovery = KeyboardMapping(journalURL: journalURL, keyboards: { keyboards })
    try recovery.restore()
    assert(current["first"] == [changedUnrelated, addedUnrelated, caps])
    assert(current["second"] == [unrelated])
    assert(writes == ["first", "second", "first", "second", "first"])
    assert(!files.fileExists(atPath: journalURL.path))
    try recovery.restore()
    assert(writes.count == 5)

    // The second install can fail before or after changing its property; the first must still recover.
    for failAfterChange in [false, true] {
        current = ["first": [caps, unrelated], "second": [unrelated]]
        failSecondInstallAfterChange = failAfterChange
        let partial = KeyboardMapping(journalURL: journalURL, keyboards: { keyboards })
        expectRecoveryFailure { _ = try partial.apply() }
        assert(current["first"] == [unrelated, owned])
        assert(current["second"] == (failAfterChange ? [unrelated, owned] : [unrelated]))
        let partialJournal = try readMappingJournal(journalURL)
        assert(partialJournal.originalCaps == ["first": [caps], "second": []])

        failSecondInstallAfterChange = nil
        let partialRecovery = KeyboardMapping(journalURL: journalURL, keyboards: { keyboards })
        try partialRecovery.restore()
        assert(current == ["first": [unrelated, caps], "second": [unrelated]])
        assert(!files.fileExists(atPath: journalURL.path))
    }

    // A file where the recovery directory belongs makes persistence fail deterministically.
    let blockedDirectory = directory.appendingPathComponent("blocked")
    try Data("not a directory".utf8).write(to: blockedDirectory)
    var blockedMappings = [caps, unrelated]
    var blockedWrites = 0
    let blocked = KeyboardMapping(
        journalURL: blockedDirectory.appendingPathComponent("keyboard-mapping.plist"),
        keyboards: {
            [
                KeyboardMapping.Keyboard(
                    id: "blocked",
                    readMappings: { blockedMappings },
                    writeMappings: {
                        blockedWrites += 1
                        blockedMappings = $0
                    }
                )
            ]
        }
    )
    expectRecoveryFailure { _ = try blocked.apply() }
    assert(blockedWrites == 0 && blockedMappings == [caps, unrelated])
    print(
        "Keyboard recovery: write-ahead journal, partial installs, persistence failure, and failed-restore retry passed"
    )
}
