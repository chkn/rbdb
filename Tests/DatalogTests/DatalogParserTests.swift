import Testing
@testable import Datalog
@testable import RBDB

@Test("Parse simple facts")
func parseSimpleFacts() throws {
	let parser = DatalogParser()

	// Test simple fact: parent(alice, bob).
	let result1 = try parser.parse("parent(alice, bob)")
	let expected1 = Formula.hornClause(
		positive: Predicate(name: "parent", arguments: [.string("alice"), .string("bob")]),
		negative: []
	)
	#expect(result1 == expected1)

	// Test fact with numbers: age(alice, 30)
	let result2 = try parser.parse("age(alice, 30)")
	let expected2 = Formula.hornClause(
		positive: Predicate(name: "age", arguments: [.string("alice"), .number(30.0)]),
		negative: []
	)
	#expect(result2 == expected2)

	// Test fact with quoted strings: name(1, "Alice Smith")
	let result3 = try parser.parse("name(1, \"Alice Smith\")")
	let expected3 = Formula.hornClause(
		positive: Predicate(name: "name", arguments: [.number(1.0), .string("Alice Smith")]),
		negative: []
	)
	#expect(result3 == expected3)
}

@Test("Parse facts with variables")
func parseFactsWithVariables() throws {
	let parser = DatalogParser()

	// Test fact with variable: person(X)
	let result = try parser.parse("person(X)")

	// Create expected formula with a variable and use canonicalize to compare
	let expectedVar = Var()
	let expected = Formula.hornClause(
		positive: Predicate(name: "person", arguments: [.variable(expectedVar)]),
		negative: []
	)

	// Use canonicalize to compare formulas with variables
	#expect(result.canonicalize() == expected.canonicalize())
}

@Test("Parse simple rules")
func parseSimpleRules() throws {
	let parser = DatalogParser()

	// Test rule: grandparent(X, Z) :- parent(X, Y), parent(Y, Z)
	let result = try parser.parse("grandparent(X, Z) :- parent(X, Y), parent(Y, Z)")

	// Create expected formula with variables and use canonicalize to compare
	let X = Var()
	let Y = Var()
	let Z = Var()
	let expected = Formula.hornClause(
		positive: Predicate(name: "grandparent", arguments: [.variable(X), .variable(Z)]),
		negative: [
			Predicate(name: "parent", arguments: [.variable(X), .variable(Y)]),
			Predicate(name: "parent", arguments: [.variable(Y), .variable(Z)]),
		]
	)

	// Use canonicalize to compare formulas with variables
	#expect(result.canonicalize() == expected.canonicalize())
}

@Test("Parse mixed rules with constants and variables")
func parseMixedRules() throws {
	let parser = DatalogParser()

	// Test rule: adult(X) :- age(X, 18)
	let result = try parser.parse("adult(X) :- age(X, 18)")

	// Create expected formula and use canonicalize to compare
	let X = Var()
	let expected = Formula.hornClause(
		positive: Predicate(name: "adult", arguments: [.variable(X)]),
		negative: [
			Predicate(name: "age", arguments: [.variable(X), .number(18.0)])
		]
	)

	// Use canonicalize to compare formulas with variables
	#expect(result.canonicalize() == expected.canonicalize())
}

@Test("Parse with periods and whitespace")
func parseWithPeriodsAndWhitespace() throws {
	let parser = DatalogParser()

	// Test with trailing period
	let result1 = try parser.parse("parent(alice, bob).")
	let expected = Formula.hornClause(
		positive: Predicate(name: "parent", arguments: [.string("alice"), .string("bob")]),
		negative: []
	)
	#expect(result1 == expected)

	// Test with extra whitespace
	let result2 = try parser.parse("  parent( alice , bob )  .  ")
	#expect(result2 == expected)

	// Test rule with whitespace and period
	let result3 = try parser.parse("  grandparent(X, Z) :- parent(X, Y) , parent(Y, Z)  .  ")

	// Create expected formula and use canonicalize to compare
	let X2 = Var()
	let Y2 = Var()
	let Z2 = Var()
	let expected3 = Formula.hornClause(
		positive: Predicate(name: "grandparent", arguments: [.variable(X2), .variable(Z2)]),
		negative: [
			Predicate(name: "parent", arguments: [.variable(X2), .variable(Y2)]),
			Predicate(name: "parent", arguments: [.variable(Y2), .variable(Z2)]),
		]
	)

	// Use canonicalize to compare formulas with variables
	#expect(result3.canonicalize() == expected3.canonicalize())
}

@Test("Print simple facts")
func printSimpleFacts() throws {
	let parser = DatalogParser()

	// Test simple fact
	let fact1 = Formula.hornClause(
		positive: Predicate(name: "parent", arguments: [.string("alice"), .string("bob")]),
		negative: []
	)
	let printed1 = try parser.print(fact1)
	#expect(printed1 == "parent(alice, bob)")

	// Test fact with numbers
	let fact2 = Formula.hornClause(
		positive: Predicate(name: "age", arguments: [.string("alice"), .number(30.0)]),
		negative: []
	)
	let printed2 = try parser.print(fact2)
	#expect(printed2 == "age(alice, 30.0)")

	// Test fact with quoted strings
	let fact3 = Formula.hornClause(
		positive: Predicate(name: "name", arguments: [.number(1.0), .string("Alice Smith")]),
		negative: []
	)
	let printed3 = try parser.print(fact3)
	#expect(printed3 == "name(1.0, \"Alice Smith\")")
}

@Test("Print rules")
func printRules() throws {
	let parser = DatalogParser()

	// Create variables for testing with specific IDs
	let X = Var(id: 23)  // X
	let Y = Var(id: 24)  // Y
	let Z = Var(id: 25)  // Z

	// Test simple rule
	let rule = Formula.hornClause(
		positive: Predicate(name: "grandparent", arguments: [.variable(X), .variable(Z)]),
		negative: [
			Predicate(name: "parent", arguments: [.variable(X), .variable(Y)]),
			Predicate(name: "parent", arguments: [.variable(Y), .variable(Z)]),
		]
	)

	let printed = try parser.print(rule)
	// Variables with IDs 23, 24, 25 should print as X, Y, Z
	#expect(printed == "grandparent(X, Z) :- parent(X, Y), parent(Y, Z)")
}

@Test("Round-trip parsing and printing")
func roundTripParsingAndPrinting() throws {
	let parser = DatalogParser()

	// Test facts round-trip
	let factStrings = [
		"parent(alice, bob)",
		"age(alice, 30.0)",
		"name(1.0, \"Alice Smith\")",
	]

	for factString in factStrings {
		let parsed = try parser.parse(factString)
		let printed = try parser.print(parsed)
		let reparsed = try parser.parse(printed)
		#expect(parsed == reparsed)
	}
}
