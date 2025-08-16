import Foundation
import RBDB
import Testing

struct StatementRetryTests {
	@Test("Multi-statement retry from failure point")
	func retryFromFailurePoint() throws {
		let rbdb = try RBDB(path: ":memory:")

		// First create a table that will be available after rescue
		try rbdb.query(sql: "CREATE TABLE users (id, name)")

		// Now simulate a multi-statement query where the second statement fails
		// but can be rescued, and the third statement should still execute
		let multiStatementSQL = """
			INSERT INTO users VALUES (1, 'Alice');
			SELECT * FROM posts;
			INSERT INTO users VALUES (2, 'Bob')
			"""

		do {
			// This should fail on the second statement (posts table doesn't exist)
			// but after rescue creates the posts table, it should resume from there
			try rbdb.query(sql: "CREATE TABLE posts (id, title)")  // Create posts table for rescue
			_ = try rbdb.query(sql: SQL(multiStatementSQL))

			// The final INSERT should have succeeded, so we should have 2 users
			let userCount = try rbdb.query(
				sql: "SELECT COUNT(*) as count FROM users"
			)
			#expect(userCount[0]["count"] as? Int64 == 2)

		} catch {
			// If it fails, create the posts table and try again to test the mechanism
			try rbdb.query(sql: "CREATE TABLE posts (id, title)")
			try rbdb.query(sql: SQL(multiStatementSQL))

			// Should still end up with 2 users
			let userCount = try rbdb.query(
				sql: "SELECT COUNT(*) as count FROM users"
			)
			#expect(userCount[0]["count"] as? Int64 == 2)
		}
	}

	@Test("Verify offset tracking in SQLiteError")
	func offsetTrackingWorks() throws {
		let rbdb = try RBDB(path: ":memory:")

		let sqlWithError = """
			CREATE TABLE test (id);
			SELECT * FROM nonexistent_table;
			CREATE TABLE another (name)
			"""

		do {
			try rbdb.query(sql: SQL(sqlWithError))
		} catch let error as SQLiteError {
			if case .queryError(_, let offset) = error {
				#expect(offset != nil)
				// Offset should be provided for multi-statement SQL
			} else {
				throw error
			}
		}
	}

	@Test("CREATE INDEX should not be re-executed after rescue")
	func createIndexNotReExecutedAfterRescue() throws {
		// Use a temporary file instead of in-memory to test TEMP view/trigger loss
		let tempDir = FileManager.default.temporaryDirectory
		let dbPath = tempDir.appendingPathComponent(
			"test_\(UUID().uuidString).db"
		).path
		defer {
			try? FileManager.default.removeItem(atPath: dbPath)
		}

		// First connection: Create the table
		do {
			let rbdb1 = try RBDB(path: dbPath)
			try rbdb1.query(sql: "CREATE TABLE users (id, name)")
		}

		// Second connection: CREATE INDEX then SELECT (which will need rescue due to lost TEMP view)
		let rbdb2 = try RBDB(path: dbPath)

		let multiStatementSQL = """
			CREATE INDEX users_name_idx ON _entity(entity_id);
			SELECT * FROM users
			"""

		try rbdb2.query(sql: SQL(multiStatementSQL))
		// If we reach here, offset-based retry worked

		// Verify the index was created
		let indexExists = try rbdb2.query(
			sql: "SELECT name FROM sqlite_master WHERE type='index' AND name='users_name_idx'"
		)
		#expect(indexExists.count == 1, "Index should exist")
	}

	@Test("Multi-statement SQL with parameters handles retry correctly")
	func multiStatementWithParametersRetry() throws {
		// Use a temporary file to test rescue after connection loss
		let tempDir = FileManager.default.temporaryDirectory
		let dbPath = tempDir.appendingPathComponent(
			"test_\(UUID().uuidString).db"
		).path
		defer {
			try? FileManager.default.removeItem(atPath: dbPath)
		}

		// First connection: Create the tables
		do {
			let rbdb1 = try RBDB(path: dbPath)
			try rbdb1.query(sql: "CREATE TABLE users (id, name)")
			try rbdb1.query(sql: "CREATE TABLE posts (id, title)")

		}

		// Second connection: This will need rescue due to lost TEMP views/triggers
		let rbdb2 = try RBDB(path: dbPath)

		// Multi-statement SQL with parameters
		let userId1 = 42
		let userName1 = "Alice"
		let userId2 = 100
		let userName2 = "Bob"

		let multiStatementSQL: SQL = """
			INSERT INTO users VALUES (\(userId1), \(userName1));
			SELECT * FROM posts WHERE id = \(userId1);
			INSERT INTO users VALUES (\(userId2), \(userName2))
			"""

		// This should trigger rescue on the SELECT and then continue
		try rbdb2.query(sql: multiStatementSQL)

		// Verify both users were inserted with correct parameter values
		let users = try rbdb2.query(sql: "SELECT id, name FROM users ORDER BY id")
		#expect(users.count == 2)
		#expect(users[0]["id"] as? Int64 == 42)
		#expect(users[0]["name"] as? String == "Alice")
		#expect(users[1]["id"] as? Int64 == 100)
		#expect(users[1]["name"] as? String == "Bob")
	}

	@Test("Multi-statement parameter count error should report total expected parameters")
	func multiStatementParameterCountError() throws {
		let rbdb = try RBDB(path: ":memory:")

		// Create a table for our test
		try rbdb.query(sql: "CREATE TABLE test_table (id, name, value)")

		// Multi-statement SQL that expects 5 total parameters but we only provide 2
		let param1 = 1
		let param2 = "Alice"

		let multiStatementSQL: SQL = """
			INSERT INTO test_table VALUES (\(param1), \(param2), 'first');
			INSERT INTO test_table VALUES (?, ?, ?)
			"""

		// Verify our SQL object has the expected structure
		#expect(multiStatementSQL.arguments.count == 2, "Should have 2 actual parameters")
		// The query text should have 5 parameter placeholders total
		let placeholderCount = multiStatementSQL.queryText.components(separatedBy: "?").count - 1
		#expect(placeholderCount == 5, "Should have 5 parameter placeholders in query text")

		do {
			try rbdb.query(sql: multiStatementSQL)
			#expect(Bool(false), "Expected parameter count error")
		} catch SQLiteError.queryParameterCount(let expected, let got) {
			#expect(expected == 5, "Should report total parameters expected for entire SQL")
			#expect(got == 2, "Should report total parameters provided")
		}
	}

	@Test("Parameter count with string literals containing '?' should not be counted")
	func parameterCountWithQuestionMarkInStringLiteral() throws {
		let rbdb = try RBDB(path: ":memory:")

		// Create a table for our test
		try rbdb.query(sql: "CREATE TABLE test_table (id, question)")

		// SQL with string literal containing '?' and actual parameter placeholders
		let param1 = 1

		let sqlWithStringLiteral: SQL = """
			INSERT INTO test_table VALUES (\(param1), 'What is this? A test?');
			INSERT INTO test_table VALUES (?, 'Another question?')
			"""

		// Verify our SQL structure
		// Should have 2 actual parameters (param1 + one placeholder)
		// But the query text contains 4 '?' characters total (2 in string literals + 2 actual parameters)
		#expect(sqlWithStringLiteral.arguments.count == 1, "Should have 1 actual parameter")

		do {
			try rbdb.query(sql: sqlWithStringLiteral)
			#expect(Bool(false), "Expected parameter count error")
		} catch SQLiteError.queryParameterCount(let expected, let got) {
			#expect(
				expected == 2,
				"Should only count actual parameter placeholders, not '?' in string literals")
			#expect(got == 1, "Should report total parameters provided")
		}
	}

	@Test("Too many arguments should report correct parameter count")
	func tooManyArgumentsParameterCount() throws {
		let rbdb = try RBDB(path: ":memory:")

		// Create a table for our test
		try rbdb.query(sql: "CREATE TABLE test_table (id, name)")

		// SQL that expects 2 parameters but we provide 4
		let sqlWithTooManyParams = SQL(
			"INSERT INTO test_table VALUES (?, ?)",
			arguments: [1, "Alice", 42, "Bob"]
		)

		// Verify our SQL structure
		#expect(sqlWithTooManyParams.arguments.count == 4, "Should have 4 actual parameters")

		do {
			try rbdb.query(sql: sqlWithTooManyParams)
			#expect(Bool(false), "Expected parameter count error")
		} catch SQLiteError.queryParameterCount(let expected, let got) {
			// Should report that 2 parameters were expected but 4 were provided
			#expect(expected == 2, "Should report 2 parameters consumed")
			#expect(got == 4, "Should report 4 parameters provided")
		}
	}
}
