import Foundation
import SQLite3

/// Liest die neueste empfangene Nachricht. Braucht vollen Festplattenzugriff.
enum MessagesDatabase {
    static func latestIncomingRowID() -> Int64? {
        let path = NSHomeDirectory() + "/Library/Messages/chat.db"
        var database: OpaquePointer?
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return nil
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT MAX(ROWID) FROM message WHERE is_from_me = 0", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }
}

/// Fragt periodisch einen Zähler ab und meldet, wenn er steigt.
final class CounterWatcher<Value: Comparable & Sendable>: @unchecked Sendable {
    private let interval: TimeInterval
    private let read: @Sendable () -> Value?
    private let onChange: @Sendable (_ readable: Bool, _ increased: Bool) -> Void
    private var timer: DispatchSourceTimer?
    private var last: Value?

    init(
        interval: TimeInterval,
        read: @escaping @Sendable () -> Value?,
        onChange: @escaping @Sendable (_ readable: Bool, _ increased: Bool) -> Void
    ) {
        self.interval = interval
        self.read = read
        self.onChange = onChange
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: interval, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
        last = nil
    }

    private func poll() {
        guard let value = read() else {
            onChange(false, false)
            return
        }
        let increased = last.map { value > $0 } ?? false
        last = value
        onChange(true, increased)
    }
}
