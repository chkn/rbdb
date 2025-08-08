class CanonicalizeVisitor: SymbolVisitor {
	private var varMapping: [ObjectIdentifier: Var] = [:]

	func visit(variable: Var) -> Var {
		let varId = ObjectIdentifier(variable)

		if let existingVar = varMapping[varId] {
			return existingVar
		} else {
			let newVar = Var(id: UInt8(varMapping.count))
			varMapping[varId] = newVar
			return newVar
		}
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
		self.accept(visitor: CanonicalizeVisitor())
	}
}
