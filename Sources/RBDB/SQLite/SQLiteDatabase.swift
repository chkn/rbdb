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
	public func query(sql: SQL) throws -> any Sequence<Row> {
		return try SQLiteCursor(db: db, sql: sql)
	}
}
