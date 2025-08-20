import Foundation
import Testing

@testable import RBDB

@Suite("CREATE TABLE Interception Tests")
struct CreateTableInterceptionTests {

	@Test("Simple CREATE TABLE is intercepted and recorded in predicate table")
	func simpleCreateTableInterception() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Execute a CREATE TABLE statement
		try rbdb.query(sql: "CREATE TABLE users (id INTEGER, name TEXT, email TEXT)")

		// Check that the predicate was recorded
		let results = Array(
			try rbdb.query(
				sql:
					"SELECT name, json(column_names) as column_names_json FROM _predicate WHERE name = 'users'"
			))

		#expect(results.count == 1, "Should have one predicate record")
		#expect(
			results[0]["name"] as? String == "users",
			"Table name should be recorded"
		)

		if let columnNamesJson = results[0]["column_names_json"] as? String,
			let columnNamesData = columnNamesJson.data(using: .utf8)
		{
			let columnNames =
				try JSONSerialization.jsonObject(with: columnNamesData)
				as? [String]
			#expect(
				columnNames == ["id", "name", "email"],
				"Column names should be parsed correctly"
			)
		} else {
			#expect(Bool(false), "column_names should be accessible as JSON")
		}
	}

	@Test("CREATE TABLE IF NOT EXISTS is intercepted")
	func createTableIfNotExistsInterception() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Execute a CREATE TABLE IF NOT EXISTS statement
		try rbdb.query(
			sql:
				"CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY, name TEXT NOT NULL, price REAL)"
		)

		// Check that the predicate was recorded
		let results = Array(
			try rbdb.query(
				sql:
					"SELECT name, json(column_names) as column_names_json FROM _predicate WHERE name = 'products'"
			))

		#expect(results.count == 1, "Should have one predicate record")
		#expect(
			results[0]["name"] as? String == "products",
			"Table name should be recorded"
		)

		if let columnNamesJson = results[0]["column_names_json"] as? String,
			let columnNamesData = columnNamesJson.data(using: .utf8)
		{
			let columnNames =
				try JSONSerialization.jsonObject(with: columnNamesData)
				as? [String]
			#expect(
				columnNames == ["id", "name", "price"],
				"Column names should be parsed correctly"
			)
		} else {
			#expect(Bool(false), "column_names should be accessible as JSON")
		}
	}

	@Test("CREATE TABLE with complex column definitions")
	func createTableWithComplexColumns() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Execute a CREATE TABLE with various column types and constraints
		try rbdb.query(
			sql: """
				    CREATE TABLE complex_table (
				        id INTEGER PRIMARY KEY AUTOINCREMENT,
				        name VARCHAR(255) NOT NULL,
				        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
				        price DECIMAL(10,2),
				        data BLOB,
				        UNIQUE(name)
				    )
				"""
		)

		// Check that the predicate was recorded
		let results = Array(
			try rbdb.query(
				sql:
					"SELECT name, json(column_names) as column_names_json FROM _predicate WHERE name = 'complex_table'"
			))

		#expect(results.count == 1, "Should have one predicate record")
		#expect(
			results[0]["name"] as? String == "complex_table",
			"Table name should be recorded"
		)

		if let columnNamesJson = results[0]["column_names_json"] as? String,
			let columnNamesData = columnNamesJson.data(using: .utf8)
		{
			let columnNames =
				try JSONSerialization.jsonObject(with: columnNamesData)
				as? [String]
			#expect(
				columnNames == ["id", "name", "created_at", "price", "data"],
				"Column names should be parsed correctly"
			)
		} else {
			#expect(Bool(false), "column_names should be accessible as JSON")
		}
	}

	@Test("CREATE TABLE with quoted column names throws error")
	func createTableWithQuotedColumnsThrows() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Execute a CREATE TABLE with quoted column names should throw an error
		#expect(throws: SQLiteError.self) {
			try rbdb.query(
				sql: """
					    CREATE TABLE quoted_table (
					        "user id" INTEGER,
					        name TEXT
					    )
					"""
			)
		}
	}

	@Test("Multiple CREATE TABLE statements are all intercepted")
	func multipleCreateTableStatements() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Execute multiple CREATE TABLE statements
		try rbdb.query(
			sql: """
				    CREATE TABLE table1 (id INTEGER, name TEXT);
				    CREATE TABLE table2 (id INTEGER, value REAL);
				    CREATE TABLE table3 (id INTEGER, data BLOB);
				"""
		)

		// Check that all predicates were recorded
		let results = Array(
			try rbdb.query(
				sql: "SELECT name FROM _predicate ORDER BY name"
			))

		#expect(results.count == 3, "Should have three predicate records")

		let tableNames = results.compactMap { $0["name"] as? String }
		#expect(
			tableNames == ["table1", "table2", "table3"],
			"All table names should be recorded"
		)
	}

	@Test("CREATE TABLE with table name containing special characters")
	func createTableWithSpecialTableName() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Execute a CREATE TABLE with a table name that might need quoting
		try rbdb.query(sql: "CREATE TABLE \"user-data\" (id INTEGER, info TEXT)")

		// Check that the predicate was recorded
		let results = Array(
			try rbdb.query(
				sql:
					"SELECT name, json(column_names) as column_names_json FROM _predicate WHERE name = 'user-data'"
			))

		#expect(results.count == 1, "Should have one predicate record")
		#expect(
			results[0]["name"] as? String == "user-data",
			"Table name should be recorded without quotes"
		)

		if let columnNamesJson = results[0]["column_names_json"] as? String,
			let columnNamesData = columnNamesJson.data(using: .utf8)
		{
			let columnNames =
				try JSONSerialization.jsonObject(with: columnNamesData)
				as? [String]
			#expect(
				columnNames == ["id", "info"],
				"Column names should be parsed correctly"
			)
		}
	}

	@Test("Unparseable CREATE TABLE statement throws error")
	func unparseableCreateTableThrows() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Execute a malformed CREATE TABLE statement should throw an error
		#expect(throws: SQLiteError.self) {
			try rbdb.query(sql: "CREATE TABLE malformed_table")
		}
	}

	@Test("CREATE TABLE with column names only (no types)")
	func createTableWithColumnNamesOnly() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Execute a CREATE TABLE with column names but no explicit types
		try rbdb.query(sql: "CREATE TABLE simple_table (id, name, value)")

		// Check that the predicate was recorded
		let results = Array(
			try rbdb.query(
				sql:
					"SELECT name, json(column_names) as column_names_json FROM _predicate WHERE name = 'simple_table'"
			))

		#expect(results.count == 1, "Should have one predicate record")
		#expect(
			results[0]["name"] as? String == "simple_table",
			"Table name should be recorded"
		)

		if let columnNamesJson = results[0]["column_names_json"] as? String,
			let columnNamesData = columnNamesJson.data(using: .utf8)
		{
			let columnNames =
				try JSONSerialization.jsonObject(with: columnNamesData)
				as? [String]
			#expect(
				columnNames == ["id", "name", "value"],
				"Column names should be parsed correctly"
			)
		} else {
			#expect(Bool(false), "column_names should be accessible as JSON")
		}
	}

	@Test("CREATE TABLE IF NOT EXISTS silently succeeds when table exists")
	func createTableIfNotExistsWhenTableExists() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// First create the table
		try rbdb.query(sql: "CREATE TABLE test_table (id INTEGER, name TEXT)")

		// Verify it was created
		let initialResults = Array(
			try rbdb.query(
				sql: "SELECT name FROM _predicate WHERE name = 'test_table'"
			))
		#expect(
			initialResults.count == 1,
			"Should have one predicate record initially"
		)

		// Try to create the same table again with IF NOT EXISTS - should not throw
		try rbdb.query(
			sql: "CREATE TABLE IF NOT EXISTS test_table (id INTEGER, name TEXT, extra_col TEXT)"
		)

		// Verify we still have only one record (the original one)
		let finalResults = Array(
			try rbdb.query(
				sql: "SELECT name FROM _predicate WHERE name = 'test_table'"
			))
		#expect(
			finalResults.count == 1,
			"Should still have only one predicate record"
		)
	}

	@Test("CREATE TABLE without IF NOT EXISTS fails when table exists")
	func createTableWithoutIfNotExistsWhenTableExists() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// First create the table
		try rbdb.query(sql: "CREATE TABLE test_table (id INTEGER, name TEXT)")

		// Try to create the same table again without IF NOT EXISTS - should throw
		#expect(throws: SQLiteError.self) {
			try rbdb.query(sql: "CREATE TABLE test_table (id INTEGER, name TEXT)")
		}
	}

	@Test("Failed CREATE TABLE doesn't leave orphaned entity records")
	func failedCreateTableDoesntLeaveOrphanedEntities() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// First create the table
		try rbdb.query(sql: "CREATE TABLE test_table (id INTEGER, name TEXT)")

		// Count entities before failed attempt
		let entitiesBeforeResults = Array(
			try rbdb.query(
				sql: "SELECT COUNT(*) as count FROM _entity"
			))
		let entitiesBefore = entitiesBeforeResults[0]["count"] as! Int64

		// Try to create the same table again without IF NOT EXISTS - should throw
		#expect(throws: SQLiteError.self) {
			try rbdb.query(sql: "CREATE TABLE test_table (id INTEGER, name TEXT)")
		}

		// Count entities after failed attempt - should be the same
		let entitiesAfterResults = Array(
			try rbdb.query(
				sql: "SELECT COUNT(*) as count FROM _entity"
			))
		let entitiesAfter = entitiesAfterResults[0]["count"] as! Int64

		#expect(
			entitiesBefore == entitiesAfter,
			"Failed CREATE TABLE should not leave orphaned entity records"
		)
	}
}
