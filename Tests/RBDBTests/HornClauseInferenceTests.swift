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

@Test("Simple inference: all humans are mortal")
func simpleHumanMortalInference() async throws {
	let rbdb = try RBDB(path: ":memory:")

	try rbdb.query(sql: "CREATE TABLE human(name TEXT)")
	try rbdb.query(sql: "CREATE TABLE mortal(entity TEXT)")

	// Assert the rule: mortal(X) :- human(X)  (all humans are mortal)
	let X = Var()
	let rule = Formula.hornClause(
		positive: Predicate(name: "mortal", arguments: [.variable(X)]),
		negative: [Predicate(name: "human", arguments: [.variable(X)])]
	)

	try rbdb.assert(formula: rule)

	// Insert a human
	try rbdb.query(sql: "INSERT INTO human(name) VALUES ('Socrates')")

	// Check that we can query human table
	let humanResults = Array(try rbdb.query(sql: "SELECT * FROM human"))
	#expect(humanResults.count == 1, "Should insert one human")
	#expect(
		humanResults[0]["name"] as? String == "Socrates",
		"The inserted being should be Socrates (before drop)")

	// Drop the human view and try again
	try rbdb.query(sql: "DROP VIEW human")
	let humanResults2 = Array(try rbdb.query(sql: "SELECT * FROM human"))
	#expect(humanResults2.count == 1, "Should insert one human")
	#expect(
		humanResults2[0]["name"] as? String == "Socrates",
		"The inserted being should be Socrates (after drop)")

	// Check that Socrates is now inferred to be mortal
	let mortalResults = Array(try rbdb.query(sql: "SELECT * FROM mortal"))
	#expect(mortalResults.count == 1, "Should infer one mortal being")
	#expect(mortalResults[0]["entity"] as? String == "Socrates", "Socrates should be mortal")
}

@Test("Simple inference: doesn't select duplicates")
func simpleHumanMortalInference2() async throws {
	let rbdb = try RBDB(path: ":memory:")

	try rbdb.query(sql: "CREATE TABLE human(name TEXT)")
	try rbdb.query(sql: "CREATE TABLE mortal(entity TEXT)")

	// Assert the rule: mortal(X) :- human(X)  (all humans are mortal)
	let X = Var()
	let rule = Formula.hornClause(
		positive: Predicate(name: "mortal", arguments: [.variable(X)]),
		negative: [Predicate(name: "human", arguments: [.variable(X)])]
	)

	try rbdb.assert(formula: rule)

	// Insert a human
	try rbdb.query(sql: "INSERT INTO human(name) VALUES ('Socrates')")
	try rbdb.query(sql: "INSERT INTO mortal(entity) VALUES ('Socrates')")

	// Check that Socrates is now inferred to be mortal (only once)
	let mortalResults = Array(try rbdb.query(sql: "SELECT * FROM mortal"))
	#expect(mortalResults.count == 1, "Should infer one mortal being")
	#expect(mortalResults[0]["entity"] as? String == "Socrates", "Socrates should be mortal")
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

@Test("Chained inference: human -> mortal -> finite")
func chainedInference() async throws {
	let rbdb = try RBDB(path: ":memory:")

	// Create tables
	try rbdb.query(sql: "CREATE TABLE human(name TEXT)")
	try rbdb.query(sql: "CREATE TABLE mortal(name TEXT)")
	try rbdb.query(sql: "CREATE TABLE finite(name TEXT)")

	// Assert rules:
	// Rule 1: mortal(X) :- human(X)
	let X = Var()
	let rule1 = Formula.hornClause(
		positive: Predicate(name: "mortal", arguments: [.variable(X)]),
		negative: [Predicate(name: "human", arguments: [.variable(X)])]
	)
	try rbdb.assert(formula: rule1)

	// Rule 2: finite(Y) :- mortal(Y)
	let Y = Var()
	let rule2 = Formula.hornClause(
		positive: Predicate(name: "finite", arguments: [.variable(Y)]),
		negative: [Predicate(name: "mortal", arguments: [.variable(Y)])]
	)
	try rbdb.assert(formula: rule2)

	// Insert a human
	try rbdb.query(sql: "INSERT INTO human(name) VALUES ('Aristotle')")

	// Check intermediate inference: mortal
	let mortalResults = Array(try rbdb.query(sql: "SELECT * FROM mortal"))
	#expect(mortalResults.count == 1, "Should infer one mortal being")
	#expect(mortalResults[0]["name"] as? String == "Aristotle")

	// Check final inference: finite
	let finiteResults = Array(try rbdb.query(sql: "SELECT * FROM finite"))
	#expect(finiteResults.count == 1, "Should infer one finite being")
	#expect(finiteResults[0]["name"] as? String == "Aristotle")
}

@Test("Multiple premises: grandparent relationship")
func multiplePremisesInference() async throws {
	let rbdb = try RBDB(path: ":memory:")

	// Create tables
	try rbdb.query(sql: "CREATE TABLE parent(parent TEXT, child TEXT)")
	try rbdb.query(sql: "CREATE TABLE grandparent(grandparent TEXT, grandchild TEXT)")

	// Assert rule: grandparent(X,Z) :- parent(X,Y), parent(Y,Z)
	let X = Var()
	let Y = Var()
	let Z = Var()

	let grandparentRule = Formula.hornClause(
		positive: Predicate(name: "grandparent", arguments: [.variable(X), .variable(Z)]),
		negative: [
			Predicate(name: "parent", arguments: [.variable(X), .variable(Y)]),
			Predicate(name: "parent", arguments: [.variable(Y), .variable(Z)]),
		]
	)

	try rbdb.assert(formula: grandparentRule)

	// Insert parent relationships: Alice -> Bob -> Charlie
	try rbdb.query(sql: "INSERT INTO parent(parent, child) VALUES ('Alice', 'Bob')")
	try rbdb.query(
		sql:
			"INSERT INTO parent(parent, child) VALUES ('Bob', 'Charlie')")

	// Check that Alice is inferred to be Charlie's grandparent
	let grandparentResults = Array(try rbdb.query(sql: "SELECT * FROM grandparent"))
	#expect(grandparentResults.count == 1, "Should infer one grandparent relationship")
	#expect(grandparentResults[0]["grandparent"] as? String == "Alice")
	#expect(grandparentResults[0]["grandchild"] as? String == "Charlie")
}

@Test("No inference when premises not satisfied")
func noInferenceWhenPremisesNotSatisfied() async throws {
	let rbdb = try RBDB(path: ":memory:")

	// Create tables
	try rbdb.query(sql: "CREATE TABLE student(name TEXT)")
	try rbdb.query(sql: "CREATE TABLE enrolled(name TEXT, course TEXT)")
	try rbdb.query(sql: "CREATE TABLE graduate(name TEXT)")

	// Assert rule: graduate(X) :- student(X), enrolled(X, "CS101")
	let X = Var()
	let graduateRule = Formula.hornClause(
		positive: Predicate(name: "graduate", arguments: [.variable(X)]),
		negative: [
			Predicate(name: "student", arguments: [.variable(X)]),
			Predicate(name: "enrolled", arguments: [.variable(X), .string("CS101")]),
		]
	)

	try rbdb.assert(formula: graduateRule)

	// Insert a student but not the enrollment
	try rbdb.query(sql: "INSERT INTO student(name) VALUES ('Alice')")
	// Note: NOT inserting into enrolled table

	// Check that no graduate is inferred (premises not satisfied)
	let graduateResults = Array(try rbdb.query(sql: "SELECT * FROM graduate"))
	#expect(graduateResults.count == 0, "Should not infer any graduates without all premises")

	// Now add the missing premise
	try rbdb.query(
		sql:
			"INSERT INTO enrolled(name, course) VALUES ('Alice', 'CS101')")

	// Now Alice should be inferred as a graduate
	let graduateResults2 = Array(try rbdb.query(sql: "SELECT * FROM graduate"))
	#expect(graduateResults2.count == 1, "Should now infer one graduate")
	#expect(graduateResults2[0]["name"] as? String == "Alice")
}

@Test("Multiple facts trigger multiple inferences")
func multipleFactsMultipleInferences() async throws {
	let rbdb = try RBDB(path: ":memory:")

	// Create tables
	try rbdb.query(sql: "CREATE TABLE animal(name TEXT)")
	try rbdb.query(sql: "CREATE TABLE mammal(name TEXT)")

	// Assert rule: mammal(X) :- animal(X)  (all animals are mammals - simplified)
	let X = Var()
	let mammalRule = Formula.hornClause(
		positive: Predicate(name: "mammal", arguments: [.variable(X)]),
		negative: [Predicate(name: "animal", arguments: [.variable(X)])]
	)

	try rbdb.assert(formula: mammalRule)

	// Insert multiple animals
	try rbdb.query(sql: "INSERT INTO animal(name) VALUES ('Dog')")
	try rbdb.query(sql: "INSERT INTO animal(name) VALUES ('Cat')")
	try rbdb.query(sql: "INSERT INTO animal(name) VALUES ('Elephant')")

	// Check that all animals are inferred to be mammals
	let mammalResults = Array(try rbdb.query(sql: "SELECT * FROM mammal ORDER BY name"))
	#expect(mammalResults.count == 3, "Should infer three mammals")

	let names = mammalResults.compactMap { $0["name"] as? String }.sorted()
	#expect(names == ["Cat", "Dog", "Elephant"], "All animals should be inferred as mammals")
}

@Test func recursiveRule() async throws {
	let rbdb = try RBDB(path: ":memory:")
	try rbdb.query(sql: "CREATE TABLE parent(a TEXT, b TEXT)")
	try rbdb.query(sql: "CREATE TABLE ancestor(a TEXT, b TEXT)")

	let X = Var()
	let Y = Var()
	let Z = Var()

	// Rule 1: ancestor(X, Y) :- parent(X, Y)
	let rule1 = Formula.hornClause(
		positive: Predicate(name: "ancestor", arguments: [.variable(X), .variable(Y)]),
		negative: [Predicate(name: "parent", arguments: [.variable(X), .variable(Y)])]
	)
	try rbdb.assert(formula: rule1)

	// Rule 2: ancestor(X, Z) :- parent(X, Y), ancestor(Y, Z)  (2 negative literals)
	let rule2 = Formula.hornClause(
		positive: Predicate(name: "ancestor", arguments: [.variable(X), .variable(Z)]),
		negative: [
			Predicate(name: "parent", arguments: [.variable(X), .variable(Y)]),
			Predicate(name: "ancestor", arguments: [.variable(Y), .variable(Z)]),
		]
	)
	try rbdb.assert(formula: rule2)

	try rbdb.query(sql: "INSERT INTO parent(a, b) VALUES ('john', 'douglas')")
	try rbdb.query(sql: "INSERT INTO parent(a, b) VALUES ('mary', 'john')")
	let ancestorResults = try rbdb.query(sql: "SELECT * FROM ancestor")
	#expect(Array(ancestorResults).count == 3)
}
