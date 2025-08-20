import Foundation
import SQLite3

public typealias Row = [String: Any?]

/// A cursor for lazily iterating over SQL query results.
///
/// `SQLiteCursor`  supports multi-statement SQL.
/// All statements, except for the last, are completely exhausted in
/// the initializer, and the first row of the last statement is retrieved.
/// This is to try and throw any errors, as the rest of the iteration cannot
/// throw and any errors will be fatal.
class SQLiteCursor: Sequence, IteratorProtocol {
	private var statements: [OpaquePointer] = []
	private var finalStatement: OpaquePointer?
	private var nextRow: Row?

	internal init(db: OpaquePointer?, sql: SQL) throws {
		try sql.queryText.withCString { sqlCString in
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

				// statement will be nil here (but sqlite3_prepare_v2 succeeded) if currentSQL is whitespace
				if let statement = statement {
					statements.append(statement)
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

						// If there are more statements, step through this one
						if let remainingSQL = remainingSQL, remainingSQL.pointee != 0 {
							while try step(statement: statement) {
								// loop
							}
						} else {
							finalStatement = statement
							nextRow = try readRow(in: statement)
						}

						// Advance argument index by the number of parameters consumed.
						//  Do this last to have the right `failedIndex` for retrying if
						//  something fails above.
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
		}
	}

	deinit {
		for statement in statements {
			sqlite3_finalize(statement)
		}
	}

	public func next() -> Row? {
		if let currentRow = nextRow, let stmt = finalStatement {
			nextRow = try! readRow(in: stmt)
			return currentRow
		}
		return nil
	}

	func step(statement: OpaquePointer) throws -> Bool {
		switch sqlite3_step(statement) {
		case SQLITE_ROW:
			return true
		case SQLITE_DONE:
			return false
		default:
			let errmsg = String(
				cString: sqlite3_errmsg(sqlite3_db_handle(statement))
			)
			throw SQLiteError.queryError("sqlite3_step failed: \(errmsg)")
		}
	}

	/// Executes a prepared SQLite statement and returns the next row.
	///
	/// This method  calls `sqlite3_step` and converts SQLite values to Swift types.
	///
	/// - Parameter statement: A prepared SQLite statement
	/// - Returns: A  dictionary that represents a row with column names as keys, or `nil` if the query is exhausted.
	/// - Throws: `SQLiteError.queryError` if statement execution fails
	func readRow(in statement: OpaquePointer) throws -> Row? {
		if try step(statement: statement) {
			var row: Row = [:]
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
			return row
		}
		return nil
	}
}
