import Foundation
import Testing

@testable import RBDB

@Test func serializePredicate() async throws {
	try assertJSON(
		Formula.predicate(Predicate(name: "Foo", arguments: [.string("bar")])),
		expect: "[\"@foo\",[{\"\":\"bar\"}]]"
	)
}

@Test func deserializeBadPredicate() async throws {
	let dec = JSONDecoder()
	let data = "[\"1Foo\"]".data(using: .utf8)!
	#expect(throws: DecodingError.self) {
		let _ = try dec.decode(Formula.self, from: data)
	}
}

// String conversion tests
@Test func formulaStringConversions() async throws {
	// Test simple predicate
	let simple = Formula.predicate(Predicate(name: "Foo", arguments: []))
	#expect(simple.description == "foo()")
	#expect(Formula("foo()") == simple)

	// Test predicate with arguments
	let withArgs = Formula.predicate(
		Predicate(
			name: "Bar",
			arguments: [.string("hello"), .number(42.0), .boolean(true)]
		))
	#expect(withArgs.description == "bar(\"hello\", 42.0, true)")
	#expect(Formula("bar(\"hello\", 42.0, true)") == withArgs)

}

@Test func formulaStringConversionsRoundTrip() async throws {
	let formulas: [Formula] = [
		.predicate(Predicate(name: "Foo", arguments: [])),
		.predicate(Predicate(name: "Bar", arguments: [.string("test"), .number(3.14)])),
	]

	for formula in formulas {
		let description = formula.description
		let parsed = Formula(description)
		#expect(parsed == formula, "Failed round-trip for formula: \(formula)")
	}
}

@Test func formulasWithDifferentVariableNamesCanonicalizeEqually() async throws {
	// Test that formulas with the same structure but different variable names
	// become equal after canonicalization

	// Create different Var instances for the same logical variable
	let varA = Var(id: 0)  // represents 'a'
	let varB = Var(id: 1)  // represents 'b'
	let varZ = Var(id: 25)  // represents 'z'

	// These represent the same logical formula but with different variable names
	let formula1 = Formula.predicate(Predicate(name: "p", arguments: [.variable(varA)]))
	let formula2 = Formula.predicate(Predicate(name: "p", arguments: [.variable(varB)]))
	let formula3 = Formula.predicate(Predicate(name: "p", arguments: [.variable(varZ)]))

	// Before canonicalization, they should NOT be equal (different variable IDs)
	#expect(formula1 != formula2)
	#expect(formula2 != formula3)
	#expect(formula1 != formula3)

	// After canonicalization, they should be equal (same logical structure)
	let canonical1 = formula1.canonicalize()
	let canonical2 = formula2.canonicalize()
	let canonical3 = formula3.canonicalize()

	#expect(canonical1 == canonical2)
	#expect(canonical2 == canonical3)
	#expect(canonical1 == canonical3)

	// Test more complex formulas with multiple variables
	let varX = Var(id: 23)  // represents 'x'
	let varY = Var(id: 24)  // represents 'y'
	let varM = Var(id: 12)  // represents 'm'
	let varN = Var(id: 13)  // represents 'n'

	let complex1 = Formula.predicate(
		Predicate(name: "p", arguments: [.variable(varX), .variable(varY)]))
	let complex2 = Formula.predicate(
		Predicate(name: "p", arguments: [.variable(varA), .variable(varB)]))
	let complex3 = Formula.predicate(
		Predicate(name: "p", arguments: [.variable(varM), .variable(varN)]))

	// Before canonicalization, they should NOT be equal
	#expect(complex1 != complex2)
	#expect(complex2 != complex3)

	// After canonicalization, they should be equal
	let complexCanonical1 = complex1.canonicalize()
	let complexCanonical2 = complex2.canonicalize()
	let complexCanonical3 = complex3.canonicalize()

	#expect(complexCanonical1 == complexCanonical2)
	#expect(complexCanonical2 == complexCanonical3)
	#expect(complexCanonical1 == complexCanonical3)
}

@Test func hornClausesCanonicalizeEquallyRegardlessOfNegativeOrder() async throws {
	// Test that horn clauses with the same positive and negative predicates
	// canonicalize equally regardless of the order of negative predicates

	let positive = Predicate(name: "conclusion", arguments: [.string("result")])
	let negative1 = Predicate(name: "premise1", arguments: [.string("a")])
	let negative2 = Predicate(name: "premise2", arguments: [.string("b")])
	let negative3 = Predicate(name: "premise3", arguments: [.string("c")])

	// Create horn clauses with the same predicates but different orders of negatives
	let hornClause1 = Formula.hornClause(
		positive: positive,
		negative: [negative1, negative2, negative3]
	)
	let hornClause2 = Formula.hornClause(
		positive: positive,
		negative: [negative3, negative1, negative2]  // Different order
	)
	let hornClause3 = Formula.hornClause(
		positive: positive,
		negative: [negative2, negative3, negative1]  // Another different order
	)

	// Before canonicalization, they should NOT be equal (different order)
	#expect(hornClause1 != hornClause2)
	#expect(hornClause2 != hornClause3)
	#expect(hornClause1 != hornClause3)

	// After canonicalization, they should be equal (same logical content)
	let canonical1 = hornClause1.canonicalize()
	let canonical2 = hornClause2.canonicalize()
	let canonical3 = hornClause3.canonicalize()

	#expect(
		canonical1 == canonical2,
		"Horn clauses with different negative order should canonicalize equally")
	#expect(
		canonical2 == canonical3,
		"Horn clauses with different negative order should canonicalize equally")
	#expect(
		canonical1 == canonical3,
		"Horn clauses with different negative order should canonicalize equally")
}

@Test func parseHornClausesWithNegatives() async throws {
	// Test parsing horn clauses with negative literals
	// These should match the description format: "negatives -> positive"

	// Test single negative literal
	let singleNegative = "foo(\"x\") -> bar(\"y\")"
	let expectedSingle = Formula.hornClause(
		positive: Predicate(name: "bar", arguments: [.string("y")]),
		negative: [Predicate(name: "foo", arguments: [.string("x")])]
	)

	// This should now work with the horn clause parsing implementation
	let parsedSingle = Formula(singleNegative)
	#expect(parsedSingle == expectedSingle, "Failed to parse single negative horn clause")

	// Test multiple negative literals
	let multipleNegatives = "(foo(\"x\") ∧ baz(\"z\")) -> bar(\"y\")"
	let expectedMultiple = Formula.hornClause(
		positive: Predicate(name: "bar", arguments: [.string("y")]),
		negative: [
			Predicate(name: "foo", arguments: [.string("x")]),
			Predicate(name: "baz", arguments: [.string("z")]),
		]
	)

	// This should now work with the horn clause parsing implementation
	let parsedMultiple = Formula(multipleNegatives)
	#expect(parsedMultiple == expectedMultiple, "Failed to parse multiple negative horn clause")
}
