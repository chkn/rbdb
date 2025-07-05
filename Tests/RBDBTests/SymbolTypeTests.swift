import Foundation
import Testing
@testable import RBDB

@Test func serializeConstantType() async throws {
	try assertJSON(SymbolType.constant, expect: "\"\"")
}

@Test func serializeVariableType() async throws {
	try assertJSON(SymbolType.variable, expect: "\"id\"")
}

@Test func serializeRelationType() async throws {
	try assertJSON(SymbolType.predicate(name: "Foo", arity: 2), expect: "\"2Foo\"")
}

@Test func serializeQuantifiedType() async throws {
    try assertJSON(SymbolType.quantified(.predicate(name: "Foo", arity: 2)), expect: "\"2Foo#\"")
}

@Test func serializeNestedQuantifiedType() async throws {
    try assertJSON(SymbolType.quantified(.quantified(.predicate(name: "Foo", arity: 2))), expect: "\"2Foo##\"")
}
