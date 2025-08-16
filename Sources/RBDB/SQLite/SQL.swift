public struct SQL {
	public let queryText: String
	public let arguments: [Any?]
	public let startIndex: Index

	public init(_ queryText: String, arguments: [Any?] = [], startIndex: Index? = nil) {
		self.queryText = queryText
		self.arguments = arguments
		self.startIndex = startIndex ?? Index(queryOffset: 0, argumentIndex: 0)
	}

	/// An opaque index that tracks position in both the query text and arguments array
	public struct Index: Sendable {
		/// Byte offset into the queryText (compatible with SQLite error offsets)
		let queryOffset: Int
		/// Index into the arguments array
		let argumentIndex: Int
	}

	/// Returns a copy of this SQL with the given startIndex
	public func at(startIndex: Index) -> SQL {
		SQL(queryText, arguments: arguments, startIndex: startIndex)
	}
}

extension SQL: ExpressibleByStringInterpolation {
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

		public mutating func appendInterpolation(_ value: Any?) {
			if let sql = value as? SQL {
				appendInterpolation(sql)
			} else {
				arguments.append(value)
				queryParts.append("?")
			}
		}

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
