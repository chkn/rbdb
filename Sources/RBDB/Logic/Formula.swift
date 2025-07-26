public enum Formula: Symbol {
	case predicate(Predicate)
	indirect case quantified(
		_ quantifier: Quantifier,
		_ variable: Var,
		_ body: Formula
	)

	public var type: SymbolType {
		switch self {
		case .predicate(let predicate): .predicate(name: predicate.name)
		case .quantified(_, _, let body): .quantified(body.type)
		}
	}

	public var description: String {
		switch self {
		case .predicate(let predicate):
			"\(predicate.name)(\(predicate.arguments.map({ String(describing: $0) }).joined(separator: ", ")))"
		case .quantified(let quantifier, let v, let body):
			"\(quantifier)\(v) \(body)"
		}
	}

	public init?(_ description: String) {
		var trimmed = description.trimmingCharacters(
			in: .whitespacesAndNewlines
		)
		if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
			trimmed = String(trimmed.dropFirst().dropLast())
		}

		// Try quantified formula: "∀a P(a)" or "∃a P(a)"
		if let match = trimmed.wholeMatch(
			of: /^([∀∃]|forall |exists )([a-z])\.?\s*(.+)$/
		) {
			guard
				let quantifier = Quantifier(
					String(match.1.trimmingCharacters(in: .whitespaces))
				),
				let char = match.2.first,
				let body = Formula(String(match.3))
			else { return nil }

			let id = UInt8(char.asciiValue! - 97)
			let variable = Var(id: id)
			self = .quantified(quantifier, variable, body)
			return
		}

		// Try predicate: "Name(args...)"
		if let match = trimmed.wholeMatch(of: /^(\w+)\(([^)]*)\)$/) {
			let name = String(match.1)
			let argsString = String(match.2).trimmingCharacters(
				in: .whitespacesAndNewlines
			)

			var arguments: [Term] = []
			if !argsString.isEmpty {
				let argStrings = StringParsing.split(argsString, by: ",")
				for argString in argStrings {
					guard let term = Term(argString) else { return nil }
					arguments.append(term)
				}
			}

			self = .predicate(Predicate(name: name, arguments: arguments))
			return
		}

		return nil
	}

	public func accept<V>(visitor: V) -> Formula where V: SymbolVisitor {
		visitor.visit(formula: self)
	}
}

extension SymbolVisitor {
	public func visit(formula: Formula) -> Formula {
		switch formula {
		case .predicate(let predicate):
			.predicate(visit(predicate: predicate))
		case .quantified(let q, let v, let body):
			.quantified(q, visit(variable: v), visit(formula: body))
		}
	}

	public func visit(predicate: Predicate) -> Predicate {
		Predicate(name: predicate.name, arguments: predicate.arguments.map(visit(term:)))
	}
}

extension Formula: Codable {
	public init(from decoder: Decoder) throws {
		var arr = try decoder.unkeyedContainer()
		let key = try arr.decode(SymbolType.self)

		switch key {
		case .predicate(let name):
			var args: [Term] = []
			while !arr.isAtEnd {
				args.append(try arr.decode(Term.self))
			}
			self = .predicate(Predicate(name: name, arguments: args))
		case .quantified:
			self = .quantified(
				try arr.decode(Quantifier.self),
				Var(id: try arr.decode(UInt8.self)),
				try arr.decode(Formula.self)
			)
		default:
			throw DecodingError.dataCorrupted(
				DecodingError.Context(
					codingPath: decoder.codingPath,
					debugDescription: "No valid formula symbol type key found"
				)
			)
		}
	}

	public func encode(to encoder: Encoder) throws {
		var arr = encoder.unkeyedContainer()
		switch self {
		case .predicate(let predicate):
			try arr.encode(SymbolType.predicate(name: predicate.name))
			for arg in predicate.arguments {
				try arr.encode(arg)
			}
		case .quantified(let quantifier, let v, let body):
			try arr.encode(SymbolType.quantified(body.type))
			try arr.encode(quantifier)
			try arr.encode(v.id)
			try arr.encode(body)
		}
	}
}
