class CanonicalizeRewriter: VariableMappingRewriter, SymbolRewriter {

	override func map(variable: Var) -> Var {
		Var(id: UInt8(variableMapping.count))
	}

	func rewrite(formula: Formula) -> Formula {
		switch formula {
		case .hornClause(positive: let positive, negative: let negatives):
			.hornClause(
				positive: rewrite(predicate: positive),
				negative: negatives.map(rewrite(predicate:)).sorted())
		}
	}
}

extension Symbol {
	public func canonicalize() -> Self {
		rewrite(CanonicalizeRewriter())
	}
}
