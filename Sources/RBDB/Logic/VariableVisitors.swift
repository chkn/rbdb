import Foundation

/// Derive from this and conform to the `SymbolRewriter` protocol.
class VariableMappingRewriter {
	var variableMapping: [ObjectIdentifier: Var] = [:]

	func map(variable: Var) -> Var { variable }

	func rewrite(variable: Var) -> Var {
		let varId = ObjectIdentifier(variable)

		if let existingVar = variableMapping[varId] {
			return existingVar
		} else {
			let mappedVar = map(variable: variable)
			variableMapping[varId] = mappedVar
			return mappedVar
		}
	}
}

struct VariableCollector: SymbolReducer {
	func reduce(_ prev: [ObjectIdentifier: Var], _ variable: Var) -> [ObjectIdentifier: Var] {
		var variables = prev
		variables[ObjectIdentifier(variable)] = variable
		return variables
	}
}
