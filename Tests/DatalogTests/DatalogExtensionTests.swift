import Foundation
import Testing

@testable import RBDB
@testable import Datalog

@Suite("Datalog Extension Tests")
struct DatalogExtensionTests {

	@Test("assert(datalog:) and query(datalog:) with README sample code")
	func readmeSampleCode() async throws {
		// IMPORTANT: This test uses the exact sample code from the README.
		// If this test fails due to an intentional breaking API change,
		// you MUST update the corresponding sample code in README.md as well.

		let db = try RBDB(path: ":memory:")

		// Create tables for our predicates
		try db.query(sql: "CREATE TABLE parent(parent, child)")
		try db.query(sql: "CREATE TABLE grandparent(grandparent, grandchild)")

		// Assert some facts using datalog syntax
		try db.assert(datalog: "parent('John', 'Mary')")
		try db.assert(datalog: "parent('Mary', 'Tom')")
		try db.assert(datalog: "parent('Bob', 'Alice')")

		// Define a rule: grandparent(X, Z) :- parent(X, Y), parent(Y, Z)
		try db.assert(datalog: "grandparent(X, Z) :- parent(X, Y), parent(Y, Z)")

		// Query back using SQL to verify the rule works
		let result = try db.query(sql: "SELECT * FROM grandparent")
		let rows = Array(result)

		#expect(rows.count == 1, "Should have exactly one grandparent relationship")
		#expect(rows[0]["grandparent"] as? String == "John", "Grandparent should be John")
		#expect(rows[0]["grandchild"] as? String == "Tom", "Grandchild should be Tom")
	}

	@Test("query(datalog:) basic functionality")
	func queryDatalogBasic() async throws {
		let db = try RBDB(path: ":memory:")

		try db.query(sql: "CREATE TABLE user(name)")
		try db.assert(datalog: "user('Alice')")
		try db.assert(datalog: "user('Bob')")

		// Query with variable
		let results = try db.query(datalog: "user(Name)")
		let rows = Array(results)

		#expect(rows.count == 2, "Should return two users")
		let names = rows.compactMap { $0["Name"] as? String }.sorted()
		#expect(names == ["Alice", "Bob"], "Should return Alice and Bob")
	}

	@Test("assert(datalog:) basic functionality")
	func assertDatalogBasic() async throws {
		let db = try RBDB(path: ":memory:")

		try db.query(sql: "CREATE TABLE user(name)")

		// Assert using datalog syntax
		try db.assert(datalog: "user('Charlie')")

		// Verify using SQL query
		let result = try db.query(sql: "SELECT * FROM user")
		let rows = Array(result)

		#expect(rows.count == 1, "Should have one user")
		#expect(rows[0]["name"] as? String == "Charlie", "Name should be Charlie")
	}

	@Test("assert(datalog:) with rule")
	func assertDatalogRule() async throws {
		let db = try RBDB(path: ":memory:")

		try db.query(sql: "CREATE TABLE human(name)")
		try db.query(sql: "CREATE TABLE mortal(name)")

		// Assert a fact
		try db.assert(datalog: "human('Socrates')")

		// Assert a rule: mortal(X) :- human(X)
		try db.assert(datalog: "mortal(X) :- human(X)")

		// Verify the rule works
		let result = try db.query(sql: "SELECT * FROM mortal")
		let rows = Array(result)

		#expect(rows.count == 1, "Should have one mortal")
		#expect(rows[0]["name"] as? String == "Socrates", "Mortal should be Socrates")
	}

	@Test("query(datalog:) with ground formula")
	func queryDatalogGround() async throws {
		let db = try RBDB(path: ":memory:")

		try db.query(sql: "CREATE TABLE user(name)")
		try db.assert(datalog: "user('Alice')")

		// Query for specific user (ground formula)
		let results = try db.query(datalog: "user('Alice')")
		let rows = Array(results)

		#expect(rows.count == 1, "Should return one row for existing user")
		#expect(rows[0]["sat"] as? Int64 == 1, "Should return sat=1 for ground query")

		// Query for non-existent user
		let noResults = try db.query(datalog: "user('Bob')")
		let noRows = Array(noResults)

		#expect(noRows.count == 0, "Should return no rows for non-existent user")
	}
}
