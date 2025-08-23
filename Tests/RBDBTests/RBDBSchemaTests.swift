import Foundation
import Testing

@testable import RBDB

struct RBDBSchemaTests {

	@Test("Tables are created on RBDB initialization")
	func tablesCreatedOnInit() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Query for existing tables
		let results = try rbdb.query(
			sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
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
		try rbdb.query(sql: "INSERT INTO _entity (internal_entity_id) VALUES (1)")

		// Query the inserted row
		let results = Array(
			try rbdb.query(
				sql: "SELECT entity_id FROM _entity WHERE internal_entity_id = 1"
			))

		#expect(results.count == 1, "Should have inserted one row")
		#expect(results[0]["entity_id"] != nil, "entity_id should not be null")

		// Verify it's a valid BLOB (UUIDv7 is 16 bytes)
		if let entityIdData = results[0]["entity_id"] as? Data {
			#expect(entityIdData.count == 16, "UUIDv7 should be 16 bytes")
		} else {
			#expect(Bool(false), "entity_id should be Data/BLOB type")
		}
	}

	@Test("Generated columns arg1_constant and arg2_constant work correctly")
	func generatedColumnsWork() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Create predicate tables first
		try rbdb.query(sql: "CREATE TABLE parent(parent, child)")
		try rbdb.query(sql: "CREATE TABLE likes(who, what)")

		// Insert test rules with constant arguments
		try rbdb.assert(
			formula: .predicate(
				Predicate(name: "parent", arguments: [.string("alice"), .string("bob")])))
		try rbdb.assert(
			formula: .predicate(
				Predicate(name: "likes", arguments: [.string("charlie"), .number(42)])))

		// Query the generated columns
		let results = Array(
			try rbdb.query(
				sql: """
						SELECT arg1_constant, arg2_constant, output_type 
						FROM _rule 
						ORDER BY output_type
					"""))

		#expect(results.count == 2, "Should have two rules")

		// Check likes rule
		let likesRule = results.first { ($0["output_type"] as? String) == "@likes" }!
		#expect(likesRule["arg1_constant"] as? String == "charlie")
		#expect(likesRule["arg2_constant"] as? Int64 == 42)

		// Check parent rule
		let parentRule = results.first { ($0["output_type"] as? String) == "@parent" }!
		#expect(parentRule["arg1_constant"] as? String == "alice")
		#expect(parentRule["arg2_constant"] as? String == "bob")
	}

	@Test("Queries using generated columns should use indexes")
	func queriesUseIndexes() async throws {
		let rbdb = try RBDB(path: ":memory:")

		try rbdb.query(sql: "CREATE TABLE parent(parent, child)")
		try rbdb.query(sql: "CREATE TABLE likes(who, what)")

		// Insert test data
		try rbdb.assert(
			formula: .predicate(
				Predicate(name: "parent", arguments: [.string("alice"), .string("bob")])))
		try rbdb.assert(
			formula: .predicate(
				Predicate(name: "parent", arguments: [.string("charlie"), .string("dave")])))
		try rbdb.assert(
			formula: .predicate(
				Predicate(name: "likes", arguments: [.string("alice"), .number(42)])))

		// Query using arg1_constant and check query plan
		let queryPlan1 = try rbdb.query(
			sql: """
					EXPLAIN QUERY PLAN 
					SELECT * FROM parent 
					WHERE parent = 'alice'
				""")

		let planText1 = queryPlan1.compactMap { $0["detail"] as? String }.joined(separator: " ")

		// NOTE: It should be "USING COVERING INDEX", but there is a bug..
		// https://sqlite.org/forum/info/d1833ef5e40ab97d42b7f34ac488b1ca8c1d6ea46c3901a0121951a6588a6ce3
		#expect(planText1.contains("USING INDEX"), "Query should use an index")
		#expect(planText1.contains("arg1_constant"), "Query plan should mention arg1_constant")

		// Query using arg2_constant and check query plan
		let queryPlan2 = try rbdb.query(
			sql: """
					EXPLAIN QUERY PLAN 
					SELECT * FROM parent 
					WHERE child = 'bob'
				""")

		let planText2 = queryPlan2.compactMap { $0["detail"] as? String }.joined(separator: " ")

		// NOTE: It should be "USING COVERING INDEX", but there is a bug..
		// https://sqlite.org/forum/info/d1833ef5e40ab97d42b7f34ac488b1ca8c1d6ea46c3901a0121951a6588a6ce3
		#expect(planText2.contains("USING INDEX"), "Query should use an index")
		#expect(planText2.contains("arg2_constant"), "Query plan should mention arg2_constant")
	}

	@Test("assert(formula:) throws queryError for non-existent predicate")
	func assertThrowsForNonExistentPredicate() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Verify the error message is correct
		do {
			try rbdb.assert(
				formula: .predicate(Predicate(name: "foo", arguments: [.string("bar")])))
			#expect(Bool(false), "Should have thrown an error")
		} catch let error as SQLiteError {
			if case .queryError(let message, _) = error {
				#expect(
					message == "no such table: foo", "Error message should match expected format")
			} else {
				#expect(Bool(false), "Should be a queryError")
			}
		}
	}

	@Test("assert(formula:) works for existing predicates")
	func assertWorksForExistingPredicates() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Create a predicate table first
		try rbdb.query(sql: "CREATE TABLE parent(parent, child)")

		// Now assert should work
		try rbdb.assert(
			formula: .predicate(
				Predicate(name: "parent", arguments: [.string("alice"), .string("bob")])))

		// Verify the rule was inserted
		let results = Array(try rbdb.query(sql: "SELECT COUNT(*) as count FROM _rule"))
		#expect(results[0]["count"] as? Int64 == 1, "Should have one rule")
	}

	@Test("assert(formula:) validates predicates in horn clauses")
	func assertValidatesHornClausePredicates() async throws {
		let rbdb = try RBDB(path: ":memory:")

		// Try to assert a horn clause with non-existent predicate
		let variable = Var()
		let hornClause = Formula.hornClause(
			positive: Predicate(name: "nonexistent", arguments: [.variable(variable)]),
			negative: []
		)

		// Verify the error message
		do {
			try rbdb.assert(formula: hornClause)
			#expect(Bool(false), "Should have thrown an error")
		} catch let error as SQLiteError {
			if case .queryError(let message, _) = error {
				#expect(
					message == "no such table: nonexistent",
					"Error message should match expected format")
			} else {
				#expect(Bool(false), "Should be a queryError")
			}
		}
	}
}
