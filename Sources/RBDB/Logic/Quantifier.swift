public enum Quantifier: Comparable, Codable, LosslessStringConvertible {
	case forAll
	case thereExists

	public var description: String {
		switch self {
		case .forAll: "∀"
		case .thereExists: "∃"
		}
	}

	public init?(_ description: String) {
		switch description.lowercased() {
		case "∀", "forall": self = .forAll
		case "∃", "exists": self = .thereExists
		default: return nil
		}
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		let value = try container.decode(Int.self)
		switch value {
		case 0: self = .forAll
		case 1: self = .thereExists
		default:
			throw DecodingError.dataCorruptedError(
				in: container,
				debugDescription: "Invalid Quantifier raw value: \(value)"
			)
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
