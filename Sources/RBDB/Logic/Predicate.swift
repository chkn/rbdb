public struct Predicate: Equatable, Comparable, Codable {
	public let name: String
	public let arguments: [Term]

	public init(name: String, arguments: [Term]) {
		self.name = name.lowercased()
		self.arguments = arguments
	}

	public static func < (lhs: Predicate, rhs: Predicate) -> Bool {
		if lhs.name != rhs.name {
			return lhs.name < rhs.name
		}
		return lhs.arguments.lexicographicallyPrecedes(rhs.arguments)
	}
}
