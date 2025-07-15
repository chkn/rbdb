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

	override func readRows(in statement: OpaquePointer) throws -> [[String: Any?]] {
		// Only intercept commands during normal operation, not during initialization
		if !isInitializing {
			if let normalizedSQL = sqlite3_normalized_sql(statement) {
				let sqlString = String(cString: normalizedSQL)
				if sqlString.hasPrefix("CREATE TABLE") {
					// Find the table name and column definitions manually
					guard let tableInfo = extractTableNameAndColumns(from: sqlString) else {
						throw SQLiteError.queryError("Cannot parse CREATE TABLE statement: \(sqlString)")
					}

					try handleCreateTable(name: tableInfo.tableName, columnsDef: tableInfo.columnsDef, ifNotExists: tableInfo.ifNotExists)

					// Return empty result set instead of executing the CREATE TABLE
					return []
				}
			}
		}
		return try super.readRows(in: statement)
	}

	func handleCreateTable(name: String, columnsDef: String, ifNotExists: Bool) throws {
		// Parse column definitions to extract column names
		let columnNames = try parseColumnNames(from: columnsDef)

		// Convert column names to JSON text
		let columnNamesJson = try String(data: JSONSerialization.data(withJSONObject: columnNames), encoding: .utf8)!

		// First create an entity record
		try super.query("INSERT INTO entity DEFAULT VALUES")

		// Insert into predicate table using the last inserted entity ID and jsonb function
		// Use INSERT OR IGNORE if IF NOT EXISTS was specified
		let orIgnore = ifNotExists ? "OR IGNORE " : ""
		try super.query("""
			INSERT \(orIgnore)INTO predicate (internal_entity_id, name, column_names)
			VALUES (last_insert_rowid(), ?, jsonb(?))
		""", parameters: [name, columnNamesJson])
	}

	private func parseColumnNames(from columnsDef: String) throws -> [String] {
		var columnNames: [String] = []

		// Split by comma, but be careful about commas inside parentheses (for types like DECIMAL(10,2))
		var parenDepth = 0
		var currentColumn = ""

		for char in columnsDef {
			switch char {
			case "(":
				parenDepth += 1
				currentColumn.append(char)
			case ")":
				parenDepth -= 1
				currentColumn.append(char)
			case ",":
				if parenDepth == 0 {
					// Process the current column
					try processColumn(currentColumn, into: &columnNames)
					currentColumn = ""
				} else {
					currentColumn.append(char)
				}
			default:
				currentColumn.append(char)
			}
		}

		// Handle the last column
		if !currentColumn.isEmpty {
			try processColumn(currentColumn, into: &columnNames)
		}

		return columnNames
	}

	private func processColumn(_ columnDef: String, into columnNames: inout [String]) throws {
		let trimmed = columnDef.trimmingCharacters(in: .whitespacesAndNewlines)

		// Skip table constraints like UNIQUE(name), FOREIGN KEY, etc.
		let upperTrimmed = trimmed.uppercased()
		if upperTrimmed.hasPrefix("UNIQUE(") ||
		   upperTrimmed.hasPrefix("PRIMARY KEY") ||
		   upperTrimmed.hasPrefix("FOREIGN KEY") ||
		   upperTrimmed.hasPrefix("CHECK(") ||
		   upperTrimmed.hasPrefix("CONSTRAINT") {
			return
		}

		// Extract column name (first word before space or type)
		if let columnName = trimmed.components(separatedBy: .whitespacesAndNewlines).first {
			// Check for quoted column names and reject them
			if columnName.hasPrefix("\"") || columnName.hasPrefix("'") ||
			   columnName.hasPrefix("`") || columnName.hasPrefix("[") {
				throw SQLiteError.queryError("Quoted column names are not supported: \(columnName)")
			}

			if !columnName.isEmpty {
				columnNames.append(columnName)
			}
		}
	}

	private func extractTableNameAndColumns(from sql: String) -> (tableName: String, columnsDef: String, ifNotExists: Bool)? {
		// Handle CREATE TABLE [IF NOT EXISTS] tableName (columns...)
		let pattern = #/^CREATE\s+TABLE(\s+IF\s+NOT\s+EXISTS)?\s*([^(]+?)\(/#
		guard let match = sql.firstMatch(of: pattern) else {
			return nil
		}

		// Check if IF NOT EXISTS was captured
		let ifNotExists = match.1 != nil

		let rawTableName = String(match.2).trimmingCharacters(in: .whitespacesAndNewlines)
		let tableName = rawTableName.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`[]"))

		// Find the opening parenthesis after the table name
		guard let openParenIndex = sql.firstIndex(of: "(") else { return nil }

		// Find the matching closing parenthesis, handling nested parentheses
		var parenDepth = 0
		var currentIndex = openParenIndex
		var closingParenIndex: String.Index?

		for char in sql[openParenIndex...] {
			if char == "(" {
				parenDepth += 1
			} else if char == ")" {
				parenDepth -= 1
				if parenDepth == 0 {
					closingParenIndex = currentIndex
					break
				}
			}
			currentIndex = sql.index(after: currentIndex)
		}

		guard let closeParenIndex = closingParenIndex else { return nil }

		// Extract the column definitions between the parentheses
		let startIndex = sql.index(after: openParenIndex)
		let columnsDef = String(sql[startIndex..<closeParenIndex])

		return (tableName: tableName, columnsDef: columnsDef, ifNotExists: ifNotExists)
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
