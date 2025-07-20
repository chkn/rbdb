import Foundation

struct ParsedCreateTable {
	let ifNotExists: Bool
	let tableName: String
	let columnNames: [String]

	init?(sql: String) throws {
		// Handle CREATE TABLE [IF NOT EXISTS] tableName (columns...)
		let pattern = #/^CREATE\s+TABLE(\s+IF\s+NOT\s+EXISTS)?\s*([^(]+?)\(/#
		guard let match = sql.firstMatch(of: pattern) else {
			return nil
		}

		// Check if IF NOT EXISTS was captured
		self.ifNotExists = match.1 != nil

		let rawTableName = String(match.2).trimmingCharacters(
			in: .whitespacesAndNewlines
		)
		self.tableName = rawTableName.trimmingCharacters(
			in: CharacterSet(charactersIn: "\"'`[]")
		)

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
		self.columnNames = try parseColumnNames(from: columnsDef)
	}

}

private func parseColumnNames(from columnsDef: String) throws -> [String] {
	var columnNames: [String] = []

	let columnDefs = StringParsing.split(columnsDef, by: ",")
	for columnDef in columnDefs {
		try processColumn(columnDef, into: &columnNames)
	}

	return columnNames
}

private func processColumn(
	_ columnDef: String,
	into columnNames: inout [String]
) throws {
	let trimmed = columnDef.trimmingCharacters(in: .whitespacesAndNewlines)

	// Skip table constraints like UNIQUE(name), FOREIGN KEY, etc.
	let upperTrimmed = trimmed.uppercased()
	if upperTrimmed.hasPrefix("UNIQUE(")
		|| upperTrimmed.hasPrefix("PRIMARY KEY")
		|| upperTrimmed.hasPrefix("FOREIGN KEY")
		|| upperTrimmed.hasPrefix("CHECK(")
		|| upperTrimmed.hasPrefix("CONSTRAINT")
	{
		return
	}

	// Extract column name (first word before space or type)
	if let columnName = trimmed.components(separatedBy: .whitespacesAndNewlines)
		.first
	{
		// Check for quoted column names and reject them
		if columnName.hasPrefix("\"") || columnName.hasPrefix("'")
			|| columnName.hasPrefix("`") || columnName.hasPrefix("[")
		{
			throw SQLiteError.queryError(
				"Quoted column names are not supported: \(columnName)"
			)
		}

		if !columnName.isEmpty {
			columnNames.append(columnName)
		}
	}
}
