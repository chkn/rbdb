import RBDB
import Parsing

/// Parser for Datalog syntax into RBDB Formula objects.
public struct DatalogParser: ParserPrinter {

	private class Context {
		private var variables: [String: Var] = [:]

		func getVariable(name: String) -> Var {
			if let existingVar = variables[name] {
				return existingVar
			}
			let newVar = Var(name)
			variables[name] = newVar
			return newVar
		}
	}
	private let ctx = Context()

	public init() {}

	public var body: some ParserPrinter<Substring, Formula> {
		ParsePrint {
			Whitespace()
			hornClauseParser
			Whitespace()
		}
	}
}

// MARK: - Horn Clause Parser

extension DatalogParser {
	private var hornClauseParser: some ParserPrinter<Substring, Formula> {
		// FIXME: Swift really want a type annotation for this
		let emptyPredicates: [Predicate] = []
		return ParsePrint(.case(Formula.hornClause)) {
			// Head
			predicateParser

			Whitespace()

			Optionally {
				":-".printing(" :- ")
				Whitespace()
				Many {
					predicateParser
					Whitespace()
				} separator: {
					","
					Whitespace().printing(" ".utf8)
				}
			}.map(.orDefault(emptyPredicates))

			Whitespace()

			// Optional period at the end
			".".replaceError(with: ())
		}
	}
}

// MARK: - Predicate Parser

extension DatalogParser {
	private var predicateParser: some ParserPrinter<Substring, Predicate> {
		ParsePrint(.memberwise(Predicate.init(name:arguments:))) {
			// Parse predicate name (identifier)
			identifierParser

			// Parse arguments in parentheses
			"("
			Whitespace()

			// Parse comma-separated terms, or empty
			Many {
				termParser
				Whitespace()
			} separator: {
				","
				Whitespace().printing(" ".utf8)
			}

			Whitespace()
			")"
		}
	}
}

// MARK: - Term Parser

extension DatalogParser {
	private var termParser: some ParserPrinter<Substring, Term> {
		OneOf {
			// Variables (start with uppercase or _)
			variableParser.map(.case(Term.variable))

			// Quoted strings
			quotedStringParser.map(.case(Term.string))

			// Numbers
			numberParser.map(.case(Term.number))

			// Atoms (lowercase identifiers) - treated as strings
			atomParser.map(.case(Term.string))
		}
	}

	private var variableParser: some ParserPrinter<Substring, Var> {
		ParsePrint {
			// Variables start with uppercase letter or underscore
			Peek {
				Prefix(1) { char in
					char.isUppercase || char == "_"
				}
			}
			// Followed by alphanumeric characters or underscores
			Prefix { char in
				char.isLetter || char.isNumber || char == "_"
			}
		}.map(
			.convert(
				apply: { ctx.getVariable(name: String($0)) },
				unapply: { String(describing: $0)[...] }
			)
		)
	}

	private var quotedStringParser: some ParserPrinter<Substring, String> {
		OneOf {
			// Single-quoted strings (parse only, always print as double-quoted)
			Parse {
				"'"
				Prefix { $0 != "'" }.map(.string)
				"'"
			}
			// Double-quoted strings (default for printing)
			ParsePrint {
				"\""
				Prefix { $0 != "\"" }.map(.string)
				"\""
			}
		}
	}

	private var numberParser: some ParserPrinter<Substring.UTF8View, Float> {
		Float.parser()
	}

	private var atomParser: some ParserPrinter<Substring, String> {
		identifierParser
	}

	private var identifierParser: some ParserPrinter<Substring, String> {
		ParsePrint {
			// Start with letter or underscore
			Peek {
				Prefix(1) { char in
					char.isLetter || char == "_"
				}
			}
			// Followed by alphanumeric characters or underscores
			Prefix { char in
				char.isLetter || char.isNumber || char == "_"
			}
		}
		.map(.string)
	}
}

extension Conversion {
	@inlinable
	public static func orDefault<T: Equatable>(_ defaultValue: T) -> Self
	where Self == Conversions.OrDefault<T> {
		return .init(defaultValue: defaultValue)
	}
}

extension Conversions {
	public struct OrDefault<T: Equatable>: Conversion {
		public let defaultValue: T

		@inlinable
		public init(defaultValue: T) {
			self.defaultValue = defaultValue
		}

		@inlinable
		public func apply(_ input: T?) throws -> T {
			return input ?? defaultValue
		}

		@inlinable
		public func unapply(_ output: T) -> T? {
			return output == defaultValue ? nil : output
		}
	}
}
