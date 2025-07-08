import Foundation
import SQLite3

enum SqliteError: Error {
	case couldNotOpenDatabase(String)
	case couldNotRegisterFunction(name: String)
	case queryOrExecuteError(String)
}

class SQLiteDatabase {
	private var db: OpaquePointer?

	init(path: String) throws {
		if sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
			let errmsg = String(cString: sqlite3_errmsg(db!))
			sqlite3_close(db)
			throw SqliteError.couldNotOpenDatabase(errmsg)
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
			throw SqliteError.couldNotRegisterFunction(name: "uuidv7")
		}
	}

	deinit {
		sqlite3_close(db)
	}

	func execute(_ sql: String) throws {
		var err: UnsafeMutablePointer<CChar>? = nil
		let result = sqlite3_exec(db, sql, nil, nil, &err)
		if result != SQLITE_OK {
			let errmsg = String(cString: err!)
			sqlite3_free(err)
			throw SqliteError.queryOrExecuteError(errmsg)
		}
	}

	func query(_ sql: String) throws -> [[String: Any]] {
		var statement: OpaquePointer?
		var results: [[String: Any]] = []
		guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
			let errmsg = String(cString: sqlite3_errmsg(db))
			throw SqliteError.queryOrExecuteError(errmsg)
		}

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

			results.append(row)
		}

		sqlite3_finalize(statement)
		return results
	}
}
