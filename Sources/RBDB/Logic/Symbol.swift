public protocol Symbol: Comparable, Codable, LosslessStringConvertible {
	var type: SymbolType { get }
	func accept<V: SymbolVisitor>(visitor: V) -> Self
}

public protocol SymbolVisitor {
	func visit(formula: Formula) -> Formula
	func visit(predicate: Predicate) -> Predicate
	func visit(term: Term) -> Term
	func visit(variable: Var) -> Var
}
