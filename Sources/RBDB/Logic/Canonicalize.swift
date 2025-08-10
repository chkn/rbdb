class CanonicalizeVisitor: VariableCollectingVisitor, SymbolVisitor {

	override func map(variable: Var) -> Var {
		Var(id: UInt8(variableMapping.count))
	}

	func visit(formula: Formula) -> Formula {
		switch formula {
		case .hornClause(positive: let positive, negative: let negatives):
			let canonicalPositive = visit(predicate: positive)
			let canonicalNegatives = negatives.map(visit(predicate:)).sorted()
			return .hornClause(positive: canonicalPositive, negative: canonicalNegatives)
		}
	}
}

extension Symbol {
	public func canonicalize() -> Self {
		accept(visitor: CanonicalizeVisitor())
	}
}
