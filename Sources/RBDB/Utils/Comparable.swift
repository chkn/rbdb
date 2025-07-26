// Technically a little naughty to declare retroactive conformance here,
//  but I think it's ok because we don't care about the specific semantics
//  of the comparison, as long as it's consistent, so would prolly be fine
//  if a different implementation were used.
extension Array: @retroactive Comparable where Element: Comparable {
	public static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.lexicographicallyPrecedes(rhs)
	}
}

// For this one, we DO care about getting this implementation...
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
