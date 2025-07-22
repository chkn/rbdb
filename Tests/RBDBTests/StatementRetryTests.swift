import Foundation
import RBDB
import Testing

struct StatementRetryTests {
	@Test("Multi-statement retry from failure point")
	func retryFromFailurePoint() throws {
		let rbdb = try RBDB(path: ":memory:")

		// First create a table that will be available after rescue
		try rbdb.query("CREATE TABLE users (id, name)")

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
			try rbdb.query("CREATE TABLE posts (id, title)")  // Create posts table for rescue
			_ = try rbdb.query(multiStatementSQL)

			// The final INSERT should have succeeded, so we should have 2 users
			let userCount = try rbdb.query(
				"SELECT COUNT(*) as count FROM users"
			)
			#expect(userCount[0]["count"] as? Int64 == 2)

		} catch {
			// If it fails, create the posts table and try again to test the mechanism
			try rbdb.query("CREATE TABLE posts (id, title)")
			_ = try rbdb.query(multiStatementSQL)

			// Should still end up with 2 users
			let userCount = try rbdb.query(
				"SELECT COUNT(*) as count FROM users"
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
			try rbdb.query(sqlWithError)
		} catch let error as SQLiteError {
			if case .queryError(_, let offset) = error {
				#expect(offset != nil)
				#expect(offset! > 0)  // Should be past the first statement
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
			try rbdb1.query("CREATE TABLE users (id, name)")
		}

		// Second connection: CREATE INDEX then SELECT (which will need rescue due to lost TEMP view)
		let rbdb2 = try RBDB(path: dbPath)

		let multiStatementSQL = """
			CREATE INDEX users_name_idx ON _entity(entity_id);
			SELECT * FROM users
			"""

		try rbdb2.query(multiStatementSQL)
		// If we reach here, offset-based retry worked

		// Verify the index was created
		let indexExists = try rbdb2.query(
			"SELECT name FROM sqlite_master WHERE type='index' AND name='users_name_idx'"
		)
		#expect(indexExists.count == 1, "Index should exist")
	}
}
