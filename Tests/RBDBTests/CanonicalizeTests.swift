import Foundation
import Testing
@testable import RBDB

@Test func canonicalizeFormulasWithSeparateVarInstances() async throws {
	// Create two separate Var instances with no IDs (so they are different objects)
	let var1 = Var()
	let var2 = Var()

	// Create two identical predicates using different Var instances
	let formula1 = Formula.predicate(Predicate(name: "Foo", arguments: [.variable(var1)]))
	let formula2 = Formula.predicate(Predicate(name: "Foo", arguments: [.variable(var2)]))

	// Before canonicalization, formulas should NOT be equal (different Var instances)
	#expect(formula1 != formula2)

	// After canonicalization, formulas should be equal (canonicalized variables)
	let canonicalized1 = formula1.canonicalize()
	let canonicalized2 = formula2.canonicalize()

	#expect(canonicalized1 == canonicalized2)
}
