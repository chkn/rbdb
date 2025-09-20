import Foundation
import Testing

@testable import RBDB

@Suite("RBDB Query Tests")
struct RBDBQueryTests {

	@Test("query(formula:) with no variables returns boolean result")
	func queryGroundFormula() async throws {
		let rbdb = try RBDB(path: ":memory:")

		try rbdb.query(sql: "CREATE TABLE user(name TEXT)")
		try rbdb.query(sql: "INSERT INTO user(name) VALUES ('Alice')")
		try rbdb.query(sql: "INSERT INTO user(name) VALUES ('Bob')")

		// Query for user("Alice") - should return true
		let trueFormula = Formula.predicate(
			Predicate(
				name: "user",
				arguments: [Term.string("Alice")]
			))

		let trueResults = try rbdb.query(formula: trueFormula)
		let trueRows = Array(trueResults)

		#expect(trueRows.count == 1, "Should return exactly one row")
		#expect(trueRows[0]["sat"] as? Int64 == 1, "Should return true for existing user")

		// Query for user("Charlie") - should return false
		let falseFormula = Formula.predicate(
			Predicate(
				name: "user",
				arguments: [Term.string("Charlie")]
			))

		let falseResults = try rbdb.query(formula: falseFormula)
		let falseRows = Array(falseResults)

		#expect(falseRows.count == 0, "Should return no rows")
	}

	@Test("query(formula:) with one variable returns all bindings")
	func queryWithOneVariable() async throws {
		let rbdb = try RBDB(path: ":memory:")

		try rbdb.query(sql: "CREATE TABLE user(name TEXT)")
		try rbdb.query(sql: "INSERT INTO user(name) VALUES ('Alice')")
		try rbdb.query(sql: "INSERT INTO user(name) VALUES ('Bob')")
		try rbdb.query(sql: "INSERT INTO user(name) VALUES ('Charlie')")

		let X = Var("X")

		// Query for user(X) - should return all users with X bound to each name
		let formula = Formula.predicate(
			Predicate(
				name: "user",
				arguments: [Term.variable(X)]
			))

		let results = try rbdb.query(formula: formula)
		let rows = Array(results)

		#expect(rows.count == 3, "Should return three rows for three users")

		// Each row should have the variable X bound to a user name
		let xValues = rows.compactMap { $0["X"] as? String }.sorted()
		#expect(xValues == ["Alice", "Bob", "Charlie"], "Should return all user names bound to X")
	}

	@Test("query(formula:) with multiple variables returns all binding combinations")
	func queryWithMultipleVariables() async throws {
		let rbdb = try RBDB(path: ":memory:")

		try rbdb.query(sql: "CREATE TABLE person(name TEXT, age INTEGER)")
		try rbdb.query(sql: "INSERT INTO person(name, age) VALUES ('Alice', 25)")
		try rbdb.query(sql: "INSERT INTO person(name, age) VALUES ('Bob', 30)")

		let X = Var("X")
		let Y = Var("Y")

		// Query for person(X, Y) - should return all name-age combinations
		let formula = Formula.predicate(
			Predicate(
				name: "person",
				arguments: [Term.variable(X), Term.variable(Y)]
			))

		let results = try rbdb.query(formula: formula)
		let rows = Array(results)

		#expect(rows.count == 2, "Should return two rows for two people")

		// Check that we have columns for both variables
		#expect(rows[0].keys.contains("X"), "Should have column for variable X")
		#expect(rows[0].keys.contains("Y"), "Should have column for variable Y")

		// Verify the bindings
		let bindings = rows.map { row in
			(row["X"] as? String, row["Y"] as? Int64)
		}.sorted { $0.0 ?? "" < $1.0 ?? "" }

		#expect(
			bindings[0].0 == "Alice" && bindings[0].1 == 25, "First binding should be Alice, 25")
		#expect(bindings[1].0 == "Bob" && bindings[1].1 == 30, "Second binding should be Bob, 30")
	}

	@Test("query(formula:) with Horn clause inference")
	func queryHornClauseInference() async throws {
		let rbdb = try RBDB(path: ":memory:")

		try rbdb.query(sql: "CREATE TABLE parent(child TEXT, parent_name TEXT)")
		try rbdb.query(sql: "CREATE TABLE grandparent(grandchild TEXT, grandparent_name TEXT)")

		// Insert parent relationships
		try rbdb.query(sql: "INSERT INTO parent(child, parent_name) VALUES ('Alice', 'Bob')")
		try rbdb.query(sql: "INSERT INTO parent(child, parent_name) VALUES ('Bob', 'Charlie')")

		let X = Var("X")
		let Y = Var("Y")
		let Z = Var("Z")

		// Assert rule: grandparent(X, Z) :- parent(X, Y), parent(Y, Z)
		let grandparentRule = Formula.hornClause(
			positive: Predicate(name: "grandparent", arguments: [.variable(X), .variable(Z)]),
			negative: [
				Predicate(name: "parent", arguments: [.variable(X), .variable(Y)]),
				Predicate(name: "parent", arguments: [.variable(Y), .variable(Z)]),
			]
		)
		try rbdb.assert(formula: grandparentRule)

		// Query ground formula: grandparent("Alice", "Charlie") - should return true
		let groundQuery = Formula.predicate(
			Predicate(
				name: "grandparent",
				arguments: [Term.string("Alice"), Term.string("Charlie")]
			))

		let groundResults = try rbdb.query(formula: groundQuery)
		let groundRows = Array(groundResults)

		#expect(groundRows.count == 1, "Should return one row")
		#expect(
			groundRows[0]["sat"] as? Int64 == 1, "Should infer Alice is grandchild of Charlie")

		// Query with variable: grandparent("Alice", Z) - should return Z=Charlie
		let variableQuery = Formula.predicate(
			Predicate(
				name: "grandparent",
				arguments: [Term.string("Alice"), Term.variable(Z)]
			))

		let variableResults = try rbdb.query(formula: variableQuery)
		let variableRows = Array(variableResults)

		#expect(variableRows.count == 1, "Should return one binding")
		#expect(variableRows[0]["Z"] as? String == "Charlie", "Z should be bound to Charlie")
	}

	@Test("query(formula:) with non-existent predicate throws")
	func queryNonExistentPredicate() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Query ground formula for non-existent predicate
		let groundFormula = Formula.predicate(
			Predicate(
				name: "nonexistent",
				arguments: [Term.string("test")]
			))

		#expect(throws: SQLiteError.self) {
			_ = try rbdb.query(formula: groundFormula)
		}
	}

	@Test("query(formula:) with mixed constants and variables")
	func queryMixedTerms() async throws {
		let rbdb = try RBDB(path: ":memory:")

		try rbdb.query(sql: "CREATE TABLE likes(person TEXT, food TEXT)")
		try rbdb.query(sql: "INSERT INTO likes(person, food) VALUES ('Alice', 'pizza')")
		try rbdb.query(sql: "INSERT INTO likes(person, food) VALUES ('Alice', 'pasta')")
		try rbdb.query(sql: "INSERT INTO likes(person, food) VALUES ('Bob', 'pizza')")

		let X = Var("X")

		// Query likes("Alice", X) - should return what Alice likes
		let formula = Formula.predicate(
			Predicate(
				name: "likes",
				arguments: [Term.string("Alice"), Term.variable(X)]
			))

		let results = try rbdb.query(formula: formula)
		let rows = Array(results)

		#expect(rows.count == 2, "Should return two things Alice likes")

		let foods = rows.compactMap { $0["X"] as? String }.sorted()
		#expect(foods == ["pasta", "pizza"], "Should return pasta and pizza")
	}

	@Test("query(formula:) returns no rows when no matches")
	func queryNoMatches() async throws {
		let rbdb = try RBDB(path: ":memory:")

		try rbdb.query(sql: "CREATE TABLE user(name TEXT)")
		try rbdb.query(sql: "INSERT INTO user(name) VALUES ('Alice')")

		let formula = Formula.predicate(
			Predicate(
				name: "user",
				arguments: [Term.string("Zoe")]
			))

		// Ground query should return false
		let results = try rbdb.query(formula: formula)
		let rows = Array(results)

		#expect(rows.count == 0, "Should return no rows")
	}
}
