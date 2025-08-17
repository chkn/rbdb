/// A type-safe representation of SQL queries with parameter binding.
///
/// The `SQL` struct encapsulates a SQL query string along with its parameters,
/// providing compile-time safety through Swift's string interpolation system.
/// Parameters are automatically bound to `?` placeholders in the query.
///
/// ## Usage
///
/// ### String Interpolation (Recommended)
/// ```swift
/// let name = "Alice"
/// let age = 30
/// let sql: SQL = "INSERT INTO users (name, age) VALUES (\(name), \(age))"
/// ```
///
/// ### Direct Construction
/// ```swift
/// let sql = SQL("SELECT * FROM users WHERE age > ?", arguments: [25])
/// ```
///
/// ### Embedding SQL in SQL
/// ```swift
/// let subquery: SQL = "SELECT id FROM active_users WHERE age > \(minAge)"
/// let mainQuery: SQL = "DELETE FROM posts WHERE user_id IN (\(subquery))"
/// ```
public struct SQL {
	/// The SQL query text with `?` placeholders for parameters
	public let queryText: String

	/// The parameter values to bind to placeholders
	public let arguments: [Any?]

	/// The starting position for executing this SQL (used for error recovery)
	public let startIndex: Index

	/// Creates a new SQL query with optional parameters.
	///
	/// - Parameters:
	///   - queryText: The SQL query string with `?` placeholders
	///   - arguments: Parameter values to bind to placeholders
	///   - startIndex: Starting position (used internally for error recovery)
	public init(_ queryText: String, arguments: [Any?] = [], startIndex: Index? = nil) {
		self.queryText = queryText
		self.arguments = arguments
		self.startIndex = startIndex ?? Index(queryOffset: 0, argumentIndex: 0)
	}

	/// An opaque index that tracks position in both the query text and arguments array.
	///
	/// This is used internally for error recovery and multi-statement SQL execution.
	public struct Index: Sendable {
		/// Byte offset into the queryText (compatible with SQLite error offsets)
		let queryOffset: Int
		/// Index into the arguments array
		let argumentIndex: Int
	}

	/// Returns a copy of this SQL with the given startIndex.
	///
	/// This is used internally for error recovery to resume execution from a specific point.
	///
	/// - Parameter startIndex: The position to start execution from
	/// - Returns: A new SQL instance with the updated start position
	public func at(startIndex: Index) -> SQL {
		SQL(queryText, arguments: arguments, startIndex: startIndex)
	}
}

extension SQL: ExpressibleByStringInterpolation {
	/// String interpolation implementation for SQL queries.
	///
	/// This allows using Swift's string interpolation syntax to build SQL queries
	/// with automatic parameter binding. Values interpolated into the string
	/// become bound parameters, except for `SQL` instances which are inlined.
	public struct StringInterpolation: StringInterpolationProtocol {
		var queryParts: [String] = []
		var arguments: [Any?] = []

		public init(literalCapacity: Int, interpolationCount: Int) {
			queryParts.reserveCapacity(interpolationCount + 1)
			arguments.reserveCapacity(interpolationCount)
		}

		public mutating func appendLiteral(_ literal: String) {
			queryParts.append(literal)
		}

		/// Interpolates a value as a bound parameter.
		///
		/// If the value is an `SQL` instance, it's inlined directly into the query.
		/// Otherwise, the value becomes a bound parameter represented by `?`.
		///
		/// - Parameter value: The value to interpolate
		public mutating func appendInterpolation(_ value: Any?) {
			if let sql = value as? SQL {
				appendInterpolation(sql)
			} else {
				arguments.append(value)
				queryParts.append("?")
			}
		}

		/// Inlines another SQL query directly into this one.
		///
		/// The query text is inserted directly (not as a parameter), and all
		/// arguments from the nested SQL are added to this query's argument list.
		///
		/// - Parameter sql: The SQL query to inline
		public mutating func appendInterpolation(_ sql: SQL) {
			queryParts.append(sql.queryText)
			arguments.append(contentsOf: sql.arguments)
		}

		var sql: SQL {
			let queryText = queryParts.joined()
			return SQL(queryText, arguments: arguments)
		}
	}

	public init(stringInterpolation: StringInterpolation) {
		self = stringInterpolation.sql
	}

	public init(stringLiteral value: String) {
		self.init(value)
	}
}
