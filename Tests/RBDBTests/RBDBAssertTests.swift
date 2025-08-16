import Foundation
import Testing

@testable import RBDB

struct RBDBAssertTests {

	@Test("assert(formula:) should store rule in database")
	func assertFormulaStoresRule() async throws {
		let rbdb = try RBDB(path: ":memory:")

		try rbdb.query(sql: "CREATE TABLE user(name)")

		// Create a simple predicate formula: user("Alice")
		let formula = Formula.predicate(
			Predicate(
				name: "user",
				arguments: [Term.string("Alice")]
			))

		try rbdb.assert(formula: formula)

		let ruleResults = try rbdb.query(sql: "SELECT name FROM user")
		#expect(
			ruleResults.count == 1,
			"Should have one record stored in user table"
		)
		#expect(ruleResults[0]["name"] as? String == "Alice")
	}

	@Test("INSERT should assert fact")
	func createInsertSelectFlow() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Create a table with one column
		try rbdb.query(sql: "CREATE TABLE user(name)")

		// Insert a row into the table
		try rbdb.query(
			sql: SQL("INSERT INTO user(name) VALUES (?)", arguments: ["Alice"])
		)

		let ruleResults = try rbdb.query(sql: "SELECT name FROM user")
		#expect(
			ruleResults.count == 1,
			"Should have one record stored in user table"
		)
		#expect(ruleResults[0]["name"] as? String == "Alice")
	}
}
