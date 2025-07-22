import Foundation
import Testing

@testable import RBDB

@Test func serializePredicate() async throws {
	try assertJSON(
		Formula.predicate(name: "Foo", arguments: [.string("bar")]),
		expect: "[\"@Foo\",{\"\":\"bar\"}]"
	)
}

@Test func deserializeBadPredicate() async throws {
	let dec = JSONDecoder()
	let data = "[\"1Foo\"]".data(using: .utf8)!
	#expect(throws: DecodingError.self) {
		let _ = try dec.decode(Formula.self, from: data)
	}
}

@Test func serializeQuantified() async throws {
	let a = Var(id: 0)
	try assertJSON(
		Formula.quantified(
			.forAll,
			a,
			.predicate(name: "Foo", arguments: [.variable(a)])
		),
		expect: "[\"@Foo#\",0,0,[\"@Foo\",{\"v\":0}]]"
	)
}

// String conversion tests
@Test func formulaStringConversions() async throws {
	// Test simple predicate
	let simple = Formula.predicate(name: "Foo", arguments: [])
	#expect(simple.description == "Foo()")
	#expect(Formula("Foo()") == simple)

	// Test predicate with arguments
	let withArgs = Formula.predicate(
		name: "Bar",
		arguments: [.string("hello"), .number(42.0), .boolean(true)]
	)
	#expect(withArgs.description == "Bar(\"hello\", 42.0, true)")
	#expect(Formula("Bar(\"hello\", 42.0, true)") == withArgs)

	// Test quantified formula
	let varA = Var(id: 0)
	let quantified = Formula.quantified(
		.forAll,
		varA,
		.predicate(name: "P", arguments: [.variable(varA)])
	)
	#expect(quantified.description == "∀a P(a)")
	#expect(Formula("∀a P(a)") == quantified)
	#expect(Formula("∀a(P(a))") == quantified)

	// Test text quantified formulas
	#expect(Formula("forall a P(a)") == quantified)
	#expect(Formula("forall a. P(a)") == quantified)

	let existential = Formula.quantified(
		.thereExists,
		varA,
		.predicate(name: "P", arguments: [.variable(varA)])
	)
	#expect(Formula("exists a P(a)") == existential)
	#expect(Formula("exists a. P(a)") == existential)

	// Test nested quantified formula
	let varB = Var(id: 1)
	let nested = Formula.quantified(.thereExists, varB, quantified)
	#expect(nested.description == "∃b ∀a P(a)")
	#expect(Formula("∃b ∀a P(a)") == nested)
	#expect(Formula("∃b∀a(P(a))") == nested)
}

@Test func formulaStringConversionsRoundTrip() async throws {
	let formulas: [Formula] = [
		.predicate(name: "Foo", arguments: []),
		.predicate(name: "Bar", arguments: [.string("test"), .number(3.14)]),
		.quantified(
			.forAll,
			Var(id: 0),
			.predicate(name: "P", arguments: [.variable(Var(id: 0))])
		),
		.quantified(
			.thereExists,
			Var(id: 1),
			.predicate(
				name: "Q",
				arguments: [.boolean(false), .variable(Var(id: 1))]
			)
		),
	]

	for formula in formulas {
		let description = formula.description
		let parsed = Formula(description)
		#expect(parsed == formula, "Failed round-trip for formula: \(formula)")
	}
}

@Test func formulasWithDifferentVariableNamesCanonicalizeEqually() async throws {
	// Test that formulas with the same structure but different variable names
	// become equal after parsing and canonicalization

	// These represent the same logical formula but with different variable names
	let formula1String = "∀a P(a)"
	let formula2String = "∀b P(b)"
	let formula3String = "∀z P(z)"

	// Parse the formulas
	guard let parsed1 = Formula(formula1String),
		let parsed2 = Formula(formula2String),
		let parsed3 = Formula(formula3String)
	else {
		#expect(Bool(false), "Failed to parse formulas")
		return
	}

	// Before canonicalization, they should NOT be equal (different variable instances)
	#expect(parsed1 != parsed2)
	#expect(parsed2 != parsed3)
	#expect(parsed1 != parsed3)

	// After canonicalization, they should be equal (same logical structure)
	let canonical1 = parsed1.canonicalize()
	let canonical2 = parsed2.canonicalize()
	let canonical3 = parsed3.canonicalize()

	#expect(canonical1 == canonical2)
	#expect(canonical2 == canonical3)
	#expect(canonical1 == canonical3)

	// Test more complex formulas
	let complex1String = "∀x ∃y P(x, y)"
	let complex2String = "∀a ∃b P(a, b)"
	let complex3String = "∀m ∃n P(m, n)"

	guard let complexParsed1 = Formula(complex1String),
		let complexParsed2 = Formula(complex2String),
		let complexParsed3 = Formula(complex3String)
	else {
		#expect(Bool(false), "Failed to parse complex formulas")
		return
	}

	// Before canonicalization, they should NOT be equal
	#expect(complexParsed1 != complexParsed2)
	#expect(complexParsed2 != complexParsed3)

	// After canonicalization, they should be equal
	let complexCanonical1 = complexParsed1.canonicalize()
	let complexCanonical2 = complexParsed2.canonicalize()
	let complexCanonical3 = complexParsed3.canonicalize()

	#expect(complexCanonical1 == complexCanonical2)
	#expect(complexCanonical2 == complexCanonical3)
	#expect(complexCanonical1 == complexCanonical3)
}
