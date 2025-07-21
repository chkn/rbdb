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
}

extension Symbol {
	public func canonicalize() -> Self {
		self.accept(visitor: CanonicalizeVisitor())
	}
}
