import Foundation

// MARK: - Unified Application Storage & Atomic Writes
enum AppPaths {
    static let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("CustomER", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let legacyDir: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("tututodoWidget", isDirectory: true)
    }()

    static func file(_ name: String) -> URL {
        appSupportDir.appendingPathComponent(name)
    }

    static func writeAtomically(_ data: Data, to url: URL, privatePermissions: Bool = false) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            if privatePermissions {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
        } catch {
            // Best-effort persistence
        }
    }

    /// One-time seamless migration of data files from the legacy `tututodoWidget` folder.
    /// Copies missing files or newer versions without deleting the legacy backup.
    static func migrateLegacyDataIfNeeded() {
        let marker = appSupportDir.appendingPathComponent(".migrated_v2")
        let fm = FileManager.default
        guard !fm.fileExists(atPath: marker.path), fm.fileExists(atPath: legacyDir.path) else { return }

        let knownFiles = [
            "reminders.json",
            "recurring_habits.json",
            "calendar_events.json",
            "positions.json"
        ]

        for name in knownFiles {
            let src = legacyDir.appendingPathComponent(name)
            let dst = appSupportDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }

            var shouldCopy = !fm.fileExists(atPath: dst.path)
            if !shouldCopy,
               let srcAttr = try? fm.attributesOfItem(atPath: src.path),
               let dstAttr = try? fm.attributesOfItem(atPath: dst.path),
               let srcDate = srcAttr[.modificationDate] as? Date,
               let dstDate = dstAttr[.modificationDate] as? Date,
               srcDate > dstDate {
                shouldCopy = true
            }

            if shouldCopy, let data = try? Data(contentsOf: src) {
                writeAtomically(data, to: dst)
            }
        }

        writeAtomically(Data("ok".utf8), to: marker)
    }
}
