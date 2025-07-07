import Foundation
import Testing
@testable import RBDB

@Test func serializePredicate() async throws {
	try assertJSON(Formula.predicate(name: "Foo", arguments: [Term.string("bar")]), expect: "[\"@Foo\",{\"\":\"bar\"}]")
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
	try assertJSON(Formula.quantified(.forAll, a, Formula.predicate(name: "Foo", arguments: [.variable(a)])), expect: "[\"@Foo#\",0,0,[\"@Foo\",{\"id\":0}]]")
}
