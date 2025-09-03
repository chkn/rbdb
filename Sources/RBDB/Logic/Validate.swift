import Foundation

public enum ValidationError: Error, Equatable {
	case unsafeVariables([Var])

	public var localizedDescription: String {
		switch self {
		case .unsafeVariables(let variables):
			let varNames = variables.map { "var\($0.id ?? 255)" }.sorted().joined(separator: ", ")
			return
				"Unsafe variables in horn clause head: \(varNames). All variables in the head must also appear in the body."
		}
	}
}

struct UnsafeVariableCollector: SymbolReducer {
	func reduce(_ prev: [Var], _ formula: Formula) throws -> [Var] {
		var unsafeVariables = prev
		let collector = VariableCollector()

		switch formula {
		case .hornClause(positive: let positive, negative: let negatives):
			let headVariables = try collector.reduce(Set(), positive)
			let bodyVariables = try negatives.reduce(
				Set(), { $0.union(try collector.reduce(Set(), $1)) })

			// Check for unsafe variables in the head
			for v in headVariables {
				if !bodyVariables.contains(v) {
					unsafeVariables.append(v)
				}
			}
		}

		return unsafeVariables
	}
}

extension Symbol {
	/// Validates this `Symbol` and throws a `FormulaValidationError` if it fails validation.
	func validate() throws {
		let unsafeVariables = try reduce([], UnsafeVariableCollector())
		if !unsafeVariables.isEmpty {
			throw ValidationError.unsafeVariables(unsafeVariables)
		}
	}
}
