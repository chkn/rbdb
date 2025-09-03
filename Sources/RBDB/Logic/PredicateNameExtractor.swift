import Foundation

struct PredicateNameExtractor: SymbolReducer {
	func reduce(_ predicateNames: Set<String>, _ predicate: Predicate) throws -> Set<String> {
		var names = predicateNames
		names.insert(predicate.name)
		return names
	}
}

extension Symbol {
	public func getPredicateNames() throws -> Set<String> {
		try reduce(Set<String>(), PredicateNameExtractor())
	}
}
