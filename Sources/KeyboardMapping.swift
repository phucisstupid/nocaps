import Darwin
import Foundation
import IOKit.hid
import IOKit.hidsystem

final class KeyboardMapping {
    typealias Entry = [String: UInt64]

    struct Keyboard {
        let id: String
        let readMappings: () throws -> [Entry]
        let writeMappings: ([Entry]) throws -> Void
    }

    static let capsUsage: UInt64 = 0x7_0000_0039
    static let reservedUsage: UInt64 = 0x7_0000_006F
    static let sourceKey = "HIDKeyboardModifierMappingSrc"
    static let destinationKey = "HIDKeyboardModifierMappingDst"
    private static let ownedEntry: Entry = [sourceKey: capsUsage, destinationKey: reservedUsage]

    private struct Journal: Codable {
        var bootSession: String
        var originalCaps: [String: [Entry]] = [:]
    }

    private struct MappingError: LocalizedError {
        let message: String
        var errorDescription: String? {
            message
        }
    }

    private lazy var client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    private var manager: IOHIDManager?
    private var cachedKeyboards: [Keyboard] = []
    private var keyboardChangePending = false
    private var keyboardChangeGeneration = 0
    var onKeyboardsChanged: ((Bool) -> Void)?
    private static let propertyKey = "UserKeyMapping" as CFString
    private let journalURL: URL
    private let listKeyboards: (() throws -> [Keyboard])?

    init(journalURL: URL? = nil, keyboards: (() throws -> [Keyboard])? = nil) {
        self.journalURL =
            journalURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NoCaps/keyboard-mapping.plist")
        listKeyboards = keyboards
    }

    deinit {
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
    }

    func startMonitoring() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOHIDManagerOptions.independentDevices.rawValue)
        self.manager = manager
        let callback: IOHIDDeviceCallback = { context, _, _, _ in
            guard let context else { return }
            Unmanaged<KeyboardMapping>.fromOpaque(context).takeUnretainedValue().keyboardsChanged()
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, callback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, callback, context)
        IOHIDManagerSetDeviceMatching(
            manager,
            [
                kIOHIDDeviceUsagePageKey: 1,
                kIOHIDDeviceUsageKey: 6,
            ] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    private func keyboardsChanged() {
        cachedKeyboards = []
        keyboardChangeGeneration += 1
        guard !keyboardChangePending else { return }
        keyboardChangePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.keyboardChangePending = false
            let generation = self.keyboardChangeGeneration
            self.onKeyboardsChanged?(true)
            // shortcut: publication after 1s needs manual refresh; add readiness tracking if keyboards exceed this delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.keyboardChangeGeneration == generation else { return }
                self.onKeyboardsChanged?(false)
            }
        }
    }

    static func installing(in mappings: [Entry]) throws -> [Entry] {
        try validate(mappings)
        guard !mappings.contains(where: { $0[sourceKey] == reservedUsage || $0[destinationKey] == reservedUsage })
        else {
            throw MappingError(
                message: "F20 is already used by another keyboard mapping. Remove that mapping before enabling NoCaps."
            )
        }
        return mappings.filter { $0[sourceKey] != capsUsage } + [ownedEntry]
    }

    static func restoring(in mappings: [Entry], originalCaps: [Entry]) throws -> [Entry] {
        try validate(mappings)
        try validate(originalCaps)
        guard originalCaps.allSatisfy({ $0[sourceKey] == capsUsage }) else {
            throw MappingError(message: "NoCaps' recovery file contains an invalid Caps Lock mapping.")
        }
        guard mappings.filter({ $0[sourceKey] == capsUsage }) == [ownedEntry] else { return mappings }
        return mappings.filter { $0[sourceKey] != capsUsage } + originalCaps
    }

    static func verify(in mappings: [Entry]) throws {
        try validate(mappings)
        guard mappings.filter({ $0[sourceKey] == capsUsage }) == [ownedEntry] else {
            throw MappingError(message: "Another app changed Caps Lock. Disable NoCaps before enabling it again.")
        }
        _ = try installing(in: mappings.filter { $0[sourceKey] != capsUsage })
    }

    func verify() throws {
        for keyboard in cachedKeyboards {
            try Self.verify(in: keyboard.readMappings())
        }
    }

    func apply() throws -> Int {
        var journal = try loadJournal()
        let keyboards = try keyboards()
        for keyboard in keyboards {
            let current = try keyboard.readMappings()
            if journal.originalCaps[keyboard.id] != nil {
                try Self.verify(in: current)
            } else {
                let updated = try Self.installing(in: current)
                journal.originalCaps[keyboard.id] = current.filter { $0[Self.sourceKey] == Self.capsUsage }
                try saveJournal(journal)
                try keyboard.writeMappings(updated)
            }
        }
        cachedKeyboards = keyboards
        return keyboards.count
    }

    func restore() throws {
        cachedKeyboards = []
        var journal = try loadJournal()
        guard !journal.originalCaps.isEmpty else {
            try saveJournal(journal)
            return
        }
        var firstError: Error?
        for keyboard in try keyboards() {
            guard let original = journal.originalCaps[keyboard.id] else { continue }
            do {
                let current = try keyboard.readMappings()
                let restored = try Self.restoring(in: current, originalCaps: original)
                if restored != current {
                    try keyboard.writeMappings(restored)
                }
                journal.originalCaps.removeValue(forKey: keyboard.id)
                try saveJournal(journal)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw firstError
        }
    }

    private static func validate(_ mappings: [Entry]) throws {
        guard mappings.allSatisfy({ $0[sourceKey] != nil && $0[destinationKey] != nil }) else {
            throw MappingError(
                message: "The keyboard has an invalid UserKeyMapping property. NoCaps left it unchanged."
            )
        }
    }

    private func keyboards() throws -> [Keyboard] {
        if let listKeyboards { return try listKeyboards() }
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            throw MappingError(
                message: "macOS did not provide access to keyboard services. Check NoCaps' permissions and reopen it."
            )
        }
        return try services.filter { IOHIDServiceClientConformsTo($0, 1, 6) != 0 }.map { service in
            guard let id = IOHIDServiceClientGetRegistryID(service) as? NSNumber else {
                throw MappingError(message: "macOS returned an invalid keyboard identifier. NoCaps left it unchanged.")
            }
            return Keyboard(
                id: id.stringValue,
                readMappings: { try Self.mappings(for: service) },
                writeMappings: { try Self.setMappings($0, for: service) }
            )
        }
    }

    private static func mappings(for service: IOHIDServiceClient) throws -> [Entry] {
        guard let property = IOHIDServiceClientCopyProperty(service, propertyKey) else { return [] }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: property, format: .binary, options: 0)
            let mappings = try PropertyListDecoder().decode([Entry].self, from: data)
            try Self.validate(mappings)
            return mappings
        } catch {
            throw MappingError(
                message: "The keyboard has an unreadable UserKeyMapping property. NoCaps left it unchanged."
            )
        }
    }

    private static func setMappings(_ mappings: [Entry], for service: IOHIDServiceClient) throws {
        guard IOHIDServiceClientSetProperty(service, propertyKey, mappings as CFArray) else {
            throw MappingError(
                message:
                    "macOS refused to update Caps Lock. NoCaps kept its recovery file; reopen it to restore the key."
            )
        }
        guard try Self.mappings(for: service) == mappings else {
            throw MappingError(
                message:
                    "The Caps Lock mapping could not be verified. NoCaps kept its recovery file; reopen it to restore the key."
            )
        }
    }

    private func loadJournal() throws -> Journal {
        let bootSession = try currentBootSession()
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return Journal(bootSession: bootSession) }
        do {
            let journal = try PropertyListDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
            guard journal.bootSession == bootSession else { return Journal(bootSession: bootSession) }
            for original in journal.originalCaps.values {
                try Self.validate(original)
                guard original.allSatisfy({ $0[Self.sourceKey] == Self.capsUsage }) else {
                    throw MappingError(message: "Invalid recovery entries.")
                }
            }
            return journal
        } catch {
            throw MappingError(
                message:
                    "NoCaps could not read its keyboard recovery file. Caps Lock was left unchanged. File: \(journalURL.path)"
            )
        }
    }

    private func saveJournal(_ journal: Journal) throws {
        if journal.originalCaps.isEmpty {
            if FileManager.default
                .fileExists(atPath: journalURL.path)
            {
                try FileManager.default.removeItem(at: journalURL)
            }
            return
        }
        try FileManager.default.createDirectory(
            at: journalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try PropertyListEncoder().encode(journal).write(to: journalURL, options: .atomic)
    }

    private func currentBootSession() throws -> String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 else {
            throw MappingError(
                message: "NoCaps could not identify this macOS boot session. Caps Lock was left unchanged."
            )
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else {
            throw MappingError(
                message: "NoCaps could not identify this macOS boot session. Caps Lock was left unchanged."
            )
        }
        return String(cString: bytes)
    }
}
