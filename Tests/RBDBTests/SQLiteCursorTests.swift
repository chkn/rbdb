import Foundation
import Testing

@testable import RBDB

@Suite("SQLiteCursor Rerun Tests")
struct SQLiteCursorTests {

	@Test("Rerun cursor without new arguments reuses same parameters")
	func rerunWithoutNewArguments() async throws {
		let db = try SQLiteDatabase(path: ":memory:")

		// Create a test table
		try db.query(sql: "CREATE TABLE test (id INTEGER, name TEXT)")
		try db.query(sql: "INSERT INTO test (id, name) VALUES (1, 'Alice')")
		try db.query(sql: "INSERT INTO test (id, name) VALUES (2, 'Bob')")

		// Create cursor with initial query
		let cursor = try SQLiteCursor(
			db, sql: SQL("SELECT * FROM test WHERE id = ?", arguments: [1]))

		// First iteration should return Alice
		let firstResult = Array(cursor)
		#expect(firstResult.count == 1, "Should return one row on first run")
		#expect(firstResult[0]["name"] as? String == "Alice", "First run should return Alice")

		// Rerun without new arguments - should get same result
		let rerunCursor = try cursor.rerun()
		let secondResult = Array(rerunCursor)
		#expect(secondResult.count == 1, "Should return one row on rerun")
		#expect(secondResult[0]["name"] as? String == "Alice", "Rerun should return Alice again")
	}

	@Test("Rerun cursor with new arguments changes results")
	func rerunWithNewArguments() async throws {
		let db = try SQLiteDatabase(path: ":memory:")

		// Create a test table
		try db.query(sql: "CREATE TABLE test (id INTEGER, name TEXT)")
		try db.query(sql: "INSERT INTO test (id, name) VALUES (1, 'Alice')")
		try db.query(sql: "INSERT INTO test (id, name) VALUES (2, 'Bob')")
		try db.query(sql: "INSERT INTO test (id, name) VALUES (3, 'Charlie')")

		// Create cursor with initial query
		let cursor = try SQLiteCursor(
			db, sql: SQL("SELECT * FROM test WHERE id = ?", arguments: [1]))

		// First iteration should return Alice
		let firstResult = Array(cursor)
		#expect(firstResult.count == 1, "Should return one row on first run")
		#expect(firstResult[0]["name"] as? String == "Alice", "First run should return Alice")

		// Rerun with different argument - should get Bob
		let rerunCursor = try cursor.rerun(withArguments: [2])
		let secondResult = Array(rerunCursor)
		#expect(secondResult.count == 1, "Should return one row on rerun")
		#expect(secondResult[0]["name"] as? String == "Bob", "Rerun should return Bob")

		// Rerun again with another argument - should get Charlie
		let rerunCursor2 = try cursor.rerun(withArguments: [3])
		let thirdResult = Array(rerunCursor2)
		#expect(thirdResult.count == 1, "Should return one row on second rerun")
		#expect(
			thirdResult[0]["name"] as? String == "Charlie", "Second rerun should return Charlie")
	}

	@Test("Rerun cursor with multiple parameters")
	func rerunWithMultipleParameters() async throws {
		let db = try SQLiteDatabase(path: ":memory:")

		// Create a test table
		try db.query(sql: "CREATE TABLE test (id INTEGER, name TEXT, age INTEGER)")
		try db.query(sql: "INSERT INTO test (id, name, age) VALUES (1, 'Alice', 25)")
		try db.query(sql: "INSERT INTO test (id, name, age) VALUES (2, 'Bob', 30)")
		try db.query(sql: "INSERT INTO test (id, name, age) VALUES (3, 'Charlie', 25)")

		// Create cursor with multiple parameters
		let cursor = try SQLiteCursor(
			db, sql: SQL("SELECT * FROM test WHERE age = ? AND name = ?", arguments: [25, "Alice"]))

		// First iteration should return Alice
		let firstResult = Array(cursor)
		#expect(firstResult.count == 1, "Should return one row on first run")
		#expect(firstResult[0]["name"] as? String == "Alice", "First run should return Alice")

		// Rerun with different parameters - should get Charlie
		let rerunCursor = try cursor.rerun(withArguments: [25, "Charlie"])
		let secondResult = Array(rerunCursor)
		#expect(secondResult.count == 1, "Should return one row on rerun")
		#expect(secondResult[0]["name"] as? String == "Charlie", "Rerun should return Charlie")

		// Rerun with parameters that match Bob
		let rerunCursor2 = try cursor.rerun(withArguments: [30, "Bob"])
		let thirdResult = Array(rerunCursor2)
		#expect(thirdResult.count == 1, "Should return one row on second rerun")
		#expect(thirdResult[0]["name"] as? String == "Bob", "Second rerun should return Bob")
	}

	@Test("Rerun cursor with multi-statement SQL")
	func rerunWithMultiStatement() async throws {
		let db = try SQLiteDatabase(path: ":memory:")

		// Create test tables
		try db.query(sql: "CREATE TABLE users (id INTEGER, name TEXT)")
		try db.query(sql: "CREATE TABLE temp_data (value INTEGER)")

		try db.query(sql: "INSERT INTO users (id, name) VALUES (1, 'Alice')")
		try db.query(sql: "INSERT INTO users (id, name) VALUES (2, 'Bob')")

		// Multi-statement SQL: insert into temp table, then select from users
		let multiStatementSQL = SQL(
			"""
			INSERT INTO temp_data (value) VALUES (?);
			SELECT * FROM users WHERE id = ?
			""", arguments: [100, 1])

		let cursor = try SQLiteCursor(db, sql: multiStatementSQL)

		// First run should insert 100 and return Alice
		let firstResult = Array(cursor)
		#expect(firstResult.count == 1, "Should return one row on first run")
		#expect(firstResult[0]["name"] as? String == "Alice", "First run should return Alice")

		// Verify temp_data has the inserted value
		let tempResults1 = Array(
			try db.query(sql: "SELECT COUNT(*) as count FROM temp_data WHERE value = 100"))
		#expect(tempResults1[0]["count"] as? Int64 == 1, "Should have inserted 100 into temp_data")

		// Rerun with different arguments
		let rerunCursor = try cursor.rerun(withArguments: [200, 2])
		let secondResult = Array(rerunCursor)
		#expect(secondResult.count == 1, "Should return one row on rerun")
		#expect(secondResult[0]["name"] as? String == "Bob", "Rerun should return Bob")

		// Verify temp_data has the new inserted value
		let tempResults2 = Array(
			try db.query(sql: "SELECT COUNT(*) as count FROM temp_data WHERE value = 200"))
		#expect(tempResults2[0]["count"] as? Int64 == 1, "Should have inserted 200 into temp_data")
	}

	@Test("Rerun cursor with wrong parameter count throws error")
	func rerunWithWrongParameterCount() async throws {
		let db = try SQLiteDatabase(path: ":memory:")

		try db.query(sql: "CREATE TABLE test (id INTEGER, name TEXT)")
		try db.query(sql: "INSERT INTO test (id, name) VALUES (1, 'Alice')")

		// Create cursor expecting 1 parameter
		let cursor = try SQLiteCursor(
			db, sql: SQL("SELECT * FROM test WHERE id = ?", arguments: [1]))

		// First run should work
		let firstResult = Array(cursor)
		#expect(firstResult.count == 1, "Should return one row on first run")

		// Try to rerun with wrong number of parameters
		do {
			_ = try cursor.rerun(withArguments: [1, 2])  // Too many parameters
			#expect(Bool(false), "Expected parameter count error")
		} catch SQLiteError.queryParameterCount(let expected, let got) {
			#expect(expected == 1, "Should expect 1 parameter")
			#expect(got == 2, "Should report 2 parameters provided")
		}

		do {
			_ = try cursor.rerun(withArguments: [])  // Too few parameters
			#expect(Bool(false), "Expected parameter count error")
		} catch SQLiteError.queryParameterCount(let expected, let got) {
			#expect(expected == 1, "Should expect 1 parameter")
			#expect(got == 0, "Should report 0 parameters provided")
		}
	}

	@Test("Rerun cursor returns self for method chaining")
	func rerunReturnsSelf() async throws {
		let db = try SQLiteDatabase(path: ":memory:")

		try db.query(sql: "CREATE TABLE test (id INTEGER)")
		try db.query(sql: "INSERT INTO test (id) VALUES (1)")

		let cursor = try SQLiteCursor(
			db, sql: SQL("SELECT * FROM test WHERE id = ?", arguments: [1]))

		// Verify that rerun returns the same cursor instance
		let rerunCursor = try cursor.rerun(withArguments: [1])
		#expect(cursor === rerunCursor, "rerun should return the same cursor instance")

		// Should be able to chain operations
		let results = Array(try cursor.rerun(withArguments: [1]))
		#expect(results.count == 1, "Should return one row")
	}

	@Test("Rerun cursor with different parameter types")
	func rerunWithDifferentParameterTypes() async throws {
		let db = try SQLiteDatabase(path: ":memory:")

		try db.query(
			sql: "CREATE TABLE test (id INTEGER, name TEXT, score REAL, data BLOB, active INTEGER)")

		// Insert test data with various types
		try db.query(
			sql: """
					INSERT INTO test (id, name, score, data, active) 
					VALUES (1, 'Alice', 85.5, X'deadbeef', 1)
				""")

		// Test with different parameter types
		let cursor = try SQLiteCursor(
			db,
			sql: SQL(
				"SELECT * FROM test WHERE id = ? AND name = ? AND score > ? AND active = ?",
				arguments: [1, "Alice", 80.0, 1]))

		let firstResult = Array(cursor)
		#expect(firstResult.count == 1, "Should return one row")

		// Rerun with different types
		let rerunCursor = try cursor.rerun(withArguments: [1, "Alice", 90.0, 0])
		let secondResult = Array(rerunCursor)
		#expect(secondResult.count == 0, "Should return no rows with active = false")

		// Rerun again with mixed types including null
		try db.query(
			sql: "INSERT INTO test (id, name, score, data, active) VALUES (2, 'Bob', 95.0, NULL, 0)"
		)
		let rerunCursor2 = try cursor.rerun(withArguments: [2, "Bob", 90.0, 0])
		let thirdResult = Array(rerunCursor2)
		#expect(thirdResult.count == 1, "Should return Bob's row")
	}

	@Test("underestimatedCount > 0 iff cursor has rows")
	func underestimatedCountBasedOnNextRow() async throws {
		let db = try SQLiteDatabase(path: ":memory:")

		try db.query(sql: "CREATE TABLE test (id INTEGER, name TEXT)")
		try db.query(sql: "INSERT INTO test (id, name) VALUES (1, 'Alice')")
		try db.query(sql: "INSERT INTO test (id, name) VALUES (2, 'Bob')")

		// Cursor with results
		let cursorWithResults = try db.query(sql: SQL("SELECT * FROM test"))
		#expect(
			cursorWithResults.underestimatedCount > 0 && cursorWithResults.underestimatedCount <= 2)

		// Cursor with no results
		let cursorEmpty = try SQLiteCursor(db, sql: SQL("SELECT * FROM test WHERE id = 999"))
		#expect(cursorEmpty.underestimatedCount == 0)
	}

	@Test("underestimatedCount == 0 for empty result set")
	func underestimatedCountEmptyResult() async throws {
		let db = try SQLiteDatabase(path: ":memory:")

		try db.query(sql: "CREATE TABLE test (id INTEGER, name TEXT)")
		// No data inserted

		let cursor = try db.query(sql: SQL("SELECT * FROM test"))

		let estimatedCount = cursor.underestimatedCount
		let actualCount = Array(cursor).count

		#expect(estimatedCount == 0, "underestimatedCount should be 0 for empty result")
		#expect(actualCount == 0, "Should return 0 rows for empty table")
	}
}
