
public enum Quantifier: Comparable, Codable {
	case forAll
	case thereExists

	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		let value = try container.decode(Int.self)
		switch value {
		case 0: self = .forAll
		case 1: self = .thereExists
		default:
			throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Quantifier raw value: \(value)")
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		switch self {
		case .forAll: try container.encode(0)
		case .thereExists: try container.encode(1)
		}
	}
}

public enum Formula: Symbol {
	case predicate(name: String, arguments: [Term])
	indirect case quantified(_ quantifier: Quantifier, _ variable: Var, _ body: Formula)

	public var type: SymbolType {
		switch self {
		case .predicate(let name, let args): .predicate(name: name, arity: UInt8(args.count))
		case .quantified(_, _, let body): .quantified(body.type)
		}
	}
}

extension Formula: Codable {
	public init(from decoder: Decoder) throws {
		var arr = try decoder.unkeyedContainer()
		let key = try arr.decode(SymbolType.self)

		switch key {
		case .predicate(let name, let arity):
			var args: [Term] = []
			args.reserveCapacity(Int(arity))
			for _ in 0..<arity {
				args.append(try arr.decode(Term.self))
			}
			self = .predicate(name: name, arguments: args)
		case .quantified:
			self = .quantified(try arr.decode(Quantifier.self), Var(id: try arr.decode(Int.self)), try arr.decode(Formula.self))
		default:
			throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No valid formula symbol type key found"))
		}
	}

	public func encode(to encoder: Encoder) throws {
		var arr = encoder.unkeyedContainer()
		switch self {
		case .predicate(let name, let args):
			try arr.encode(SymbolType.predicate(name: name, arity: UInt8(args.count)))
			for arg in args {
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
