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
	func reduce(_ prev: [Var], _ formula: Formula) -> [Var] {
		var unsafeVariables = prev
		let collector = VariableCollector()

		switch formula {
		case .hornClause(positive: let positive, negative: let negatives):
			let headVariables = collector.reduce([:], positive)

			var bodyVariables: [ObjectIdentifier: Var] = [:]
			for negative in negatives {
				bodyVariables.merge(collector.reduce([:], negative), uniquingKeysWith: { $1 })
			}

			// Check for unsafe variables in the head
			for v in headVariables {
				if bodyVariables[v.key] == nil {
					unsafeVariables.append(v.value)
				}
			}
		}

		return unsafeVariables
	}
}

extension Symbol {
	/// Validates this `Symbol` and throws a `FormulaValidationError` if it fails validation.
	func validate() throws {
		let unsafeVariables = reduce([], UnsafeVariableCollector())
		if !unsafeVariables.isEmpty {
			throw ValidationError.unsafeVariables(unsafeVariables)
		}
	}
}
