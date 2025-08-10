import Foundation

public enum FormulaValidationError: Error, Equatable {
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

class UnsafeVariableCollector: VariableCollectingVisitor, SymbolVisitor {
	var unsafeVariables: [Var] = []

	func visit(formula: Formula) -> Formula {
		switch formula {
		case .hornClause(positive: let positive, negative: let negatives):
			if !negatives.isEmpty {
				_ = visit(predicate: positive)
				let headVariables = variableMapping

				variableMapping.removeAll()
				for negative in negatives {
					_ = visit(predicate: negative)
				}
				let bodyVariables = variableMapping

				for v in headVariables {
					if bodyVariables[v.key] == nil {
						unsafeVariables.append(v.value)
					}
				}
			}
		}
		return formula
	}
}

extension Formula {
	/// Validates this `Formula` and throws a `FormulaValidationError` if it fails validation.
	func validate() throws {
		let collector = UnsafeVariableCollector()
		_ = accept(visitor: collector)
		if !collector.unsafeVariables.isEmpty {
			throw FormulaValidationError.unsafeVariables(collector.unsafeVariables)
		}
	}
}
