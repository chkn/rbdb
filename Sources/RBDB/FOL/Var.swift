public class Var {
	// Set once the enclosing formula is canonicalized
	var id: UInt8? = nil

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

extension Var: CustomStringConvertible {
	public var description: String {
		if let id = self.id {
			let scalar = UnicodeScalar(97 + Int(id))!
			return String(scalar)
		} else {
			return String(format: "0x%llx", UInt(bitPattern: ObjectIdentifier(self)))
		}
	}
}
