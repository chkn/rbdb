import Foundation
import Testing
@testable import RBDB

@Suite("Parameterized Query Tests")
struct ParameterizedQueryTests {

    @Test("String parameter binding")
    func stringParameterBinding() async throws {
        let db = try SQLiteDatabase(path: ":memory:")

        // Create a test table
        try db.query("CREATE TABLE test (id INTEGER, name TEXT)")

        // Insert with string parameter
        try db.query("INSERT INTO test (id, name) VALUES (?, ?)", parameters: [1, "Alice"])

        // Query with string parameter
        let results = try db.query("SELECT * FROM test WHERE name = ?", parameters: ["Alice"])

        #expect(results.count == 1, "Should return one row")
        #expect(results[0]["id"] as? Int64 == 1, "ID should be 1")
        #expect(results[0]["name"] as? String == "Alice", "Name should be Alice")
    }

    @Test("Integer parameter binding")
    func integerParameterBinding() async throws {
        let db = try SQLiteDatabase(path: ":memory:")

        try db.query("CREATE TABLE test (id INTEGER, value INTEGER)")

        // Test both Int and Int64
        try db.query("INSERT INTO test (id, value) VALUES (?, ?)", parameters: [1, 42])
        try db.query("INSERT INTO test (id, value) VALUES (?, ?)", parameters: [Int64(2), Int64(100)])

        let results = try db.query("SELECT * FROM test WHERE value > ?", parameters: [50])

        #expect(results.count == 1, "Should return one row")
        #expect(results[0]["value"] as? Int64 == 100, "Value should be 100")
    }

    @Test("Double parameter binding")
    func doubleParameterBinding() async throws {
        let db = try SQLiteDatabase(path: ":memory:")

        try db.query("CREATE TABLE test (id INTEGER, price REAL)")

        try db.query("INSERT INTO test (id, price) VALUES (?, ?)", parameters: [1, 19.99])
        try db.query("INSERT INTO test (id, price) VALUES (?, ?)", parameters: [2, 29.50])

        let results = try db.query("SELECT * FROM test WHERE price < ?", parameters: [25.0])

        #expect(results.count == 1, "Should return one row")
        #expect(results[0]["price"] as? Double == 19.99, "Price should be 19.99")
    }

    @Test("Data parameter binding")
    func dataParameterBinding() async throws {
        let db = try SQLiteDatabase(path: ":memory:")

        try db.query("CREATE TABLE test (id INTEGER, data BLOB)")

        let testData = Data([0x01, 0x02, 0x03, 0x04])
        try db.query("INSERT INTO test (id, data) VALUES (?, ?)", parameters: [1, testData])

        let results = try db.query("SELECT * FROM test WHERE id = ?", parameters: [1])

        #expect(results.count == 1, "Should return one row")
        if let retrievedData = results[0]["data"] as? Data {
            #expect(retrievedData == testData, "Retrieved data should match inserted data")
        } else {
            #expect(Bool(false), "Data should be of Data type")
        }
    }

    @Test("UUIDv7 parameter binding")
    func uuidv7ParameterBinding() async throws {
        let db = try SQLiteDatabase(path: ":memory:")

        let testUUID = UUIDv7()

        try db.query("CREATE TABLE entity (internal_entity_id, entity_id)")

        // Insert with UUIDv7 parameter
        try db.query("INSERT INTO entity (internal_entity_id, entity_id) VALUES (?, ?)",
                      parameters: [1, testUUID])

        // Query with UUIDv7 parameter
        let results = try db.query("SELECT * FROM entity WHERE entity_id = ?",
                                    parameters: [testUUID])

        #expect(results.count == 1, "Should return one row")
        #expect(results[0]["internal_entity_id"] as? Int64 == 1, "ID should be 1")

        if let retrievedData = results[0]["entity_id"] as? Data {
            let retrievedUUID = UUIDv7(data: retrievedData)
            #expect(retrievedUUID == testUUID, "Retrieved UUID should match inserted UUID")
        } else {
            #expect(Bool(false), "entity_id should be of Data type")
        }
    }

    @Test("NSNull parameter binding")
    func nsNullParameterBinding() async throws {
        let db = try SQLiteDatabase(path: ":memory:")

        try db.query("CREATE TABLE test (id INTEGER, optional_text TEXT)")

        try db.query("INSERT INTO test (id, optional_text) VALUES (?, ?)", 
                    parameters: [1, NSNull()])

        let results = try db.query("SELECT * FROM test WHERE optional_text IS NULL")

        #expect(results.count == 1, "Should return one row")
        #expect(results[0]["optional_text"] == nil, "optional_text should be null")
    }

	@Test("nil parameter binding")
	func nilParameterBinding() async throws {
		let db = try SQLiteDatabase(path: ":memory:")

		try db.query("CREATE TABLE test (id INTEGER, optional_text TEXT)")

		try db.query("INSERT INTO test (id, optional_text) VALUES (?, ?)",
					parameters: [1, nil])

		let results = try db.query("SELECT * FROM test WHERE optional_text IS NULL")

		#expect(results.count == 1, "Should return one row")
		#expect(results[0]["optional_text"] == nil, "optional_text should be null")
	}

    @Test("Mixed parameter types")
    func mixedParameterTypes() async throws {
        let db = try SQLiteDatabase(path: ":memory:")

        // Create a more complex table
        try db.query("""
            CREATE TABLE complex_test (
                id INTEGER,
                name TEXT,
                price REAL,
                data BLOB,
                uuid_field BLOB,
                optional_field TEXT
            )
        """)

        let testUUID = UUIDv7()
        let testData = Data([0xFF, 0xEE, 0xDD])

        try db.query("""
            INSERT INTO complex_test (id, name, price, data, uuid_field, optional_field) 
            VALUES (?, ?, ?, ?, ?, ?)
        """, parameters: [42, "Test Item", 99.99, testData, testUUID, NSNull()])

        let results = try db.query("""
            SELECT * FROM complex_test WHERE id = ? AND name = ? AND price > ?
        """, parameters: [42, "Test Item", 50.0])

        #expect(results.count == 1, "Should return one row")
        #expect(results[0]["id"] as? Int64 == 42, "ID should be 42")
        #expect(results[0]["name"] as? String == "Test Item", "Name should match")
        #expect(results[0]["price"] as? Double == 99.99, "Price should match")
        #expect(results[0]["optional_field"] == nil, "Optional field should be null")

        if let retrievedData = results[0]["data"] as? Data {
            #expect(retrievedData == testData, "Data should match")
        }

        if let retrievedUUIDData = results[0]["uuid_field"] as? Data {
            let retrievedUUID = UUIDv7(data: retrievedUUIDData)
            #expect(retrievedUUID == testUUID, "UUID should match")
        }
    }

    @Test("Unsupported parameter type throws error")
    func unsupportedParameterType() async throws {
        let db = try SQLiteDatabase(path: ":memory:")

        try db.query("CREATE TABLE test (id INTEGER)")

        // Try to bind an unsupported type (e.g., a custom struct)
        struct UnsupportedType {}
        let unsupported = UnsupportedType()

        #expect(throws: SQLiteError.self) {
            try db.query("INSERT INTO test (id) VALUES (?)", parameters: [unsupported])
        }
    }

    @Test("Parameter count mismatch")
    func parameterCountMismatch() async throws {
        let db = try SQLiteDatabase(path: ":memory:")

        try db.query("CREATE TABLE test (id INTEGER, name TEXT)")

        // Provide fewer parameters than placeholders
        #expect(throws: SQLiteError.self) {
            try db.query("INSERT INTO test (id, name) VALUES (?, ?)", parameters: [1])
        }
    }
}
