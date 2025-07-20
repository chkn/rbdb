
class CanonicalizeVisitor: SymbolVisitor {
	private var counter: UInt8 = 0

	func visit(variable: Var) -> Var {
		if variable.id == nil {
			let newVar = Var(id: counter)
			counter += 1
			return newVar
		} else {
			return variable
		}
	}
}

extension Symbol {
	public func canonicalize() -> Self {
		self.accept(visitor: CanonicalizeVisitor())
	}
}
