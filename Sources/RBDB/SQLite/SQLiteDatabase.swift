import Foundation
import SQLite3

public enum SQLiteError: Error {
	case couldNotOpenDatabase(String)
	case couldNotRegisterFunction(name: String)
	case queryParameterCount(expected: Int, got: Int)
	case queryError(String)
}

public class SQLiteDatabase {
	var db: OpaquePointer?

	public init(path: String) throws {
		if sqlite3_open_v2(
			path,
			&db,
			SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
			nil
		) != SQLITE_OK {
			let errmsg = String(cString: sqlite3_errmsg(db!))
			sqlite3_close(db)
			throw SQLiteError.couldNotOpenDatabase(errmsg)
		}

		// Register the custom uuidv7() function
		let result = sqlite3_create_function(
			db,  // Database connection
			"uuidv7",  // Function name
			0,  // Number of arguments (0 for no arguments)
			SQLITE_UTF8 | SQLITE_INNOCUOUS,
			nil,  // User data pointer (not needed)
			uuidv7SQLiteFunction,  // Function implementation
			nil,  // Step function (for aggregates)
			nil  // Final function (for aggregates)
		)
		if result != SQLITE_OK {
			sqlite3_close(db)
			throw SQLiteError.couldNotRegisterFunction(name: "uuidv7")
		}
	}

	deinit {
		sqlite3_close(db)
	}

	/// Runs one or more SQL statements, returning the result set from the last one.
	@discardableResult
	public func query(_ sql: String) throws -> [[String: Any?]] {
		return try sql.withCString { sqlCString in
			var finalResults: [[String: Any?]] = []
			var remainingSQL: UnsafePointer<CChar>? = sqlCString

			while let currentSQL = remainingSQL, currentSQL.pointee != 0 {
				var statement: OpaquePointer?
				var nextSQL: UnsafePointer<CChar>?

				guard
					sqlite3_prepare_v2(db, currentSQL, -1, &statement, &nextSQL)
						== SQLITE_OK
				else {
					let errmsg = String(cString: sqlite3_errmsg(db))
					throw SQLiteError.queryError(errmsg)
				}
				defer {
					sqlite3_finalize(statement)
				}

				// statement will be nil here (but sqlite3_prepare_v2 succeeded) if currentSQL is whitespace
				if let statement = statement {
					let statementResults = try readRows(in: statement)

					// Keep results from the last statement that produced results
					if !statementResults.isEmpty {
						finalResults = statementResults
					}
				}

				// Move to the next statement
				remainingSQL = nextSQL
			}
			return finalResults
		}
	}

	/// Runs a single parameterized SQL statement.
	@discardableResult
	public func query(_ sql: String, parameters: [Any?]) throws -> [[String:
		Any?]]
	{
		return try sql.withCString { sqlCString in
			var statement: OpaquePointer?

			guard
				sqlite3_prepare_v2(db, sqlCString, -1, &statement, nil)
					== SQLITE_OK
			else {
				let errmsg = String(cString: sqlite3_errmsg(db))
				throw SQLiteError.queryError(errmsg)
			}
			defer {
				sqlite3_finalize(statement)
			}
			guard let statement = statement else { return [] }

			// Check parameter count
			let expectedParams = Int(sqlite3_bind_parameter_count(statement))
			guard parameters.count == expectedParams else {
				throw SQLiteError.queryParameterCount(
					expected: expectedParams,
					got: parameters.count
				)
			}

			// Bind parameters
			for (index, parameter) in parameters.enumerated() {
				let paramIndex = Int32(index + 1)  // SQLite parameters are 1-indexed

				switch parameter {
				case let stringValue as any StringProtocol:
					guard
						stringValue.withCString({ bindCStr in
							sqlite3_bind_text(
								statement,
								paramIndex,
								bindCStr,
								-1,
								unsafeBitCast(-1, to: sqlite3_destructor_type.self) // SQLITE_TRANSIENT
							)
						}) == SQLITE_OK
					else {
						let errmsg = String(cString: sqlite3_errmsg(db))
						throw SQLiteError.queryError(
							"Failed to bind string parameter at index \(index): \(errmsg)"
						)
					}
				case let intValue as Int:
					guard
						sqlite3_bind_int64(
							statement,
							paramIndex,
							Int64(intValue)
						) == SQLITE_OK
					else {
						let errmsg = String(cString: sqlite3_errmsg(db))
						throw SQLiteError.queryError(
							"Failed to bind int parameter at index \(index): \(errmsg)"
						)
					}
				case let int64Value as Int64:
					guard
						sqlite3_bind_int64(statement, paramIndex, int64Value)
							== SQLITE_OK
					else {
						let errmsg = String(cString: sqlite3_errmsg(db))
						throw SQLiteError.queryError(
							"Failed to bind int64 parameter at index \(index): \(errmsg)"
						)
					}
				case let doubleValue as Double:
					guard
						sqlite3_bind_double(statement, paramIndex, doubleValue)
							== SQLITE_OK
					else {
						let errmsg = String(cString: sqlite3_errmsg(db))
						throw SQLiteError.queryError(
							"Failed to bind double parameter at index \(index): \(errmsg)"
						)
					}
				case let dataValue as Data:
					let result = dataValue.withUnsafeBytes { bytes in
						sqlite3_bind_blob(
							statement,
							paramIndex,
							bytes.baseAddress,
							Int32(dataValue.count),
							unsafeBitCast(-1, to: sqlite3_destructor_type.self) // SQLITE_TRANSIENT
						)
					}
					guard result == SQLITE_OK else {
						let errmsg = String(cString: sqlite3_errmsg(db))
						throw SQLiteError.queryError(
							"Failed to bind data parameter at index \(index): \(errmsg)"
						)
					}
				case let uuidValue as UUIDv7:
					let result = uuidValue.withUnsafeBytes { bytes in
						sqlite3_bind_blob(
							statement,
							paramIndex,
							bytes.baseAddress,
							Int32(bytes.count),
							unsafeBitCast(-1, to: sqlite3_destructor_type.self)
						)
					}
					guard result == SQLITE_OK else {
						let errmsg = String(cString: sqlite3_errmsg(db))
						throw SQLiteError.queryError(
							"Failed to bind UUIDv7 parameter at index \(index): \(errmsg)"
						)
					}
				case nil, is NSNull:
					guard sqlite3_bind_null(statement, paramIndex) == SQLITE_OK
					else {
						let errmsg = String(cString: sqlite3_errmsg(db))
						throw SQLiteError.queryError(
							"Failed to bind null parameter at index \(index): \(errmsg)"
						)
					}
				default:
					throw SQLiteError.queryError(
						"Unsupported parameter type at index \(index): \(type(of: parameter))"
					)
				}
			}

			return try readRows(in: statement)
		}
	}

	/// Loops running `sqlite3_step` and extracting the row values.
	func readRows(in statement: OpaquePointer) throws -> [[String: Any?]] {
		var statementResults: [[String: Any?]] = []
		while true {
			let stepResult = sqlite3_step(statement)
			if stepResult == SQLITE_ROW {
				var row: [String: Any?] = [:]
				let columnCount = sqlite3_column_count(statement)
				for i in 0..<columnCount {
					let columnName = String(
						cString: sqlite3_column_name(statement, i)
					)
					let columnType = sqlite3_column_type(statement, i)
					switch columnType {
					case SQLITE_TEXT:
						let columnValue = String(
							cString: sqlite3_column_text(statement, i)
						)
						row[columnName] = columnValue
					case SQLITE_BLOB:
						let blobPointer = sqlite3_column_blob(statement, i)
						let blobSize = sqlite3_column_bytes(statement, i)
						let blobData = Data(
							bytes: blobPointer!,
							count: Int(blobSize)
						)
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
						throw SQLiteError.queryError(
							"Unexpected column type in result set: \(columnType)"
						)
					}
				}
				statementResults.append(row)
			} else if stepResult == SQLITE_DONE {
				break
			} else {
				let errmsg = String(
					cString: sqlite3_errmsg(sqlite3_db_handle(statement))
				)
				throw SQLiteError.queryError("sqlite3_step failed: \(errmsg)")
			}
		}
		return statementResults
	}
}

