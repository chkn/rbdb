import Foundation
import Testing

@testable import RBDB

@Test func serializeVariable() async throws {
	try assertJSON(Term.variable(Var(id: 42)), expect: "{\"v\":42}")
}

@Test func serializeBooleanConstant() async throws {
	try assertJSON(Term.boolean(true), expect: "{\"\":true}")
	try assertJSON(Term.boolean(false), expect: "{\"\":false}")
}

@Test func serializeIntConstant() async throws {
	try assertJSON(Term.number(5), expect: "{\"\":5}")
	try assertJSON(Term.number(-5), expect: "{\"\":-5}")
	try assertJSON(Term.number(0), expect: "{\"\":0}")
}

@Test func serializeFloatConstant() async throws {
	try assertJSON(Term.number(5.7), expect: "{\"\":5.7}")
	try assertJSON(Term.number(-5.123), expect: "{\"\":-5.123}")
	#expect(throws: EncodingError.self) {
		try assertJSON(Term.number(Float.nan), expect: "")
	}
}

@Test func serializeStringConstant() async throws {
	try assertJSON(Term.string("hi mom"), expect: "{\"\":\"hi mom\"}")
	try assertJSON(Term.string("123"), expect: "{\"\":\"123\"}")
	try assertJSON(Term.string("true"), expect: "{\"\":\"true\"}")
	try assertJSON(Term.string(""), expect: "{\"\":\"\"}")
}

@Test func deserializeWithNoKeysThrows() async throws {
	let dec = JSONDecoder()
	let data = "{}".data(using: .utf8)!
	#expect(throws: DecodingError.self) {
		let _ = try dec.decode(Term.self, from: data)
	}
}

@Test func deserializeWithUnknownType() async throws {
	let dec = JSONDecoder()
	let data = "{\"----UNKNOWN KEY---\": \"foo\"}".data(using: .utf8)!
	#expect(throws: DecodingError.self) {
		let _ = try dec.decode(Term.self, from: data)
	}
}

@Test func deserializeWithExtraneousUnknownType() async throws {
	let dec = JSONDecoder()
	let data = "{\"----UNKNOWN KEY---\": \"foo\",\"\":\"bar\"}".data(
		using: .utf8
	)!
	let result = try dec.decode(Term.self, from: data)
	#expect(result == .string("bar"))
}

@Test func deserializePrefersLaterDefinedTypes1() async throws {
	let dec = JSONDecoder()
	let data = "{\"\":\"bar\",\"v\":5}".data(using: .utf8)!
	let result = try dec.decode(Term.self, from: data)
	#expect(result == .variable(Var(id: 5)))
}

@Test func deserializePrefersLaterDefinedTypes2() async throws {
	let dec = JSONDecoder()
	let data = "{\"v\":5,\"\":\"bar\"}".data(using: .utf8)!
	let result = try dec.decode(Term.self, from: data)
	#expect(result == .variable(Var(id: 5)))
}

// String conversion tests
@Test func termStringConversions() async throws {
	// Test boolean terms
	#expect(Term.boolean(true).description == "true")
	#expect(Term.boolean(false).description == "false")
	#expect(Term("true") == Term.boolean(true))
	#expect(Term("false") == Term.boolean(false))

	// Test number terms
	#expect(Term.number(42.0).description == "42.0")
	#expect(Term.number(3.14).description == "3.14")
	#expect(Term("42.0") == Term.number(42.0))
	#expect(Term("3.14") == Term.number(3.14))

	// Test string terms
	#expect(Term.string("hello").description == "\"hello\"")
	#expect(Term.string("world").description == "\"world\"")
	#expect(Term("\"hello\"") == Term.string("hello"))
	#expect(Term("\"world\"") == Term.string("world"))

	// Test variable terms
	let varA = Var(id: 0)
	let varB = Var(id: 1)
	#expect(Term.variable(varA).description == "a")
	#expect(Term.variable(varB).description == "b")
	#expect(Term("a") == Term.variable(Var(id: 0)))
	#expect(Term("b") == Term.variable(Var(id: 1)))
}

@Test func termStringConversionsRoundTrip() async throws {
	let terms: [Term] = [
		.boolean(true),
		.boolean(false),
		.number(42.0),
		.number(3.14),
		.string("hello"),
		.string("world with spaces"),
		.variable(Var(id: 0)),
		.variable(Var(id: 25)),  // 'z'
	]

	for term in terms {
		let description = term.description
		let parsed = Term(description)
		#expect(parsed == term, "Failed round-trip for term: \(term)")
	}
}
