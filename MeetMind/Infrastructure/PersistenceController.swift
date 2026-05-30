//
//  PersistenceController.swift
//  MeetMind
//
//  Responsible for: ModelContainer creation, backup on schema error,
//  multi-tiered recovery, and surfacing diagnostic state to the UI.
//  MeetMindApp is NOT responsible for any of this logic.
//

import SwiftData
import Foundation

// MARK: - PersistenceController

/// Manages the SwiftData `ModelContainer` lifecycle, including schema-error
/// recovery and automatic backup creation.
///
/// Usage:
/// ```swift
/// let pc = PersistenceController.shared
/// // pc.container — use in .modelContainer(...)
/// // pc.initializationError — non-nil when a recovery was performed
/// // pc.isBackupCreated — true when corrupt files were copied to Backups/
/// ```
final class PersistenceController {

    // MARK: - Shared Instance

    static let shared = PersistenceController()

    // MARK: - Public State

    /// The ready-to-use `ModelContainer`. Never nil — falls back to in-memory
    /// if on-disk creation fails twice.
    let container: ModelContainer

    /// Non-nil when the app performed a recovery (schema conflict, corruption).
    /// The value is the original error description for display in the UI.
    private(set) var initializationError: String?

    /// `true` when corrupt store files were successfully backed up before reset.
    private(set) var isBackupCreated: Bool = false

    // MARK: - Schema

    private static let schema = Schema([
        Meeting.self,
        SpeakerProfile.self,
        TranscriptSegment.self,
        ActionItem.self,
        Decision.self,
        MeetingGroup.self,
        VectorEmbeddingEntity.self,
        GroupChatMessageEntity.self,
        GroupChatSessionEntity.self,
        ChildEmbeddingEntity.self
    ])

    private static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "MeetMind.store")
    }

    private static let storeFilenames = [
        "MeetMind.store",
        "MeetMind.store-wal",
        "MeetMind.store-shm"
    ]

    // MARK: - Init

    private init() {
        AppLogger.info("SwiftData Store URL: \(Self.storeURL.path)")

        let config = ModelConfiguration(
            schema: Self.schema,
            url: Self.storeURL
        )

        // Attempt 1: normal on-disk open
        if let container = try? ModelContainer(for: Self.schema, configurations: [config]) {
            self.container = container
            return
        }

        // On-disk open failed — back up files and try a clean store
        AppLogger.error("Primary ModelContainer creation failed — attempting recovery")
        let (backupDone, originalError) = Self.backupStoreFiles()
        self.isBackupCreated = backupDone
        self.initializationError = originalError

        Self.deleteStoreFiles()

        // Attempt 2: fresh on-disk store after reset
        if let container = try? ModelContainer(for: Self.schema, configurations: [config]) {
            AppLogger.info("Recovery succeeded — fresh on-disk store created")
            self.container = container
            return
        }

        // Attempt 3: in-memory fallback so the app stays alive
        AppLogger.error("Second on-disk attempt failed — falling back to in-memory store")
        let inMemoryConfig = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)

        guard let container = try? ModelContainer(for: Self.schema, configurations: [inMemoryConfig]) else {
            // This is a framework-level failure — no sane fallback exists.
            // In production this should never happen; log extensively before dying.
            AppLogger.error("CRITICAL: In-memory ModelContainer also failed. App cannot continue.")
            fatalError("""
                PersistenceController: All three ModelContainer creation attempts failed.
                Schema: \(Self.schema)
                This indicates a SwiftData framework bug or a corrupted binary.
                """)
        }

        self.initializationError = (initializationError ?? "") +
            " (Critical: running in temporary in-memory mode — data will not be saved)"
        self.container = container
        AppLogger.error("Running in in-memory fallback mode")
    }

    // MARK: - Private Helpers

    /// Copies all store-related files to a timestamped `Backups/` folder.
    /// - Returns: `(backupSucceeded, originalErrorDescription)`
    @discardableResult
    private static func backupStoreFiles() -> (Bool, String?) {
        let fm = FileManager.default
        let timestamp = Int(Date().timeIntervalSince1970)
        let backupFolder = URL.applicationSupportDirectory.appending(path: "Backups")

        var backupDone = false
        try? fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)

        for filename in storeFilenames {
            let src = URL.applicationSupportDirectory.appending(path: filename)
            guard fm.fileExists(atPath: src.path) else { continue }

            let dst = backupFolder.appending(path: "\(filename).backup-\(timestamp)")
            do {
                try fm.copyItem(at: src, to: dst)
                AppLogger.info("Backed up \(filename) → \(dst.lastPathComponent)")
                backupDone = true
            } catch {
                AppLogger.error("Failed to back up \(filename): \(error)")
            }
        }
        return (backupDone, backupDone ? "Store files backed up to Backups/" : nil)
    }

    /// Removes all store files to allow a fresh creation.
    private static func deleteStoreFiles() {
        let fm = FileManager.default
        for filename in storeFilenames {
            let url = URL.applicationSupportDirectory.appending(path: filename)
            try? fm.removeItem(at: url)
        }
        AppLogger.info("Deleted store files for clean reset")
    }
}
