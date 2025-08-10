import Foundation

class VariableCollectingVisitor {
	var variableMapping: [ObjectIdentifier: Var] = [:]

	func map(variable: Var) -> Var { variable }

	func visit(variable: Var) -> Var {
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
