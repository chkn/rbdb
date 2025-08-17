import Foundation
import SQLite3

/// Errors that can occur when working with SQLite databases.
public enum SQLiteError: Error {
	/// Failed to open the database at the specified path.
	case couldNotOpenDatabase(String)

	/// Failed to register a custom SQL function.
	case couldNotRegisterFunction(name: String)

	/// Parameter count mismatch between SQL placeholders and provided arguments.
	/// - Parameters:
	///   - expected: Number of parameters consumed by all statements
	///   - got: Number of arguments provided
	case queryParameterCount(expected: Int, got: Int)

	/// Error running a query. Gives an index in the SQL of the failing statement, if possible.
	/// - Parameters:
	///   - String: Error message from SQLite
	///   - index: Position in the SQL where the error occurred, if available
	case queryError(String, index: SQL.Index? = nil)
}

/// A Swift wrapper around SQLite with support for typed SQL queries and parameter binding.
///
/// This class provides a type-safe interface to SQLite databases using the `SQL` struct
/// for parameterized queries. It supports multi-statement SQL execution with proper
/// parameter binding and error recovery.
public class SQLiteDatabase {
	var db: OpaquePointer?

	/// Creates a new SQLite database connection.
	///
	/// Opens or creates a SQLite database at the specified path and registers
	/// custom functions like `uuidv7()`.
	///
	/// - Parameter path: The file system path to the database file, or ":memory:" for an in-memory database
	/// - Throws: `SQLiteError.couldNotOpenDatabase` if the database cannot be opened
	/// - Throws: `SQLiteError.couldNotRegisterFunction` if custom functions cannot be registered
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

	/// Executes one or more SQL statements with parameter binding.
	///
	/// This method supports multi-statement SQL execution with automatic parameter binding.
	/// Parameters are bound to `?` placeholders in the order they appear in the SQL text,
	/// distributed across all statements in the query.
	///
	/// - Parameter sql: The SQL query with embedded parameters
	/// - Returns: An array of dictionaries representing the result set from the last statement that produced results
	/// - Throws: `SQLiteError.queryParameterCount` if parameter count doesn't match placeholders
	/// - Throws: `SQLiteError.queryError` if SQL execution fails
	///
	/// ## Example
	/// ```swift
	/// let results = try db.query(sql: """
	///     INSERT INTO users (name, age) VALUES (\(name), \(age));
	///     SELECT * FROM users WHERE age > \(minAge)
	///     """)
	/// ```
	@discardableResult
	public func query(sql: SQL) throws -> [[String: Any?]] {
		return try sql.queryText.withCString { sqlCString in
			var finalResults: [[String: Any?]] = []
			var remainingSQL: UnsafePointer<CChar>? = sqlCString.advanced(
				by: sql.startIndex.queryOffset)

			let argumentCount = sql.arguments.count
			var argumentIndex = sql.startIndex.argumentIndex

			while let currentSQL = remainingSQL, currentSQL.pointee != 0 {
				var statement: OpaquePointer?

				guard
					sqlite3_prepare_v2(db, currentSQL, -1, &statement, &remainingSQL)
						== SQLITE_OK
				else {
					let errmsg = String(cString: sqlite3_errmsg(db))
					let failedOffset = currentSQL - sqlCString
					let failedIndex = SQL.Index(
						queryOffset: Int(failedOffset), argumentIndex: argumentIndex)
					throw SQLiteError.queryError(errmsg, index: failedIndex)
				}
				defer {
					sqlite3_finalize(statement)
				}

				// statement will be nil here (but sqlite3_prepare_v2 succeeded) if currentSQL is whitespace
				if let statement = statement {
					do {
						let expectedParams = Int(sqlite3_bind_parameter_count(statement))
						let availableParams = sql.arguments.count - argumentIndex
						if availableParams < expectedParams {
							argumentIndex += expectedParams
							continue
						}

						// Bind parameters for this statement
						for i in 0..<expectedParams {
							let parameterIndex = argumentIndex + i
							let parameter = sql.arguments[parameterIndex]
							let paramIndex = Int32(i + 1)  // SQLite parameters are 1-indexed

							switch parameter {
							case let stringValue as any StringProtocol:
								guard
									stringValue.withCString({ bindCStr in
										sqlite3_bind_text(
											statement,
											paramIndex,
											bindCStr,
											-1,
											unsafeBitCast(
												-1,
												to: sqlite3_destructor_type.self
											)  // SQLITE_TRANSIENT
										)
									}) == SQLITE_OK
								else {
									let errmsg = String(cString: sqlite3_errmsg(db))
									throw SQLiteError.queryError(
										"Failed to bind string parameter at index \(parameterIndex): \(errmsg)"
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
										"Failed to bind int parameter at index \(parameterIndex): \(errmsg)"
									)
								}
							case let int64Value as Int64:
								guard
									sqlite3_bind_int64(statement, paramIndex, int64Value)
										== SQLITE_OK
								else {
									let errmsg = String(cString: sqlite3_errmsg(db))
									throw SQLiteError.queryError(
										"Failed to bind int64 parameter at index \(parameterIndex): \(errmsg)"
									)
								}
							case let doubleValue as Double:
								guard
									sqlite3_bind_double(statement, paramIndex, doubleValue)
										== SQLITE_OK
								else {
									let errmsg = String(cString: sqlite3_errmsg(db))
									throw SQLiteError.queryError(
										"Failed to bind double parameter at index \(parameterIndex): \(errmsg)"
									)
								}
							case let dataValue as Data:
								let result = dataValue.withUnsafeBytes { bytes in
									sqlite3_bind_blob(
										statement,
										paramIndex,
										bytes.baseAddress,
										Int32(dataValue.count),
										// SQLITE_TRANSIENT
										unsafeBitCast(-1, to: sqlite3_destructor_type.self)
									)
								}
								guard result == SQLITE_OK else {
									let errmsg = String(cString: sqlite3_errmsg(db))
									throw SQLiteError.queryError(
										"Failed to bind data parameter at index \(parameterIndex): \(errmsg)"
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
										"Failed to bind UUIDv7 parameter at index \(parameterIndex): \(errmsg)"
									)
								}
							case nil, is NSNull:
								guard sqlite3_bind_null(statement, paramIndex) == SQLITE_OK
								else {
									let errmsg = String(cString: sqlite3_errmsg(db))
									throw SQLiteError.queryError(
										"Failed to bind null parameter at index \(parameterIndex): \(errmsg)"
									)
								}
							default:
								throw SQLiteError.queryError(
									"Unsupported parameter type at index \(parameterIndex): \(type(of: parameter))"
								)
							}
						}

						let statementResults = try readRows(in: statement)

						// Keep results from the last statement that produced results
						if !statementResults.isEmpty {
							finalResults = statementResults
						}

						// Advance argument index by the number of parameters consumed.
						//  Do this last to have the right `failedIndex` for retrying if
						//  `readRows` fails above.
						argumentIndex += expectedParams
					} catch {
						let failedOffset = currentSQL - sqlCString
						if case .queryError(let message, _) = error as? SQLiteError {
							let failedIndex = SQL.Index(
								queryOffset: Int(failedOffset), argumentIndex: argumentIndex)
							throw SQLiteError.queryError(message, index: failedIndex)
						}

						throw error
					}
				}
			}
			if argumentIndex != argumentCount {
				throw SQLiteError.queryParameterCount(
					expected: argumentIndex,
					got: argumentCount
				)
			}
			return finalResults
		}
	}

	/// Executes a prepared SQLite statement and extracts all result rows.
	///
	/// This method repeatedly calls `sqlite3_step` to iterate through all rows
	/// returned by the statement, converting SQLite values to Swift types.
	///
	/// - Parameter statement: A prepared SQLite statement
	/// - Returns: An array of dictionaries, where each dictionary represents a row with column names as keys
	/// - Throws: `SQLiteError.queryError` if statement execution fails
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
