
public enum SymbolType: Comparable {
	// terms
	case constant
	case variable

	public var isTerm: Bool {
		switch self {
		case .constant, .variable: true
		default: false
		}
	}

	// formulas
	/// Maximum arity is 9
	case predicate(name: String, arity: UInt8)
	indirect case quantified(SymbolType)

	public var isFormula: Bool {
		switch self {
		case .predicate, .quantified: true
		default: false
		}
	}
}

extension SymbolType: Codable {
	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		let str = try container.decode(String.self)
		if let value = SymbolType(stringValue: str) {
			self = value
		} else {
			throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid SymbolType string \(str)"))
		}
	}

	public func encode(to encoder: Encoder) throws {
		// Validate
		if case .predicate(name: _, arity: let arity) = self, arity > 9 {
			throw EncodingError.invalidValue(arity, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Predicate arity must be less than or equal to 9"))
		}
		var container = encoder.singleValueContainer()
		try container.encode(stringValue)
	}
}

// Conforms to CodingKey because it's used as the key for Term
extension SymbolType: CodingKey {
	public var stringValue: String {
		switch self {
		case .constant: ""
		case .variable: "id"
		case .predicate(name: let name, arity: let arity): String(arity) + name
		case .quantified(let ty): "\(ty.stringValue)#"
		}
	}
	public init?(stringValue: String) {
		if stringValue.last == "#" {
			let str = String(stringValue.dropLast())
			guard let ty = SymbolType(stringValue: str) else { return nil }
			self = .quantified(ty)
		} else {
			switch stringValue {
			case "": self = .constant
			case "id": self = .variable
			default:
				var str = stringValue
				guard let arity = UInt8(String(str.removeFirst())) else { return nil }
				self = .predicate(name: str, arity: arity)
			}
		}
	}

	public var intValue: Int? { nil }
	public init?(intValue: Int) { nil }
}
