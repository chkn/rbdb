import Foundation

public class RBDB: SQLiteDatabase {

	// FIXME: Can we validate that it's actually an RBDB?
	public override init(path: String) throws {
		try super.init(path: path)

		// Migrate the schema
		try super.query(String(decoding: PackageResources.schema_sql, as: UTF8.self))
	}

	@discardableResult
	public override func query(_ sql: String) throws -> [[String: Any?]] {
		do {
			return try super.query(sql)
		} catch let error as SQLiteError {
			if try rescue(error: error) {
				// Now try the original query again
				return try super.query(sql)
			}
			throw error
		}
	}

	@discardableResult
	public override func query(_ sql: String, parameters: [Any?]) throws -> [[String: Any?]] {
		do {
			return try super.query(sql, parameters: parameters)
		} catch let error as SQLiteError {
			if try rescue(error: error) {
				// Now try the original query again
				return try super.query(sql, parameters: parameters)
			}
			throw error
		}
	}

	private func rescue(error: SQLiteError) throws -> Bool {
		if case let .queryError(msg) = error, let match = msg.firstMatch(of: /no such table: ([^\s]+)/) {
			let createViewSQL = "CREATE TEMP VIEW IF NOT EXISTS \(match.1) AS SELECT 1 AS stub;"
			try super.query(createViewSQL)
			return true
		}
		return false
	}
}
