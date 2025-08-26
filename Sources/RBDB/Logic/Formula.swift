public enum Formula: Symbol {
	case hornClause(positive: Predicate, negative: [Predicate])

	public static func predicate(_ predicate: Predicate) -> Formula {
		.hornClause(positive: predicate, negative: [])
	}

	public var type: SymbolType {
		switch self {
		case .hornClause(positive: let positive, negative: _):
			.hornClause(positiveName: positive.name)
		}
	}

	public var description: String {
		switch self {
		case .hornClause(positive: let predicate, negative: let negatives):
			let positiveStr = String(describing: predicate)
			if negatives.isEmpty {
				return positiveStr
			}

			var negativeStr = negatives.map { String(describing: $0) }.joined(separator: " ∧ ")
			if negatives.count > 1 {
				negativeStr = "(\(negativeStr))"
			}

			return "\(negativeStr) -> \(positiveStr)"
		}
	}

	public init?(_ description: String) {
		var trimmed = description.trimmingCharacters(
			in: .whitespacesAndNewlines
		)

		// Try horn clause: "negatives -> positive"
		if let arrowIndex = trimmed.range(of: " -> ") {
			let negativesStr = String(trimmed[..<arrowIndex.lowerBound]).trimmingCharacters(
				in: .whitespacesAndNewlines)
			let positiveStr = String(trimmed[arrowIndex.upperBound...]).trimmingCharacters(
				in: .whitespacesAndNewlines)

			// Parse positive predicate
			guard let positive = Predicate(positiveStr) else { return nil }

			// Parse negative predicates
			var negatives: [Predicate] = []

			// Handle parentheses around multiple negatives: "(foo(x) ∧ bar(y))"
			var negativesPart = negativesStr
			if negativesPart.hasPrefix("(") && negativesPart.hasSuffix(")") {
				negativesPart = String(negativesPart.dropFirst().dropLast())
			}

			// Split by " ∧ " for multiple negatives
			let negativeStrs = negativesPart.components(separatedBy: " ∧ ")
			for negativeStr in negativeStrs {
				let trimmedNegative = negativeStr.trimmingCharacters(in: .whitespacesAndNewlines)
				guard let negative = Predicate(trimmedNegative) else { return nil }
				negatives.append(negative)
			}

			self = .hornClause(positive: positive, negative: negatives)
			return
		}

		if trimmed.hasPrefix("(") && trimmed.hasSuffix(")") {
			trimmed = String(trimmed.dropFirst().dropLast())
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

	public func rewrite<T: SymbolRewriter>(_ rewriter: T) -> Formula {
		rewriter.rewrite(formula: self)
	}

	public func reduce<T: SymbolReducer>(_ initialResult: T.Result, _ reducer: T) -> T.Result {
		reducer.reduce(initialResult, self)
	}
}

extension SymbolRewriter {
	public func rewrite(formula: Formula) -> Formula {
		switch formula {
		case .hornClause(positive: let positive, negative: let negatives):
			.hornClause(
				positive: rewrite(predicate: positive),
				negative: negatives.map(rewrite(predicate:))
			)
		}
	}

	public func rewrite(predicate: Predicate) -> Predicate {
		Predicate(name: predicate.name, arguments: predicate.arguments.map(rewrite(term:)))
	}
}

extension SymbolReducer {
	public func reduce(_ prev: Result, _ formula: Formula) -> Result {
		switch formula {
		case .hornClause(positive: let positive, negative: let negatives):
			negatives.reduce(reduce(prev, positive), reduce)
		}
	}

	public func reduce(_ prev: Result, _ predicate: Predicate) -> Result {
		predicate.arguments.reduce(prev, reduce)
	}
}

extension Formula: Codable {
	public init(from decoder: Decoder) throws {
		var arr = try decoder.unkeyedContainer()
		let key = try arr.decode(SymbolType.self)

		switch key {
		case .hornClause(let positiveName):
			var args: [Term] = []
			var positiveArgs = try arr.nestedUnkeyedContainer()
			while !positiveArgs.isAtEnd {
				args.append(try positiveArgs.decode(Term.self))
			}
			let positive = Predicate(name: positiveName, arguments: args)

			var negatives: [Predicate] = []
			while !arr.isAtEnd {
				negatives.append(try arr.decode(Predicate.self))
			}
			self = .hornClause(positive: positive, negative: negatives)
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
		try arr.encode(type)
		switch self {
		case .hornClause(positive: let positive, negative: let negatives):
			var positiveArr = arr.nestedUnkeyedContainer()
			for arg in positive.arguments {
				try positiveArr.encode(arg)
			}
			for negative in negatives {
				try arr.encode(negative)
			}
		}
	}
}
