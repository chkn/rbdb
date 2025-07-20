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
