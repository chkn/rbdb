import Foundation
import Testing
@testable import RBDB

@Test("SQL string interpolation creates parameterized queries")
func sqlStringInterpolation() throws {
	// Test basic interpolation
	let name = "John"
	let age = 25
	let sql: SQL = "SELECT * FROM users WHERE name = \(name) AND age = \(age)"

	#expect(sql.queryText == "SELECT * FROM users WHERE name = ? AND age = ?")
	#expect(sql.arguments.count == 2)
	#expect(sql.arguments[0] as? String == "John")
	#expect(sql.arguments[1] as? Int == 25)
}

@Test("SQL string interpolation with mixed types")
func sqlInterpolationMixedTypes() throws {
	let id = 42
	let isActive = true
	let rating: Double = 4.5
	let description: String? = nil

	let sql: SQL =
		"UPDATE products SET active = \(isActive), rating = \(rating), description = \(description) WHERE id = \(id)"

	#expect(
		sql.queryText == "UPDATE products SET active = ?, rating = ?, description = ? WHERE id = ?")
	#expect(sql.arguments.count == 4)
	#expect(sql.arguments[0] as? Bool == true)
	#expect(sql.arguments[1] as? Double == 4.5)
	#expect(sql.arguments[2] == nil)
	#expect(sql.arguments[3] as? Int == 42)
}

@Test("SQL string literal creates query without parameters")
func sqlStringLiteral() throws {
	let sql: SQL = "SELECT COUNT(*) FROM users"

	#expect(sql.queryText == "SELECT COUNT(*) FROM users")
	#expect(sql.arguments.isEmpty)
}

@Test("Empty SQL string interpolation")
func emptySQLInterpolation() throws {
	let sql: SQL = ""

	#expect(sql.queryText == "")
	#expect(sql.arguments.isEmpty)
}

@Test("SQL unsafeRaw interpolation bypasses parameterization")
func sqlUnsafeRawInterpolation() throws {
	let tableName = "users"
	let orIgnore = "OR IGNORE "
	let userId = 42

	let sql: SQL =
		"INSERT \(SQL(orIgnore))INTO \(SQL(tableName)) (id) VALUES (\(userId))"

	#expect(sql.queryText == "INSERT OR IGNORE INTO users (id) VALUES (?)")
	#expect(sql.arguments.count == 1)
	#expect(sql.arguments[0] as? Int == 42)
}

@Test("SQL struct interpolation merges query text and arguments")
func sqlStructInterpolation() throws {
	let innerSQL: SQL = "SELECT id FROM users WHERE name = \("John")"
	let outerSQL: SQL = "INSERT INTO results \(innerSQL)"

	#expect(outerSQL.queryText == "INSERT INTO results SELECT id FROM users WHERE name = ?")
	#expect(outerSQL.arguments.count == 1)
	#expect(outerSQL.arguments[0] as? String == "John")
}
