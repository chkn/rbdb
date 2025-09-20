fileprivate typealias SQLExpression = String

fileprivate struct SQLTable {
	var name: String
	var alias: String?
	var conditions: [SQLExpression] = []

	var effectiveName: String {
		alias ?? name
	}
}

fileprivate struct SQLSelect {
	var select: [SQLExpression]
	var fromTables: [SQLTable]
	static var empty: SQLSelect { SQLSelect(select: [], fromTables: []) }

	var sql: String {
		var result = "SELECT \(select.joined(separator: ", "))"

		if let t1 = fromTables.first {
			if let alias = t1.alias {
				result += " FROM [\(t1.name)] AS [\(alias)]"
			} else {
				result += " FROM [\(t1.name)]"
			}

			for t2 in fromTables.dropFirst() {
				if let alias = t2.alias {
					result +=
						" JOIN [\(t2.name)] AS [\(alias)] ON \(t2.conditions.joined(separator: " AND "))"
				} else {
					result += " JOIN [\(t2.name)] ON \(t2.conditions.joined(separator: " AND "))"
				}
			}

			if !t1.conditions.isEmpty {
				result += " WHERE \(t1.conditions.joined(separator: " AND "))"
			}
		}

		return result
	}
}

fileprivate struct RuleIntoSQLReducer: SymbolReducer {
	let getColumnNames: (_ predicateName: String) throws -> [String]

	struct SQLVarRef {
		var srcTableName: String
		var srcColumnName: String
	}

	// Must be a valid, canonical formula (e.g. passes `validate` and has had `canonicalize` called)
	func reduce(_ prev: SQLSelect, _ formula: Formula) throws -> SQLSelect {
		var sql = prev
		switch formula {
		case .hornClause(positive: let positive, negative: let negatives):
			var cols: [Var: SQLVarRef] = [:]
			var tableNameCounts: [String: Int] = [:]

			// Process each predicate in the body
			for (index, predicate) in negatives.enumerated() {
				// Create unique table alias for duplicate table names
				let count = tableNameCounts[predicate.name, default: 0]
				tableNameCounts[predicate.name] = count + 1

				let alias = count > 0 ? "\(predicate.name)\(count)" : nil
				let table = SQLTable(name: predicate.name, alias: alias)
				sql.fromTables.append(table)

				let columnNames = try getColumnNames(predicate.name)

				for (i, term) in predicate.arguments.enumerated() {
					// FIXME: I think other types of terms need to go into the WHERE clause
					guard case .variable(let v) = term else { continue }

					// If this variable was seen before, create a join condition
					if let existingRef = cols[v] {
						// This variable appears in multiple tables - create join condition
						let condition =
							"[\(existingRef.srcTableName)].\(existingRef.srcColumnName) = [\(table.effectiveName)].\(columnNames[i])"
						sql.fromTables[index].conditions.append(condition)
					} else {
						// First occurrence of this variable
						cols[v] = SQLVarRef(
							srcTableName: table.effectiveName,
							srcColumnName: columnNames[i]
						)
					}
				}
			}

			// Generate SELECT clause based on the head predicate
			let columnNames = try getColumnNames(positive.name)
			for (i, term) in positive.arguments.enumerated() {
				var value: SQLExpression
				switch term {
				case .boolean(let b): value = b ? "true" : "false"
				case .number(let n): value = String(n)
				case .string(let s): value = s
				case .variable(let v):
					guard let col = cols[v] else {
						preconditionFailure("All terms in the head must also appear in the body")
					}
					value = "[\(col.srcTableName)].\(col.srcColumnName)"
				}
				sql.select.append("\(value) AS \(columnNames[i])")
			}
		}
		return sql
	}
}

fileprivate struct QueryIntoSQLReducer: SymbolReducer {
	let getColumnNames: (_ predicateName: String) throws -> [String]

	func reduce(_ prev: SQLSelect, _ formula: Formula) throws -> SQLSelect {
		var sql = prev
		switch formula {
		case .hornClause(positive: let predicate, negative: let negatives):
			// For queries, we don't allow negative literals for now
			guard negatives.isEmpty else {
				throw SQLiteError.queryError("Queries with negative literals are not supported")
			}

			var table = SQLTable(name: predicate.name, alias: nil)
			let columnNames = try getColumnNames(predicate.name)

			// Process arguments to build variable mappings and WHERE conditions for constants
			for (i, term) in predicate.arguments.enumerated() {
				switch term {
				case .variable(let v):
					// Variables become part of the result set
					// FIXME: Prevent SQL injection via variable name
					sql.select.append("[\(table.effectiveName)].\(columnNames[i]) AS [\(v)]")
				case .boolean(let b):
					let value = b ? "true" : "false"
					table.conditions.append("[\(table.effectiveName)].\(columnNames[i]) = \(value)")
				case .number(let n):
					table.conditions.append("[\(table.effectiveName)].\(columnNames[i]) = \(n)")
				case .string(let s):
					// FIXME: Prevent SQL injection
					table.conditions.append("[\(table.effectiveName)].\(columnNames[i]) = '\(s)'")
				}
			}

			if sql.select.isEmpty {
				sql.select.append("true as sat")
			}
			sql.fromTables.append(table)
		}
		return sql
	}
}

extension Symbol {
	func ruleIntoSQL(_ getColumnNames: @escaping (_ predicateName: String) throws -> [String])
		throws
		-> String
	{
		try reduce(.empty, RuleIntoSQLReducer(getColumnNames: getColumnNames)).sql
	}

	func queryIntoSQL(_ getColumnNames: @escaping (_ predicateName: String) throws -> [String])
		throws
		-> String
	{
		try reduce(.empty, QueryIntoSQLReducer(getColumnNames: getColumnNames)).sql
	}
}
