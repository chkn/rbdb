public protocol Symbol: Comparable, Codable {
	var type: SymbolType { get }
}
