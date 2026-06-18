import Foundation
import GRDB

/// Append-only local store of surfer counts. Persists every sample and computes
/// per-spot weekday×hour medians that give the UI its "emptier/busier than
/// usual" baseline.
final class HistoryStore {
    private let dbQueue: DatabaseQueue

    init(inMemory: Bool = false) throws {
        if inMemory {
            dbQueue = try DatabaseQueue()
        } else {
            let dir = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true
            ).appendingPathComponent("Swell", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dbQueue = try DatabaseQueue(path: dir.appendingPathComponent("history.sqlite").path)
        }
        try migrate()
    }

    private func migrate() throws {
        try dbQueue.write { db in
            try db.create(table: "sample", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("rowid")
                t.column("spotID", .text).notNull().indexed()
                t.column("timestamp", .datetime).notNull()
                t.column("count", .integer)            // nullable: nil = no reading
                t.column("confidence", .double).notNull()
            }
        }
    }

    func append(_ s: Sample) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sample (spotID, timestamp, count, confidence)
                VALUES (?, ?, ?, ?)
                """, arguments: [s.spotID, s.timestamp, s.count, s.confidence])
        }
    }

    func latest(spotID: String) throws -> Sample? {
        try dbQueue.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT spotID, timestamp, count, confidence FROM sample
                WHERE spotID = ? ORDER BY timestamp DESC LIMIT 1
                """, arguments: [spotID])
            guard let row else { return nil }
            return Sample(spotID: row["spotID"], timestamp: row["timestamp"],
                          count: row["count"], confidence: row["confidence"])
        }
    }

    /// Median surfer count for this spot at the same weekday and hour, across all
    /// history. Returns nil if no comparable samples exist.
    func typicalCount(spotID: String, for date: Date,
                      calendar: Calendar = .current) throws -> Double? {
        let weekday = calendar.component(.weekday, from: date)
        let hour = calendar.component(.hour, from: date)
        let counts: [Int] = try dbQueue.read { db in
            try Int.fetchAll(db, sql: """
                SELECT count FROM sample
                WHERE spotID = ? AND count IS NOT NULL
                  AND CAST(strftime('%w', timestamp) AS INTEGER) = ?
                  AND CAST(strftime('%H', timestamp) AS INTEGER) = ?
                """, arguments: [spotID, weekday - 1, hour])  // strftime %w is 0=Sunday
        }
        return median(counts)
    }
}
