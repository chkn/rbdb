
public enum Term: Symbol {
	case variable(Var)

	// constants
	case boolean(Bool)
	case number(Float)
	case string(String)

	public var type: SymbolType {
		switch self {
		case .variable: .variable
		case .boolean, .number, .string: .constant
		}
	}
}

extension Term: Codable {
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: SymbolType.self)

		// Take the last key here because we want to prefer types added later to the SymbolType enum.
		//  This will allow us to add a new type while not breaking older clients by including a fallback.
		if let key = container.allKeys.sorted().last(where: { $0.isTerm }) {
			switch key {
			case .variable:
				self = .variable(Var(id: try container.decode(UInt8.self, forKey: key)))

			// This is a bit naughty, but it keeps the json very concise. We could store the expected constant
			//  data type in SymbolType, but that opens the door to data anomalies where the actual type of the
			//  value doesn't jibe with the declared type.
			case .constant:
				// Bool last because it's probably least frequently used type
				if let stringValue = try? container.decode(String.self, forKey: key) {
					self = .string(stringValue)
				} else if let floatValue = try? container.decode(Float.self, forKey: key) {
					self = .number(floatValue)
				} else if let boolValue = try? container.decode(Bool.self, forKey: key) {
					self = .boolean(boolValue)
				} else {
					throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid constant value"))
				}
			default:
				// should never get here
				fatalError()
			}
		} else {
			throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No valid term symbol type key found"))
		}
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: SymbolType.self)
		switch self {
		case .variable(let v): try container.encode(v.id, forKey: .variable)
		case .boolean(let value): try container.encode(value, forKey: .constant)
		case .number(let value): try container.encode(value, forKey: .constant)
		case .string(let value): try container.encode(value, forKey: .constant)
		}
	}
}

extension [Term]: @retroactive Comparable {
	public static func <(lhs: Self, rhs: Self) -> Bool {
		lhs.lexicographicallyPrecedes(rhs)
	}
}

extension Bool: @retroactive Comparable {
   public static func < (lhs: Bool, rhs: Bool) -> Bool {
	   // We use false < true.
	   //  This sort order is important, because SQLite uses 0 for false, and 1 for true,
	   //  so it will use the same sort order.
	   //
	   // lhs | rhs | result
	   // ------------------
	   //  f  |  t  |  t
	   //  f  |  f  |  f
	   //  t  |  t  |  f
	   //  t  |  f  |  f
	   !lhs && rhs
   }
}
