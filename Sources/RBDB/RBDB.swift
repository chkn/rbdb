import Foundation
import SQLite3

public class RBDB: SQLiteDatabase {
	private var isInitializing = false

	// FIXME: Can we validate that it's actually an RBDB?
	public override init(path: String) throws {
		try super.init(path: path)

		// Set flag to allow schema tables to be created during initialization
		isInitializing = true
		defer { isInitializing = false }

		// Migrate the schema
		try super.query(
			String(decoding: PackageResources.schema_sql, as: UTF8.self)
		)
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
	public override func query(_ sql: String, parameters: [Any?]) throws
		-> [[String: Any?]]
	{
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

	override func readRows(in statement: OpaquePointer) throws -> [[String:
		Any?]]
	{
		if !isInitializing {
			if let normalizedSQL = sqlite3_normalized_sql(statement) {
				let sqlString = String(cString: normalizedSQL)
				if sqlString.hasPrefix("CREATE TABLE") {
					try interceptCreateTable(sqlString)

					// Return empty result set instead of letting SQLite execute
					//  the CREATE TABLE
					return []
				}
			}
		}
		return try super.readRows(in: statement)
	}

	func interceptCreateTable(_ sql: String) throws {
		guard
			let createTable = try ParsedCreateTable(
				sql: sql
			)
		else {
			throw SQLiteError.queryError(
				"Cannot parse CREATE TABLE statement: \(sql)"
			)
		}
		let columnNamesJson = try String(
			data: JSONSerialization.data(
				withJSONObject: createTable.columnNames
			),
			encoding: .utf8
		)!

		try super.query("BEGIN TRANSACTION")
		do {
			// First create an entity record
			try super.query("INSERT INTO entity DEFAULT VALUES")

			// Insert into predicate table using the last inserted entity ID and jsonb function
			// Use INSERT OR IGNORE if IF NOT EXISTS was specified
			let orIgnore = createTable.ifNotExists ? "OR IGNORE " : ""
			try super.query(
				"""
					INSERT \(orIgnore)INTO predicate (internal_entity_id, name, column_names)
					VALUES (last_insert_rowid(), ?, jsonb(?))
				""",
				parameters: [createTable.tableName, columnNamesJson]
			)

			try super.query("COMMIT")
		} catch {
			try super.query("ROLLBACK")
			throw error
		}
	}

	private func rescue(error: SQLiteError) throws -> Bool {
		if case .queryError(let msg) = error,
			let match = msg.firstMatch(of: /no such table: ([^\s]+)/)
		{
			let createViewSQL =
				"CREATE TEMP VIEW IF NOT EXISTS \(match.1) AS SELECT 1 AS stub;"
			try super.query(createViewSQL)
			return true
		}
		return false
	}
}
