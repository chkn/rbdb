import Foundation

/// Utility functions for parsing delimited strings with proper handling of nested structures
enum StringParsing {
	/// Splits a string by delimiter, respecting parentheses and optional quote handling
	static func split(
		_ string: String,
		by delimiter: Character
	) -> [String] {
		var components: [String] = []
		var current = ""
		var parenDepth = 0
		var inQuotes = false

		for char in string {
			switch char {
			case "\"":
				current.append(char)
				inQuotes.toggle()
			case "(":
				current.append(char)
				if !inQuotes { parenDepth += 1 }
			case ")":
				current.append(char)
				if !inQuotes { parenDepth -= 1 }
			case delimiter:
				if !inQuotes && parenDepth == 0 {
					components.append(
						current.trimmingCharacters(in: .whitespacesAndNewlines)
					)
					current = ""
				} else {
					current.append(char)
				}
			default:
				current.append(char)
			}
		}

		if !current.isEmpty {
			components.append(
				current.trimmingCharacters(in: .whitespacesAndNewlines)
			)
		}

		return components
	}
}
