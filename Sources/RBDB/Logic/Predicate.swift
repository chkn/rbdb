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

extension Predicate: LosslessStringConvertible {
	public var description: String {
		"\(name)(\(arguments.map({ String(describing: $0) }).joined(separator: ", ")))"
	}

	public init?(_ description: String) {
		// Parse a predicate string like "name(arg1, arg2, ...)"
		guard let match = description.wholeMatch(of: /^(\w+)\(([^)]*)\)$/) else { return nil }

		let name = String(match.1)
		let argsString = String(match.2).trimmingCharacters(in: .whitespacesAndNewlines)

		var arguments: [Term] = []
		if !argsString.isEmpty {
			let argStrings = StringParsing.split(argsString, by: ",")
			for argString in argStrings {
				guard let term = Term(argString) else { return nil }
				arguments.append(term)
			}
		}

		self.init(name: name, arguments: arguments)
	}
}
