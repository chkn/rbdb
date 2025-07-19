import Foundation
import Testing

@testable import RBDB

@Suite("RBDB Schema Initialization")
struct RBDBSchemaTests {

	@Test("Tables are created on RBDB initialization")
	func tablesCreatedOnInit() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Query for existing tables
		let results = try rbdb.query(
			"SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
		)

		let tableNames = results.compactMap { $0["name"] as? String }

		#expect(
			tableNames.contains("_entity"),
			"_entity table should be created"
		)
		#expect(
			tableNames.contains("_predicate"),
			"_predicate table should be created"
		)
		#expect(tableNames.contains("_rule"), "_rule table should be created")
	}

	@Test("UUIDv7 function works in entity table")
	func uuidv7FunctionWorks() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Insert a row into entity table (should use default uuidv7())
		try rbdb.query("INSERT INTO _entity (internal_entity_id) VALUES (1)")

		// Query the inserted row
		let results = try rbdb.query(
			"SELECT entity_id FROM _entity WHERE internal_entity_id = 1"
		)

		#expect(results.count == 1, "Should have inserted one row")
		#expect(results[0]["entity_id"] != nil, "entity_id should not be null")

		// Verify it's a valid BLOB (UUIDv7 is 16 bytes)
		if let entityIdData = results[0]["entity_id"] as? Data {
			#expect(entityIdData.count == 16, "UUIDv7 should be 16 bytes")
		} else {
			#expect(Bool(false), "entity_id should be Data/BLOB type")
		}
	}
}
