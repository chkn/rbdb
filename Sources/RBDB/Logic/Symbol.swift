public protocol Symbol: Comparable, Codable {
	var type: SymbolType { get }
	func accept<V: SymbolVisitor>(visitor: V) -> Self
}

public protocol SymbolVisitor {
	func visit(formula: Formula) -> Formula
	func visit(term: Term) -> Term
	func visit(variable: Var) -> Var
}
