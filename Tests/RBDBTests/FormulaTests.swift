import Foundation
import Testing

@testable import RBDB

@Test func serializePredicate() async throws {
	try assertJSON(
		Formula.predicate(Predicate(name: "Foo", arguments: [.string("bar")])),
		expect: "[\"@foo\",{\"\":\"bar\"}]"
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
			.predicate(Predicate(name: "Foo", arguments: [.variable(a)]))
		),
		expect: "[\"@foo#\",0,0,[\"@foo\",{\"v\":0}]]"
	)
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

	// Test quantified formula
	let varA = Var(id: 0)
	let quantified = Formula.quantified(
		.forAll,
		varA,
		.predicate(Predicate(name: "P", arguments: [.variable(varA)]))
	)
	#expect(quantified.description == "∀a p(a)")
	#expect(Formula("∀a p(a)") == quantified)
	#expect(Formula("∀a(p(a))") == quantified)

	// Test text quantified formulas
	#expect(Formula("forall a p(a)") == quantified)
	#expect(Formula("forall a. p(a)") == quantified)

	let existential = Formula.quantified(
		.thereExists,
		varA,
		.predicate(Predicate(name: "P", arguments: [.variable(varA)]))
	)
	#expect(Formula("exists a p(a)") == existential)
	#expect(Formula("exists a. p(a)") == existential)

	// Test nested quantified formula
	let varB = Var(id: 1)
	let nested = Formula.quantified(.thereExists, varB, quantified)
	#expect(nested.description == "∃b ∀a p(a)")
	#expect(Formula("∃b ∀a p(a)") == nested)
	#expect(Formula("∃b∀a(p(a))") == nested)
}

@Test func formulaStringConversionsRoundTrip() async throws {
	let formulas: [Formula] = [
		.predicate(Predicate(name: "Foo", arguments: [])),
		.predicate(Predicate(name: "Bar", arguments: [.string("test"), .number(3.14)])),
		.quantified(
			.forAll,
			Var(id: 0),
			.predicate(Predicate(name: "P", arguments: [.variable(Var(id: 0))]))
		),
		.quantified(
			.thereExists,
			Var(id: 1),
			.predicate(
				Predicate(
					name: "Q",
					arguments: [.boolean(false), .variable(Var(id: 1))]
				))
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
	let formula1String = "∀a p(a)"
	let formula2String = "∀b p(b)"
	let formula3String = "∀z p(z)"

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
	let complex1String = "∀x ∃y p(x, y)"
	let complex2String = "∀a ∃b p(a, b)"
	let complex3String = "∀m ∃n p(m, n)"

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
