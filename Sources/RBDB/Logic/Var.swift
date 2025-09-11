public final class Var: Sendable {
	let id: UInt8?

	public init(id: UInt8? = nil) {
		self.id = id
	}
}

extension Var: Comparable {
	public static func == (lhs: Var, rhs: Var) -> Bool {
		if let lhsID = lhs.id, let rhsID = rhs.id {
			return lhsID == rhsID
		} else {
			return lhs === rhs
		}
	}

	public static func < (lhs: Var, rhs: Var) -> Bool {
		if let lhsID = lhs.id, let rhsID = rhs.id {
			return lhsID < rhsID
		} else {
			return ObjectIdentifier(lhs) < ObjectIdentifier(rhs)
		}
	}
}

extension Var: Hashable {
	public func hash(into hasher: inout Hasher) {
		if let id = self.id {
			hasher.combine(id)
		} else {
			hasher.combine(ObjectIdentifier(self))
		}
	}
}

extension Var: CustomStringConvertible {
	public var description: String {
		if let id = self.id {
			let scalar = UnicodeScalar(65 + Int(id))!
			return String(scalar)
		} else {
			return String(format: "0x%llx", UInt(bitPattern: ObjectIdentifier(self)))
		}
	}
}
