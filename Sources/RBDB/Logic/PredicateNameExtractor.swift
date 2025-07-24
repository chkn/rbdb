import Foundation

class PredicateNameExtractor: SymbolVisitor {
	var predicateNames = Set<String>()

	func visit(predicate name: String, arguments args: [Term]) -> Formula {
		predicateNames.insert(name)
		return .predicate(name: name, arguments: args.map(visit(term:)))
	}

	static func run<S: Symbol>(_ symbol: S) -> Set<String> {
		let visitor = PredicateNameExtractor()
		_ = symbol.accept(visitor: visitor)
		return visitor.predicateNames
	}
}
