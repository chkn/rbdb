import Foundation
import RBDB
import Darwin

func printUsage() {
    print("Usage: sql [options] [database_path]")
    print("  Interactive SQLite database console")
    print("")
    print("Arguments:")
    print("  database_path        Path to SQLite database file (optional)")
    print("                       If not provided, uses in-memory database")
    print("")
    print("Options:")
    print("  --help               Show this help message")
    print("  -f | --file <path>   Execute the SQL commands from the given file")
    print("")
    print("Commands:")
    print("  .exit                Exit the console")
    print("  .schema              Show database schema")
}

func displaySchema(database: SQLiteDatabase) {
    do {
        let results = try database.query("SELECT name, type, sql FROM sqlite_master WHERE type IN ('table', 'view', 'index', 'trigger') ORDER BY type, name")

        if results.isEmpty {
            print("No schema objects found.")
            return
        }

        var currentType = ""
        for row in results {
            let type = row["type"] as? String ?? ""
            let name = row["name"] as? String ?? ""
            let sql = row["sql"] as? String ?? ""

            if type != currentType {
                currentType = type
                print("\n-- \(type.uppercased())S")
                print(String(repeating: "-", count: 50))
            }

            print("\(name):")
            if !sql.isEmpty {
                print("  \(sql)")
            }
            print()
        }
    } catch {
        print("Error displaying schema: \(error)")
    }
}

func executeCommandsFromFile(filePath: String, database: SQLiteDatabase) -> Bool {
    do {
        let content = try String(contentsOfFile: filePath)

        // Split by semicolon to handle multi-line SQL statements
        let statements = content.components(separatedBy: ";")

        print("Executing commands from file: \(filePath)")

        for statement in statements {
            // Remove comments and normalize whitespace
            let lines = statement.components(separatedBy: .newlines)
                .map { line in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Remove comments but keep the rest of the line
                    if let commentIndex = trimmed.firstIndex(of: Character("-")), trimmed[trimmed.index(after: commentIndex)] == "-" {
                        let beforeComment = String(trimmed[..<commentIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if beforeComment.isEmpty {
                            return ""
                        }
                        return beforeComment
                    }
                    return trimmed
                }
                .filter { !$0.isEmpty }

            let cleanStatement = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

            if cleanStatement.isEmpty {
                continue
            }

            if cleanStatement == ".schema" {
                displaySchema(database: database)
                continue
            }

            if cleanStatement == ".exit" {
                return false // Signal to exit
            }

            print("sql> \(cleanStatement)")
            do {
                let results = try database.query(cleanStatement)
                if !results.isEmpty {
                    print(formatTable(results))
                } else {
                    print("Command executed successfully.")
                }
            } catch {
                print("Error executing command '\(cleanStatement)': \(error)")
                return false // Stop execution on error
            }
            print()
        }

        print("File execution completed.")
        return true // Continue to interactive mode
    } catch {
        print("Error reading file '\(filePath)': \(error)")
        exit(1)
    }
}

func formatTable(_ rows: [[String: Any]]) -> String {
    guard !rows.isEmpty else { return "No results." }

    let columns = Array(rows[0].keys).sorted()
    var output = ""

    // Calculate column widths
    var columnWidths: [String: Int] = [:]
    for column in columns {
        columnWidths[column] = column.count
        for row in rows {
            let valueStr = stringValue(row[column])
            columnWidths[column] = max(columnWidths[column] ?? 0, valueStr.count)
        }
    }

    // Header
    let headerLine = columns.map { column in
        column.padding(toLength: columnWidths[column]!, withPad: " ", startingAt: 0)
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
            let valueStr = stringValue(row[column])
            return valueStr.padding(toLength: columnWidths[column]!, withPad: " ", startingAt: 0)
        }.joined(separator: " | ")
        output += rowLine + "\n"
    }

    return output
}

func stringValue(_ value: Any?) -> String {
    if let value = value {
        if value is NSNull {
            return "NULL"
        } else if let data = value as? Data {
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
    raw.c_lflag &= ~(UInt(ECHO | ICANON))
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
}

func restoreTerminal() {
    var cooked = termios()
    tcgetattr(STDIN_FILENO, &cooked)
    cooked.c_lflag |= UInt(ECHO | ICANON)
    tcsetattr(STDIN_FILENO, TCSAFLUSH, &cooked)
}

func redrawLineWithCursor(line: String, cursorPos: Int) {
    // Clear the line and redraw with cursor positioning
    print("\r\u{001B}[K", terminator: "")
    print("sql> \(line)", terminator: "")

    // Move cursor to the correct position
    if cursorPos < line.count {
        let moveBack = line.count - cursorPos
        print("\u{001B}[\(moveBack)D", terminator: "")
    }

    fflush(stdout)
}

func readLineWithHistory(history: inout [String], historyIndex: inout Int) -> String? {
    var line = ""
    var cursorPos = 0

    while true {
        let char = getchar()

        if char == 27 { // ESC sequence
            let next1 = getchar()
            let next2 = getchar()

            if next1 == 91 { // [ character
                switch next2 {
                case 65: // Up arrow
                    if historyIndex > 0 {
                        historyIndex -= 1
                        // Clear current line
                        print("\r\u{001B}[K", terminator: "")
                        line = history[historyIndex]
                        cursorPos = line.count
                        print("sql> \(line)", terminator: "")
                        fflush(stdout)
                    }
                case 66: // Down arrow
                    if historyIndex < history.count - 1 {
                        historyIndex += 1
                        // Clear current line
                        print("\r\u{001B}[K", terminator: "")
                        line = history[historyIndex]
                        cursorPos = line.count
                        print("sql> \(line)", terminator: "")
                        fflush(stdout)
                    } else if historyIndex == history.count - 1 {
                        historyIndex = history.count
                        // Clear current line
                        print("\r\u{001B}[K", terminator: "")
                        line = ""
                        cursorPos = 0
                        print("sql> ", terminator: "")
                        fflush(stdout)
                    }
                case 67: // Right arrow
                    if cursorPos < line.count {
                        cursorPos += 1
                        redrawLineWithCursor(line: line, cursorPos: cursorPos)
                    }
                case 68: // Left arrow
                    if cursorPos > 0 {
                        cursorPos -= 1
                        redrawLineWithCursor(line: line, cursorPos: cursorPos)
                    }
                case 51: // Delete key (ESC[3~)
                    let next3 = getchar()
                    if next3 == 126 { // ~ character
                        if cursorPos < line.count {
                            line.remove(at: line.index(line.startIndex, offsetBy: cursorPos))
                            redrawLineWithCursor(line: line, cursorPos: cursorPos)
                        }
                    }
                default:
                    break
                }
            }
        } else if char == 10 || char == 13 { // Enter
            print()
            return line
        } else if char == 127 { // Backspace
            if cursorPos > 0 {
                line.remove(at: line.index(line.startIndex, offsetBy: cursorPos - 1))
                cursorPos -= 1
                redrawLineWithCursor(line: line, cursorPos: cursorPos)
            }
        } else if char >= 32 && char <= 126 { // Printable characters
            let character = Character(UnicodeScalar(Int(char))!)
            line.insert(character, at: line.index(line.startIndex, offsetBy: cursorPos))
            cursorPos += 1
            redrawLineWithCursor(line: line, cursorPos: cursorPos)
        } else if char == 1 { // Ctrl+A (beginning of line)
            cursorPos = 0
            redrawLineWithCursor(line: line, cursorPos: cursorPos)
        } else if char == 5 { // Ctrl+E (end of line)
            cursorPos = line.count
            redrawLineWithCursor(line: line, cursorPos: cursorPos)
        } else if char == 4 { // Ctrl+D (EOF)
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
    let database: SQLiteDatabase
    do {
        database = try SQLiteDatabase(path: dbPath)
    } catch {
        print("Error opening database: \(error)")
        exit(1)
    }

    print("SQLite Interactive Console")
    if isInMemory {
        print("Database: In-memory database")
    } else {
        print("Database: \(dbPath)")
    }
    print("Type '.exit' to quit, '.schema' to show database schema")
    print()

    // Execute SQL file if provided
    if let sqlFile = sqlFile {
        let shouldContinue = executeCommandsFromFile(filePath: sqlFile, database: database)
        if !shouldContinue {
            print("Goodbye!")
            exit(0)
        }
        print()
    }

    // Command history
    var history: [String] = []
    var historyIndex = 0

    // Setup raw terminal mode for arrow key handling
    setupRawMode()

    // Setup signal handler to restore terminal on exit
    signal(SIGINT) { _ in
        restoreTerminal()
        exit(0)
    }

    // Main loop
    while true {
        print("sql> ", terminator: "")
        fflush(stdout)

        guard let input = readLineWithHistory(history: &history, historyIndex: &historyIndex) else {
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
        if !command.isEmpty && (history.isEmpty || history.last != command) {
            history.append(command)
        }
        historyIndex = history.count

        // Execute SQL command
        do {
			let results = try database.query(command)
			print(formatTable(results))
        } catch {
            print("Error: \(error)")
        }

        print()
    }

    // Restore terminal mode
    restoreTerminal()

    print("Goodbye!")
}

main()
