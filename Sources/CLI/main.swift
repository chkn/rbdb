#if os(macOS) || os(iOS)
	import Darwin
	typealias TerminalFlag = UInt
#elseif canImport(Glibc)
	// https://github.com/swiftlang/swift/issues/77866
	@preconcurrency import Glibc
	typealias TerminalFlag = UInt32
#else
	#error("Unknown platform")
#endif

import Foundation
import RBDB
import Datalog

let productName = "RBDB Interactive Console"

enum InputMode {
	case sql
	case datalog(isQueryMode: Bool)

	var prompt: String {
		switch self {
		case .sql: return "sql> "
		case .datalog(let isQueryMode):
			return isQueryMode ? "datalog> \u{001B}[90m?- \u{001B}[0m" : "datalog> "
		}
	}

	var displayName: String {
		switch self {
		case .sql: return "SQL"
		case .datalog: return "Datalog"
		}
	}
}

func parseLanguage(_ lang: String) -> InputMode? {
	let normalized = lang.lowercased()
	switch normalized {
	case "s", "sql":
		return .sql
	case "d", "datalog":
		return .datalog(isQueryMode: false)
	default:
		return nil
	}
}

func printUsage() {
	print("Usage: rbdb [options] [database_path]")
	print("  \(productName)")
	print("")
	print("Arguments:")
	print("  database_path        Path to database file (optional)")
	print("                       If not provided, uses in-memory database")
	print("")
	print("Options:")
	print("  --help               Show this help message")
	print("  -f | --file <path>   Execute the commands from the given file")
	print("  -l | --lang <lang>   Set default language: s[ql] or d[atalog] (default: sql)")
	print("")
	print("Commands:")
	print("  .exit                Exit the console")
	print("  .schema              Show database schema")
	print("")
	print("Interactive Mode:")
	print("  Shift+Tab            Switch between SQL and Datalog modes")
	print("  ? (in Datalog)       Enter query mode (not implemented)")
}

func displaySchema(database: SQLiteDatabase) {
	do {
		let results = try database.query(
			sql: "SELECT name, json(column_names) as column_names FROM _predicate ORDER BY name"
		)

		var hasSchema = false
		print("-- TABLES")
		print(String(repeating: "-", count: 50))

		for row in results {
			hasSchema = true
			let name = row["name"] as? String ?? ""
			let columnNamesJson = row["column_names"] as? String ?? ""

			// Parse column names from JSON
			var columnNames: [String] = []
			if let data = columnNamesJson.data(using: .utf8) {
				columnNames = (try? JSONDecoder().decode([String].self, from: data)) ?? []
			}

			// Generate synthetic CREATE TABLE statement
			let columnDefinitions = columnNames.map { "[\($0)]" }.joined(separator: ", ")
			let createTableSQL = "CREATE TABLE [\(name)] (\(columnDefinitions));"

			print("\(createTableSQL)")
		}

		if !hasSchema {
			print("No tables found.")
		}
	} catch {
		print("Error displaying schema: \(error)")
	}
}

func executeCommandsFromFile(filePath: String, database: RBDB, mode: InputMode) -> Bool {
	do {
		let content = try String(contentsOfFile: filePath, encoding: .utf8)

		print("Executing commands from file: \(filePath) (mode: \(mode.displayName))")

		executeCommand(content, database: database, mode: mode)

		print("File execution completed.")
		return true  // Continue to interactive mode
	} catch {
		print("Error reading file '\(filePath)': \(error)")
		exit(1)
	}
}

func formatPage<I: IteratorProtocol<Row>>(_ iter: inout I) -> String? {
	var rows: [Row] = []
	let pageSize = max(getTerminalHeight() - 5, 1)
	rows.reserveCapacity(pageSize)

	for _ in 0..<pageSize {
		guard let row = iter.next() else { break }
		rows.append(row)
	}

	guard let firstRow = rows.first else { return nil }
	let columns = Array(firstRow.keys).sorted()
	var output = ""

	// Calculate column widths
	var columnWidths: [String: Int] = [:]
	for column in columns {
		columnWidths[column] = column.count
		for row in rows {
			let valueStr = stringValue(row[column] ?? nil)
			columnWidths[column] = max(
				columnWidths[column] ?? 0,
				valueStr.count
			)
		}
	}

	// Header
	let headerLine = columns.map { column in
		column.padding(
			toLength: columnWidths[column]!,
			withPad: " ",
			startingAt: 0
		)
	}.joined(separator: " | ")
	output += headerLine + "\n"

	// Separator
	let separatorLine = columns.map { column in
		String(repeating: "-", count: columnWidths[column]!)
	}.joined(separator: "-+-")
	output += separatorLine + "\n"

	// Rows
	for row in rows {
		let rowLine = columns.map { column in
			let valueStr = stringValue(row[column] ?? nil)
			return valueStr.padding(
				toLength: columnWidths[column]!,
				withPad: " ",
				startingAt: 0
			)
		}.joined(separator: " | ")
		output += rowLine + "\n"
	}

	return output
}

func printTable<C: Sequence<Row>>(_ cursor: C) {
	var iter = cursor.makeIterator()
	guard var page = formatPage(&iter) else {
		print("No results.")
		return
	}

	while true {
		print(page)
		guard let nextPage = formatPage(&iter) else { break }

		print(
			"-- More results available. Press enter or space for next page, anything else to stop --"
		)
		let input = getchar()
		if input != 10 && input != 13 && input != 32 {
			break
		}

		page = nextPage
	}
}

func getTerminalHeight() -> Int {
	var size = winsize()
	if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0 {
		return Int(size.ws_row)
	}
	return 24  // Default fallback
}

func stringValue(_ value: Any?) -> String {
	if let value = value {
		if value is NSNull {
			return "NULL"
		} else if let data = value as? Data {
			// Try to interpret as UUIDv7 first
			if let uuid = UUIDv7(data: data) {
				return uuid.description
			}
			return "<BLOB \(data.count) bytes>"
		} else {
			return String(describing: value)
		}
	} else {
		return "NULL"
	}
}

func setupRawMode() {
	var raw = termios()
	tcgetattr(STDIN_FILENO, &raw)
	raw.c_lflag &= ~(TerminalFlag(ECHO | ICANON))
	tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
}

func restoreTerminal() {
	var cooked = termios()
	tcgetattr(STDIN_FILENO, &cooked)
	cooked.c_lflag |= TerminalFlag(ECHO | ICANON)
	tcsetattr(STDIN_FILENO, TCSAFLUSH, &cooked)
}

func redrawLineWithCursor(line: String, cursorPos: Int, mode: InputMode) {
	// Clear the line and redraw with cursor positioning
	print("\r\u{001B}[K", terminator: "")
	print("\(mode.prompt)\(line)", terminator: "")

	// Move cursor to the correct position
	if cursorPos < line.count {
		let moveBack = line.count - cursorPos
		print("\u{001B}[\(moveBack)D", terminator: "")
	}

	fflush(stdout)
}

func readLineWithHistory(
	history: inout [(String, InputMode)], historyIndex: inout Int, mode: inout InputMode
)
	-> String?
{
	var line = ""
	var cursorPos = 0

	while true {
		let char = getchar()

		if char == 27 {  // ESC sequence
			let next1 = getchar()
			let next2 = getchar()

			if next1 == 91 {  // [ character
				switch next2 {
				case 65:  // Up arrow
					if historyIndex > 0 {
						historyIndex -= 1
						// Clear current line
						print("\r\u{001B}[K", terminator: "")
						(line, mode) = history[historyIndex]
						cursorPos = line.count
						print("\(mode.prompt)\(line)", terminator: "")
						fflush(stdout)
					}
				case 66:  // Down arrow
					if historyIndex < history.count - 1 {
						historyIndex += 1
						// Clear current line
						print("\r\u{001B}[K", terminator: "")
						(line, mode) = history[historyIndex]
						cursorPos = line.count
						print("\(mode.prompt)\(line)", terminator: "")
						fflush(stdout)
					} else if historyIndex == history.count - 1 {
						historyIndex = history.count
						// Clear current line
						print("\r\u{001B}[K", terminator: "")
						line = ""
						cursorPos = 0
						print(mode.prompt, terminator: "")
						fflush(stdout)
					}
				case 67:  // Right arrow
					if cursorPos < line.count {
						cursorPos += 1
						redrawLineWithCursor(line: line, cursorPos: cursorPos, mode: mode)
					}
				case 68:  // Left arrow
					if cursorPos > 0 {
						cursorPos -= 1
						redrawLineWithCursor(line: line, cursorPos: cursorPos, mode: mode)
					}
				case 51:  // Delete key (ESC[3~)
					let next3 = getchar()
					if next3 == 126 {  // ~ character
						if cursorPos < line.count {
							line.remove(
								at: line.index(
									line.startIndex,
									offsetBy: cursorPos
								)
							)
							redrawLineWithCursor(
								line: line,
								cursorPos: cursorPos,
								mode: mode
							)
						}
					}
				case 90:  // Shift+Tab (ESC[Z)
					// Switch between SQL and Datalog modes
					switch mode {
					case .sql:
						mode = .datalog(isQueryMode: false)
					case .datalog:
						mode = .sql
					}
					// Clear current line and redraw with new mode
					print("\r\u{001B}[K", terminator: "")
					print(mode.prompt, terminator: "")
					print("\(line)", terminator: "")
					// Move cursor back to correct position
					if cursorPos < line.count {
						let moveBack = line.count - cursorPos
						print("\u{001B}[\(moveBack)D", terminator: "")
					}
					fflush(stdout)
				default:
					break
				}
			}
		} else if char == 10 || char == 13 {  // Enter
			print()
			return line
		} else if char == 127 {  // Backspace
			// Exit query mode if line is empty in datalog mode
			if case .datalog(isQueryMode: true) = mode, line.isEmpty {
				mode = .datalog(isQueryMode: false)
			}

			if cursorPos > 0 {
				line.remove(
					at: line.index(line.startIndex, offsetBy: cursorPos - 1)
				)
				cursorPos -= 1
			}

			redrawLineWithCursor(line: line, cursorPos: cursorPos, mode: mode)
		} else if char >= 32 && char <= 126 {  // Printable characters
			let character = Character(UnicodeScalar(Int(char))!)

			// Special handling for '?' in datalog mode
			if case .datalog(let isQueryMode) = mode, !isQueryMode, character == "?",
				cursorPos == 0, line.isEmpty
			{
				mode = .datalog(isQueryMode: true)
				// Redraw the line with the new query mode prompt
				print("\r\u{001B}[K", terminator: "")
				print(mode.prompt, terminator: "")
				fflush(stdout)
			} else if case .datalog(let isQueryMode) = mode, isQueryMode, character == "-",
				cursorPos == 0, line.isEmpty
			{
				// Ignore "-" typed right after "?" (that switched us into query mode and gave an implicit "?-" prompt)
				// This prevents a superfluous "-" if you paste a query like "?- foo(X)" at a non-query-mode datalog prompt
			} else {
				line.insert(
					character,
					at: line.index(line.startIndex, offsetBy: cursorPos)
				)
				cursorPos += 1
				redrawLineWithCursor(line: line, cursorPos: cursorPos, mode: mode)
			}
		} else if char == 1 {  // Ctrl+A (beginning of line)
			cursorPos = 0
			redrawLineWithCursor(line: line, cursorPos: cursorPos, mode: mode)
		} else if char == 5 {  // Ctrl+E (end of line)
			cursorPos = line.count
			redrawLineWithCursor(line: line, cursorPos: cursorPos, mode: mode)
		} else if char == 4 {  // Ctrl+D (EOF)
			if line.isEmpty {
				print()
				return nil
			}
		}
	}
}

func main() {
	let args = CommandLine.arguments

	// Handle --help
	if args.contains("--help") {
		printUsage()
		exit(0)
	}

	// Parse arguments
	var dbPath: String = ":memory:"
	var isInMemory: Bool = true
	var sqlFile: String? = nil
	var defaultMode: InputMode = .sql

	var i = 1
	while i < args.count {
		let arg = args[i]

		if arg == "--file" || arg == "-f" {
			if i + 1 >= args.count {
				print("Error: --file requires a file path")
				printUsage()
				exit(1)
			}
			sqlFile = args[i + 1]
			i += 2
		} else if arg.hasPrefix("--file=") {
			sqlFile = String(arg.dropFirst(7))
			i += 1
		} else if arg == "--lang" || arg == "-l" {
			if i + 1 >= args.count {
				print("Error: --lang requires a language argument")
				printUsage()
				exit(1)
			}
			let langArg = args[i + 1]
			if let mode = parseLanguage(langArg) {
				defaultMode = mode
			} else {
				print("Error: Unknown language '\(langArg)'. Use 's'/'sql' or 'd'/'datalog'")
				printUsage()
				exit(1)
			}
			i += 2
		} else if arg.hasPrefix("--lang=") {
			let langArg = String(arg.dropFirst(7))
			if let mode = parseLanguage(langArg) {
				defaultMode = mode
			} else {
				print("Error: Unknown language '\(langArg)'. Use 's'/'sql' or 'd'/'datalog'")
				printUsage()
				exit(1)
			}
			i += 1
		} else if !arg.hasPrefix("-") {
			// This is the database path
			dbPath = arg
			isInMemory = false
			i += 1
		} else {
			print("Error: Unknown option '\(arg)'")
			printUsage()
			exit(1)
		}
	}

	// Initialize database
	let database: RBDB
	do {
		database = try RBDB(path: dbPath)
	} catch {
		print("Error opening database: \(error)")
		exit(1)
	}

	// Check if we're connected to a terminal
	let isInteractive = isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0

	if isInteractive {
		print(productName)
		if isInMemory {
			print("Database: In-memory database")
		} else {
			print("Database: \(dbPath)")
		}
		print("Type '.exit' to quit, '.schema' to show database schema")
		print()
	}

	// Execute SQL file if provided
	if let sqlFile = sqlFile {
		let shouldContinue = executeCommandsFromFile(
			filePath: sqlFile,
			database: database,
			mode: defaultMode
		)
		if !shouldContinue {
			if isInteractive {
				print("Goodbye!")
			}
			exit(0)
		}
		if isInteractive {
			print()
		}
	}

	if isInteractive {
		runInteractiveMode(database: database, defaultMode: defaultMode)
	} else {
		runNonInteractiveMode(database: database, defaultMode: defaultMode)
	}
}

func runInteractiveMode(database: RBDB, defaultMode: InputMode) {
	// Command history
	var history: [(String, InputMode)] = []
	var historyIndex = 0
	var mode: InputMode = defaultMode

	// Setup raw terminal mode for arrow key handling
	setupRawMode()

	// Setup signal handler to restore terminal on exit
	signal(SIGINT) { _ in
		restoreTerminal()
		exit(0)
	}

	// Main loop
	while true {
		print(mode.prompt, terminator: "")
		fflush(stdout)

		guard
			let input = readLineWithHistory(
				history: &history,
				historyIndex: &historyIndex,
				mode: &mode
			)
		else {
			break
		}

		let command = input.trimmingCharacters(in: .whitespacesAndNewlines)

		if command.isEmpty {
			continue
		}

		if command == ".exit" {
			break
		}

		if command == ".schema" {
			displaySchema(database: database)
			print()
			continue
		}

		// Add to history if it's not empty and not the same as the last command
		if !command.isEmpty && (history.isEmpty || history.last?.0 != command) {
			history.append((command, mode))
		}
		historyIndex = history.count

		// Execute command based on mode
		executeCommand(command, database: database, mode: mode)
		print()
	}

	// Restore terminal mode
	restoreTerminal()

	print("Goodbye!")
}

func runNonInteractiveMode(database: RBDB, defaultMode: InputMode) {
	// Read from stdin line by line
	while let line = readLine() {
		let command = line.trimmingCharacters(in: .whitespacesAndNewlines)

		if command.isEmpty {
			continue
		}

		if command == ".exit" {
			break
		}

		if command == ".schema" {
			displaySchema(database: database)
			continue
		}

		executeCommand(command, database: database, mode: defaultMode)
	}
}

func executeCommand(_ command: String, database: RBDB, mode: InputMode) {
	do {
		switch mode {
		case .sql:
			let results = try database.query(sql: SQL(command))
			printTable(results)

		case .datalog(let isQueryMode):
			let parser = DatalogParser()
			let formula = try parser.parse(command)
			if isQueryMode {
				let results = try database.query(formula: formula)
				printTable(results)
			} else {
				try database.assert(formula: formula)
				print("Asserted.")
			}
		}
	} catch {
		print("Error: \(error)")
	}
}

main()
