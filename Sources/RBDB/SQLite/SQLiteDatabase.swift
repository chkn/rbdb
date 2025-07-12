import Foundation
import SQLite3

public enum SQLiteError: Error {
	case couldNotOpenDatabase(String)
	case couldNotRegisterFunction(name: String)
	case queryError(String)
}

public class SQLiteDatabase {
	private var db: OpaquePointer?

	public init(path: String) throws {
		if sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
			let errmsg = String(cString: sqlite3_errmsg(db!))
			sqlite3_close(db)
			throw SQLiteError.couldNotOpenDatabase(errmsg)
		}

		// Register the custom uuidv7() function
		let result = sqlite3_create_function(
				db,                   // Database connection
				"uuidv7",             // Function name
				0,                    // Number of arguments (0 for no arguments)
				SQLITE_UTF8 | SQLITE_INNOCUOUS,
				nil,                  // User data pointer (not needed)
				uuidv7SQLiteFunction, // Function implementation
				nil,                  // Step function (for aggregates)
				nil                   // Final function (for aggregates)
			)
		if result != SQLITE_OK {
			sqlite3_close(db)
			throw SQLiteError.couldNotRegisterFunction(name: "uuidv7")
		}
	}

	deinit {
		sqlite3_close(db)
	}

	public func query(_ sql: String) throws -> [[String: Any]] {
		return try sql.withCString { sqlCString in
			var finalResults: [[String: Any]] = []
			var remainingSQL: UnsafePointer<CChar>? = sqlCString

			while let currentSQL = remainingSQL, currentSQL.pointee != 0 {
				var statement: OpaquePointer?
				var nextSQL: UnsafePointer<CChar>?

				guard sqlite3_prepare_v2(db, currentSQL, -1, &statement, &nextSQL) == SQLITE_OK else {
					let errmsg = String(cString: sqlite3_errmsg(db))
					throw SQLiteError.queryError(errmsg)
				}

				// Execute the current statement
				var statementResults: [[String: Any]] = []
				let columnCount = sqlite3_column_count(statement)

				while sqlite3_step(statement) == SQLITE_ROW {
					var row: [String: Any] = [:]

					for i in 0..<columnCount {
						let columnName = String(cString: sqlite3_column_name(statement, i))
						let columnType = sqlite3_column_type(statement, i)

						switch columnType {
						case SQLITE_TEXT:
							let columnValue = String(cString: sqlite3_column_text(statement, i))
							row[columnName] = columnValue
						case SQLITE_BLOB:
							let blobPointer = sqlite3_column_blob(statement, i)
							let blobSize = sqlite3_column_bytes(statement, i)
							let blobData = Data(bytes: blobPointer!, count: Int(blobSize))
							row[columnName] = blobData
						case SQLITE_INTEGER:
							let intValue = sqlite3_column_int64(statement, i)
							row[columnName] = intValue
						case SQLITE_FLOAT:
							let doubleValue = sqlite3_column_double(statement, i)
							row[columnName] = doubleValue
						case SQLITE_NULL:
							row[columnName] = NSNull()
						default:
							row[columnName] = NSNull()
						}
					}

					statementResults.append(row)
				}

				// Finalize the current statement
				guard sqlite3_finalize(statement) == SQLITE_OK else {
					let errmsg = String(cString: sqlite3_errmsg(db))
					throw SQLiteError.queryError(errmsg)
				}

				// Keep results from the last statement that produced results
				if !statementResults.isEmpty {
					finalResults = statementResults
				}

				// Move to the next statement
				remainingSQL = nextSQL
			}
			return finalResults
		}
	}
}
