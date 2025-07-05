
public struct Var {
	var id: Int

	public init(id: Int) {
		self.id = id
	}
}

extension Var: Comparable {
	public static func < (lhs: Var, rhs: Var) -> Bool {
		lhs.id < rhs.id
	}
}
