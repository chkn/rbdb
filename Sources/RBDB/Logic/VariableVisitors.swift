import Foundation

/// Derive from this and conform to the `SymbolRewriter` protocol.
class VariableMappingRewriter {
	var variableMapping: [Var: Var] = [:]

	func map(variable: Var) -> Var { variable }

	func rewrite(variable: Var) -> Var {
		if let existingVar = variableMapping[variable] {
			return existingVar
		} else {
			let mappedVar = map(variable: variable)
			variableMapping[variable] = mappedVar
			return mappedVar
		}
	}
}

struct VariableCollector: SymbolReducer {
	func reduce(_ prev: Set<Var>, _ variable: Var) throws -> Set<Var> {
		var variables = prev
		variables.insert(variable)
		return variables
	}
}

extension Symbol {
	public func getVariables() throws -> [Var] {
		Array(try reduce(Set(), VariableCollector()))
	}
}
