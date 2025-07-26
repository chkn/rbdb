import Foundation

class PredicateNameExtractor: SymbolVisitor {
	var predicateNames = Set<String>()

	func visit(predicate: Predicate) -> Predicate {
		predicateNames.insert(predicate.name)
		return predicate
	}

}

extension Symbol {
	public func getPredicateNames() -> Set<String> {
		let visitor = PredicateNameExtractor()
		_ = self.accept(visitor: visitor)
		return visitor.predicateNames
	}
}
