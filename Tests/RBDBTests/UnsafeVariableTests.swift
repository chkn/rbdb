import Foundation
import Testing
@testable import RBDB

@Test("Reject horn clause with variable only in head")
func rejectVariableOnlyInHead() async throws {
	let rbdb = try RBDB(path: ":memory:")

	// Create tables
	try rbdb.query("CREATE TABLE human(name TEXT)")
	try rbdb.query("CREATE TABLE mortal(name TEXT, age INT)")

	// Unsafe rule: human(X) -> mortal(X, Y)
	// Y appears only in head, not in body - this is unsafe!
	let varX = Var(id: 0)  // X - safe, appears in both head and body
	let varY = Var(id: 1)  // Y - UNSAFE, appears only in head

	let unsafeRule = Formula.hornClause(
		positive: Predicate(name: "mortal", arguments: [.variable(varX), .variable(varY)]),
		negative: [Predicate(name: "human", arguments: [.variable(varX)])]
	)

	// This should throw an error about unsafe variables
	#expect(throws: (any Error).self) {
		try rbdb.assert(formula: unsafeRule)
	}
}

@Test("Accept horn clause with all variables safe")
func acceptAllVariablesSafe() async throws {
	let rbdb = try RBDB(path: ":memory:")

	// Create tables
	try rbdb.query("CREATE TABLE human(name TEXT)")
	try rbdb.query("CREATE TABLE mortal(name TEXT)")

	// Safe rule: human(X) -> mortal(X)
	// X appears in both head and body - this is safe
	let varX = Var(id: 0)

	let safeRule = Formula.hornClause(
		positive: Predicate(name: "mortal", arguments: [.variable(varX)]),
		negative: [Predicate(name: "human", arguments: [.variable(varX)])]
	)

	// This should succeed (no unsafe variables)
	try rbdb.assert(formula: safeRule)
}

@Test("Reject horn clause with multiple unsafe variables")
func rejectMultipleUnsafeVariables() async throws {
	let rbdb = try RBDB(path: ":memory:")

	// Create tables
	try rbdb.query("CREATE TABLE person(name TEXT)")
	try rbdb.query("CREATE TABLE relationship(person1 TEXT, person2 TEXT, type TEXT)")

	// Unsafe rule: person(X) -> relationship(X, Y, Z)
	// Y and Z appear only in head - both unsafe!
	let varX = Var(id: 0)  // X - safe
	let varY = Var(id: 1)  // Y - UNSAFE
	let varZ = Var(id: 2)  // Z - UNSAFE

	let unsafeRule = Formula.hornClause(
		positive: Predicate(
			name: "relationship", arguments: [.variable(varX), .variable(varY), .variable(varZ)]),
		negative: [Predicate(name: "person", arguments: [.variable(varX)])]
	)

	// This should throw an error about unsafe variables
	#expect(throws: (any Error).self) {
		try rbdb.assert(formula: unsafeRule)
	}
}

@Test("Accept horn clause with variables in multiple body predicates")
func acceptVariablesInMultipleBodyPredicates() async throws {
	let rbdb = try RBDB(path: ":memory:")

	// Create tables
	try rbdb.query("CREATE TABLE parent(parent TEXT, child TEXT)")
	try rbdb.query("CREATE TABLE person(name TEXT)")
	try rbdb.query("CREATE TABLE grandparent(grandparent TEXT, grandchild TEXT)")

	// Safe rule: parent(X, Y) ∧ parent(Y, Z) -> grandparent(X, Z)
	// All variables X, Y, Z appear in the body predicates
	let varX = Var(id: 0)  // X - appears in first body predicate
	let varY = Var(id: 1)  // Y - appears in both body predicates (bridging variable)
	let varZ = Var(id: 2)  // Z - appears in second body predicate

	let safeRule = Formula.hornClause(
		positive: Predicate(name: "grandparent", arguments: [.variable(varX), .variable(varZ)]),
		negative: [
			Predicate(name: "parent", arguments: [.variable(varX), .variable(varY)]),
			Predicate(name: "parent", arguments: [.variable(varY), .variable(varZ)]),
		]
	)

	// This should succeed (all variables are safe)
	try rbdb.assert(formula: safeRule)
}

@Test("Accept horn clause with constants and safe variables")
func acceptConstantsAndSafeVariables() async throws {
	let rbdb = try RBDB(path: ":memory:")

	// Create tables
	try rbdb.query("CREATE TABLE student(name TEXT, major TEXT)")
	try rbdb.query("CREATE TABLE honor_student(name TEXT)")

	// Safe rule: student(X, "Computer Science") -> honor_student(X)
	// X appears in both head and body, constant "Computer Science" is always safe
	let varX = Var(id: 0)

	let safeRule = Formula.hornClause(
		positive: Predicate(name: "honor_student", arguments: [.variable(varX)]),
		negative: [
			Predicate(name: "student", arguments: [.variable(varX), .string("Computer Science")])
		]
	)

	// This should succeed
	try rbdb.assert(formula: safeRule)
}

@Test("Accept horn clause with no variables (all constants)")
func acceptAllConstants() async throws {
	let rbdb = try RBDB(path: ":memory:")

	// Create tables
	try rbdb.query("CREATE TABLE config(key TEXT, value TEXT)")
	try rbdb.query("CREATE TABLE system_ready(status TEXT)")

	// Safe rule: config("debug", "true") -> system_ready("ready")
	// No variables at all - this is always safe
	let safeRule = Formula.hornClause(
		positive: Predicate(name: "system_ready", arguments: [.string("ready")]),
		negative: [Predicate(name: "config", arguments: [.string("debug"), .string("true")])]
	)

	// This should succeed
	try rbdb.assert(formula: safeRule)
}
