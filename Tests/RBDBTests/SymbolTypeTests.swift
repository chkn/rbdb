import Foundation
import Testing
@testable import RBDB

@Test func serializeConstantType() async throws {
	try assertJSON(SymbolType.constant, expect: "\"\"")
}

@Test func serializeVariableType() async throws {
	try assertJSON(SymbolType.variable, expect: "\"v\"")
}

@Test func serializeRelationType() async throws {
	try assertJSON(SymbolType.hornClause(positiveName: "Foo"), expect: "\"@Foo\"")
}
