import Foundation
import Testing
@testable import RBDB

@Test func implicationDoesntSelectNull() throws {
	let rbdb = try RBDB(path: ":memory:")

	try rbdb.query(sql: "CREATE TABLE human(name TEXT)")
	try rbdb.query(sql: "CREATE TABLE mortal(name TEXT)")

	// Assert the rule: mortal(X) :- human(X)  (all humans are mortal)
	let X = Var()
	let rule = Formula.hornClause(
		positive: Predicate(name: "mortal", arguments: [.variable(X)]),
		negative: [Predicate(name: "human", arguments: [.variable(X)])]
	)

	try rbdb.assert(formula: rule)

	let mortals = Array(try rbdb.query(sql: "SELECT * FROM mortal"))
	#expect(mortals.isEmpty, "Should not select any row: all humans are mortal")
}

@Test func negativeLiteralCountForSimpleHornClause() throws {
	let rbdb = try RBDB(path: ":memory:")

	try rbdb.query(sql: "CREATE TABLE human(name TEXT)")
	try rbdb.query(sql: "CREATE TABLE mortal(name TEXT)")

	// Assert the rule: mortal(X) :- human(X)  (1 negative literal)
	let X = Var()
	let rule = Formula.hornClause(
		positive: Predicate(name: "mortal", arguments: [.variable(X)]),
		negative: [Predicate(name: "human", arguments: [.variable(X)])]
	)

	try rbdb.assert(formula: rule)

	// Check that the negative_literal_count is 1
	let results = Array(
		try rbdb.query(
			sql: """
					SELECT output_type, negative_literal_count FROM _rule 
					WHERE output_type = '@mortal'
				"""))

	#expect(results.count == 1, "Should have one mortal rule")
	#expect(results[0]["negative_literal_count"] as? Int64 == 1, "Should have 1 negative literal")
}

@Test func negativeLiteralCountForComplexHornClause() throws {
	let rbdb = try RBDB(path: ":memory:")

	try rbdb.query(sql: "CREATE TABLE grandparent(a TEXT, b TEXT)")
	try rbdb.query(sql: "CREATE TABLE parent(a TEXT, b TEXT)")

	// Assert the rule: grandparent(X, Z) :- parent(X, Y), parent(Y, Z)  (2 negative literals)
	let X = Var()
	let Y = Var()
	let Z = Var()
	let rule = Formula.hornClause(
		positive: Predicate(name: "grandparent", arguments: [.variable(X), .variable(Z)]),
		negative: [
			Predicate(name: "parent", arguments: [.variable(X), .variable(Y)]),
			Predicate(name: "parent", arguments: [.variable(Y), .variable(Z)]),
		]
	)

	try rbdb.assert(formula: rule)

	// Check that the negative_literal_count is 2
	let results = Array(
		try rbdb.query(
			sql: """
					SELECT output_type, negative_literal_count FROM _rule 
					WHERE output_type = '@grandparent'
				"""))

	#expect(results.count == 1, "Should have one grandparent rule")
	#expect(results[0]["negative_literal_count"] as? Int64 == 2, "Should have 2 negative literals")
}

@Test func negativeLiteralCountForFacts() throws {
	let rbdb = try RBDB(path: ":memory:")

	try rbdb.query(sql: "CREATE TABLE human(name TEXT)")

	// Assert a fact: human(Socrates)  (0 negative literals)
	let fact = Formula.hornClause(
		positive: Predicate(name: "human", arguments: [.string("Socrates")]),
		negative: []  // No negative literals = fact
	)

	try rbdb.assert(formula: fact)

	// Check that the negative_literal_count is 0 for facts
	let results = Array(
		try rbdb.query(
			sql: """
					SELECT output_type, negative_literal_count FROM _rule 
					WHERE output_type = '@human'
				"""))

	#expect(results.count == 1, "Should have one human rule")
	#expect(
		results[0]["negative_literal_count"] as? Int64 == 0,
		"Should have 0 negative literals (fact)")
}

@Test func negativeLiteralCountWithMixedRuleTypes() throws {
	let rbdb = try RBDB(path: ":memory:")

	try rbdb.query(sql: "CREATE TABLE human(name TEXT)")
	try rbdb.query(sql: "CREATE TABLE mortal(name TEXT)")
	try rbdb.query(sql: "CREATE TABLE parent(a TEXT, b TEXT)")
	try rbdb.query(sql: "CREATE TABLE ancestor(a TEXT, b TEXT)")

	// Fact: human(Socrates)  (0 negative literals)
	let fact = Formula.hornClause(
		positive: Predicate(name: "human", arguments: [.string("Socrates")]),
		negative: []
	)
	try rbdb.assert(formula: fact)

	// Rule 1: mortal(X) :- human(X)  (1 negative literal)
	let X = Var()
	let rule1 = Formula.hornClause(
		positive: Predicate(name: "mortal", arguments: [.variable(X)]),
		negative: [Predicate(name: "human", arguments: [.variable(X)])]
	)
	try rbdb.assert(formula: rule1)

	// Rule 2: ancestor(X, Z) :- parent(X, Y), ancestor(Y, Z)  (2 negative literals)
	let Y = Var()
	let Z = Var()
	let rule2 = Formula.hornClause(
		positive: Predicate(name: "ancestor", arguments: [.variable(X), .variable(Z)]),
		negative: [
			Predicate(name: "parent", arguments: [.variable(X), .variable(Y)]),
			Predicate(name: "ancestor", arguments: [.variable(Y), .variable(Z)]),
		]
	)
	try rbdb.assert(formula: rule2)

	// Check all rules and their negative literal counts
	let results = Array(
		try rbdb.query(
			sql: """
					SELECT output_type, negative_literal_count FROM _rule 
					ORDER BY negative_literal_count
				"""))

	#expect(results.count == 3, "Should have three rules")

	// Fact: human(Socrates) - 0 negative literals
	#expect(results[0]["output_type"] as? String == "@human", "Should be @human")
	#expect(results[0]["negative_literal_count"] as? Int64 == 0, "Should have 0 negative literals")

	// Rule: mortal(X) :- human(X) - 1 negative literal
	#expect(results[1]["output_type"] as? String == "@mortal", "Should be @mortal")
	#expect(results[1]["negative_literal_count"] as? Int64 == 1, "Should have 1 negative literal")

	// Rule: ancestor(X, Z) :- parent(X, Y), ancestor(Y, Z) - 2 negative literals
	#expect(results[2]["output_type"] as? String == "@ancestor", "Should be @ancestor")
	#expect(results[2]["negative_literal_count"] as? Int64 == 2, "Should have 2 negative literals")
}
