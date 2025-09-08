public struct Predicate: Equatable, Comparable {
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

extension Predicate: Codable {
	public func encode(to encoder: Encoder) throws {
		var container = encoder.unkeyedContainer()
		try container.encode(name)
		for arg in arguments {
			try container.encode(arg)
		}
	}

	public init(from decoder: Decoder) throws {
		var container = try decoder.unkeyedContainer()
		let name = try container.decode(String.self)
		var args: [Term] = []
		while !container.isAtEnd {
			let term = try container.decode(Term.self)
			args.append(term)
		}
		self.init(name: name, arguments: args)
	}
}
