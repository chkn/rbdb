public final class Var: Sendable {
	public let name: String?

	public init(_ name: String? = nil) {
		self.name = name
	}

	/// Creates a new variable from an integer ID.
	///
	/// - Parameter id: An unsigned 8-bit value representing the variable index.
	///   Values 0-25 map to "A"-"Z", 26-51 map to "AA"-"AZ", 52-77 map to "BA"-"BZ", etc.
	public init(id: UInt8) {
		if id <= 25 {
			// Single letter: A-Z
			let scalar = UnicodeScalar(65 + Int(id))!
			self.name = String(scalar)
		} else {
			// Multi-letter: AA, AB, ..., AZ, BA, BB, ..., etc.
			let adjustedId = Int(id) - 26
			let firstLetter = adjustedId / 26
			let secondLetter = adjustedId % 26

			let firstScalar = UnicodeScalar(65 + firstLetter)!
			let secondScalar = UnicodeScalar(65 + secondLetter)!
			self.name = String(firstScalar) + String(secondScalar)
		}
	}

	/// The integer ID of a canonical variable.
	public var id: UInt8? {
		guard let name else { return nil }

		if name.count == 1 {
			// Single letter: A-Z maps to 0-25
			guard let scalar = name.unicodeScalars.first, scalar.value >= 65, scalar.value <= 90
			else {
				return nil
			}
			return UInt8(scalar.value - 65)
		} else if name.count == 2 {
			// Two letters: AA-ZZ maps to 26+
			let scalars = Array(name.unicodeScalars)
			guard scalars.count == 2,
				scalars[0].value >= 65, scalars[0].value <= 90,
				scalars[1].value >= 65, scalars[1].value <= 90
			else {
				return nil
			}

			let firstLetter = Int(scalars[0].value - 65)
			let secondLetter = Int(scalars[1].value - 65)
			let id = 26 + firstLetter * 26 + secondLetter

			// Check if it fits in UInt8
			guard id <= 255 else { return nil }
			return UInt8(id)
		} else {
			// Variables with more than 2 characters are not supported for ID conversion
			return nil
		}
	}
}

extension Var: Comparable {
	public static func == (lhs: Var, rhs: Var) -> Bool {
		if let lhsID = lhs.name, let rhsID = rhs.name {
			return lhsID == rhsID
		} else {
			return lhs === rhs
		}
	}

	public static func < (lhs: Var, rhs: Var) -> Bool {
		if let lhsID = lhs.name, let rhsID = rhs.name {
			return lhsID < rhsID
		} else {
			return ObjectIdentifier(lhs) < ObjectIdentifier(rhs)
		}
	}
}

extension Var: Hashable {
	public func hash(into hasher: inout Hasher) {
		if let name = self.name {
			hasher.combine(name)
		} else {
			hasher.combine(ObjectIdentifier(self))
		}
	}
}

extension Var: CustomStringConvertible {
	public var description: String {
		name ?? String(format: "0x%llx", UInt(bitPattern: ObjectIdentifier(self)))
	}
}
