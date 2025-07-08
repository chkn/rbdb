import Foundation
import RBDB

func printUsage() {
    print("Usage: sql <database_path>")
    print("  Interactive SQLite database console")
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

func main() {
    let args = CommandLine.arguments

    guard args.count == 2 else {
        printUsage()
        exit(1)
    }

    let dbPath = args[1]

    // Initialize database
    let database: SQLiteDatabase
    do {
        database = try SQLiteDatabase(path: dbPath)
    } catch {
        print("Error opening database: \(error)")
        exit(1)
    }

    print("SQLite Interactive Console")
    print("Database: \(dbPath)")
    print("Type '.exit' to quit")
    print()

    // Main loop
    while true {
        print("sql> ", terminator: "")

        guard let input = readLine() else {
            break
        }

        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)

        if command.isEmpty {
            continue
        }

        if command == ".exit" {
            break
        }

        // Execute SQL command
        do {
			let results = try database.query(command)
			print(formatTable(results))
        } catch {
            print("Error: \(error)")
        }

        print()
    }

    print("Goodbye!")
}

main()
