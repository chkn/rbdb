import Foundation

struct PredicateNameExtractor: SymbolReducer {
	func reduce(_ predicateNames: Set<String>, _ predicate: Predicate) -> Set<String> {
		var names = predicateNames
		names.insert(predicate.name)
		return names
	}
}

extension Symbol {
	public func getPredicateNames() -> Set<String> {
		reduce(Set<String>(), PredicateNameExtractor())
	}
}
