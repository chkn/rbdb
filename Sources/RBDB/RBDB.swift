import Foundation
import SQLite3

public enum RBDBError: Error {
	case corruptData(message: String)
}

public class RBDB: SQLiteDatabase {
	private var isInitializing = false

	// FIXME: Can we validate that it's actually an RBDB?
	public override init(path: String) throws {
		try super.init(path: path)

		// Set flag to allow schema tables to be created during initialization
		isInitializing = true
		defer { isInitializing = false }

		// Register the custom predicate_formula() function
		let result = sqlite3_create_function(
			db,  // Database connection
			"predicate_formula",  // Function name
			-1,  // Number of arguments (-1 for var args)
			SQLITE_UTF8 | SQLITE_DETERMINISTIC,
			nil,  // User data pointer (not needed)
			predicateFormulaSQLiteFunction,  // Function implementation
			nil,  // Step function (for aggregates)
			nil  // Final function (for aggregates)
		)
		if result != SQLITE_OK {
			sqlite3_close(db)
			throw SQLiteError.couldNotRegisterFunction(
				name: "predicate_formula"
			)
		}

		// Migrate the schema
		try super.query(
			String(decoding: PackageResources.schema_sql, as: UTF8.self)
		)
	}

	@discardableResult
	public override func query(_ sql: String) throws -> [[String: Any?]] {
		do {
			return try super.query(sql)
		} catch let error as SQLiteError {
			if try rescue(error: error) {
				// Now try the original query again
				return try super.query(sql)
			}
			throw error
		}
	}

	@discardableResult
	public override func query(_ sql: String, parameters: [Any?]) throws
		-> [[String: Any?]]
	{
		do {
			return try super.query(sql, parameters: parameters)
		} catch let error as SQLiteError {
			if try rescue(error: error) {
				// Now try the original query again
				return try super.query(sql, parameters: parameters)
			}
			throw error
		}
	}

	public func assert(formula: Formula) throws {
		let jsonStr = try formulaToJSON(formula)

		try super.query("BEGIN TRANSACTION")
		do {
			for (sql, parameters) in sqlForInsert(
				ofFormula: jsonStr,
				usingParameters: true
			) {
				try super.query(
					sql,
					parameters: parameters
				)
			}
			try super.query("COMMIT")
		} catch {
			try super.query("ROLLBACK")
			throw error
		}
	}

	private func sqlForInsert(ofFormula expr: String, usingParameters: Bool)
		-> [(
			String, parameters: [Any?]
		)]
	{
		[
			(
				// Can't use DEFAULT VALUES in a trigger context
				"INSERT INTO _entity (internal_entity_id) VALUES (NULL)",
				parameters: []
			),
			(
				"""
				INSERT INTO _rule (internal_entity_id, formula)
				VALUES (last_insert_rowid(), jsonb(\(usingParameters ? "?" : expr)))
				""",
				parameters: usingParameters ? [expr] : []
			),
		]
	}

	override func readRows(in statement: OpaquePointer) throws -> [[String:
		Any?]]
	{
		if !isInitializing {
			if let normalizedSQL = sqlite3_normalized_sql(statement) {
				let sqlString = String(cString: normalizedSQL)
				if sqlString.hasPrefix("CREATE TABLE") {
					try interceptCreateTable(sqlString)

					// Return empty result set instead of letting SQLite execute
					//  the CREATE TABLE
					return []
				}
			}
		}
		return try super.readRows(in: statement)
	}

	func interceptCreateTable(_ sql: String) throws {
		guard
			let createTable = try ParsedCreateTable(
				sql: sql
			)
		else {
			throw SQLiteError.queryError(
				"Cannot parse CREATE TABLE statement: \(sql)"
			)
		}
		let columnNamesJson = try String(
			data: JSONSerialization.data(
				withJSONObject: createTable.columnNames
			),
			encoding: .utf8
		)!

		try super.query("BEGIN TRANSACTION")
		do {
			try super.query("INSERT INTO _entity DEFAULT VALUES")

			// Insert into predicate table using the last inserted entity ID and jsonb function
			// Use INSERT OR IGNORE if IF NOT EXISTS was specified
			let orIgnore = createTable.ifNotExists ? "OR IGNORE " : ""
			try super.query(
				"""
					INSERT \(orIgnore)INTO _predicate (internal_entity_id, name, column_names)
					VALUES (last_insert_rowid(), ?, jsonb(?))
				""",
				parameters: [createTable.tableName, columnNamesJson]
			)

			try super.query("COMMIT")
			
			// Immediately create the view and trigger so the table is usable
			try createViewAndTrigger(for: createTable.tableName, columns: createTable.columnNames)
		} catch {
			try super.query("ROLLBACK")
			throw error
		}
	}

	private func createViewAndTrigger(for tableName: String, columns: [String]) throws {
		let columnList = columns.map { "[\($0)]" }.joined(separator: ", ")
		var selectList: [String] = []
		selectList.reserveCapacity(columns.count)
		for i in 1...columns.count {
			// We're selecting WHERE output_type is a predicate formula,
			//  so all its parameters should be constants (we don't allow free vars)
			selectList.append("json_extract(formula, '$[\(i)].\"\"')")
		}
		let createViewSQL =
			"""
			CREATE TEMP VIEW IF NOT EXISTS \(tableName) (\(columnList)) AS
			SELECT \(selectList.joined(separator: ", ")) FROM _rule WHERE output_type = '@\(tableName)'
			"""
		try super.query(createViewSQL)

		// Create INSTEAD OF INSERT trigger
		let predicateFormulaCall =
			"predicate_formula('\(tableName)', "
			+ columns.map { "NEW.[\($0)]" }.joined(separator: ", ")
			+ ")"

		let insertStatements = sqlForInsert(
			ofFormula: predicateFormulaCall,
			usingParameters: false
		)
		let triggerBody = insertStatements.map { $0.0 }.joined(separator: ";")

		let createTriggerSQL =
			"""
			CREATE TEMP TRIGGER IF NOT EXISTS \(tableName)_insert_trigger
			INSTEAD OF INSERT ON \(tableName)
			FOR EACH ROW
			BEGIN
				\(triggerBody);
			END
			"""
		try super.query(createTriggerSQL)
	}

	private func rescue(error: SQLiteError) throws -> Bool {
		if case .queryError(let msg) = error,
			let match = msg.firstMatch(of: /no such table: ([^\s]+)/)
		{
			let predicateResult = try super.query(
				"SELECT json(column_names) as json_array FROM _predicate WHERE name = ?",
				parameters: [match.1]
			)
			guard predicateResult.count == 1 else { return false }

			// Deserialize the JSON array of column names and use them for the view
			guard
				let columnNamesJson = predicateResult[0]["json_array"]
					as? String,
				let columnNamesData = columnNamesJson.data(using: .utf8),
				let columnNames = try JSONSerialization.jsonObject(
					with: columnNamesData
				) as? [String],
				!columnNames.isEmpty
			else {
				throw RBDBError.corruptData(
					message: "expected JSON array in _predicate.column_names"
				)
			}

			try createViewAndTrigger(for: String(match.1), columns: columnNames)
			return true
		}
		return false
	}
}

func formulaToJSON(_ formula: Formula) throws -> String {
	let encoder = JSONEncoder()
	let canonicalFormula = formula.canonicalize()
	guard
		let jsonStr = String(
			data: try encoder.encode(canonicalFormula),
			encoding: .utf8
		)
	else {
		throw RBDBError.corruptData(
			message: "Failed to encode formula as UTF-8 JSON"
		)
	}
	return jsonStr
}

// SQLite function implementation for predicate_formula()
func predicateFormulaSQLiteFunction(
	context: OpaquePointer?,
	argc: Int32,
	argv: UnsafeMutablePointer<OpaquePointer?>?
) {
	guard argc >= 1, let argv = argv else {
		sqlite3_result_error(
			context,
			"predicate_formula() requires at least one argument",
			-1
		)
		return
	}

	// Get the predicate name (first argument)
	guard let predicateNamePtr = sqlite3_value_text(argv[0]) else {
		sqlite3_result_error(
			context,
			"predicate_formula() first argument must be a string",
			-1
		)
		return
	}
	let predicateName = String(cString: predicateNamePtr)

	// Convert remaining arguments to Terms
	var terms: [Term] = []
	for i in 1..<argc {
		let value = argv[Int(i)]
		let sqliteType = sqlite3_value_type(value)

		let term: Term
		switch sqliteType {
		case SQLITE_TEXT:
			let textPtr = sqlite3_value_text(value)
			let text = String(cString: textPtr!)
			term = .string(text)
		case SQLITE_INTEGER:
			let intValue = sqlite3_value_int64(value)
			term = .number(Float(intValue))
		case SQLITE_FLOAT:
			let floatValue = sqlite3_value_double(value)
			term = .number(Float(floatValue))
		case SQLITE_NULL:
			sqlite3_result_error(
				context,
				"predicate_formula() does not support NULL arguments",
				-1
			)
			return
		case SQLITE_BLOB:
			sqlite3_result_error(
				context,
				"predicate_formula() does not support BLOB arguments",
				-1
			)
			return
		default:
			sqlite3_result_error(
				context,
				"predicate_formula() unsupported argument type",
				-1
			)
			return
		}

		terms.append(term)
	}

	// Create the Formula
	let formula = Formula.predicate(name: predicateName, arguments: terms)

	// Convert to JSON using the utility function
	do {
		let jsonStr = try formulaToJSON(formula)

		// Return the JSON string
		jsonStr.withCString { cString in
			sqlite3_result_text(
				context,
				cString,
				-1,
				unsafeBitCast(-1, to: sqlite3_destructor_type.self)
			)
		}
	} catch {
		sqlite3_result_error(context, "Failed to encode formula: \(error)", -1)
	}
}
