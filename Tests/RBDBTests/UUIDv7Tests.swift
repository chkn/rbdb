import Testing
@testable import RBDB

@Suite("UUIDv7 string conversion")
struct UUIDv7ConversionTests {
    @Test("Round-trip conversion: UUIDv7 -> String -> UUIDv7")
    func roundTrip() async throws {
        let uuid = UUIDv7()
        let str = uuid.description
        let reconstructed = UUIDv7(str)
        #expect(reconstructed != nil, "Should reconstruct from its own string description")
        #expect(reconstructed! == uuid, "Parsed UUID must match original bytes")
    }

    @Test("Parse with and without hyphens")
    func parseWithHyphens() async throws {
        let uuid = UUIDv7()
        let hyphenated = uuid.description
        let nonHyphen = hyphenated.replacingOccurrences(of: "-", with: "")
        let uuid1 = UUIDv7(hyphenated)
        let uuid2 = UUIDv7(nonHyphen)
        #expect(uuid1 != nil && uuid2 != nil, "Should parse both hyphenated and non-hyphenated strings")
        #expect(uuid1! == uuid2! && uuid1! == uuid, "Data should match original")
    }

    @Test("Fail on invalid strings")
    func failOnInvalid() async throws {
        #expect(UUIDv7("") == nil)
        #expect(UUIDv7("12345") == nil)
        #expect(UUIDv7("invaliduuidstringwithmorethanfivewords") == nil)
        #expect(UUIDv7("zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz") == nil)
        #expect(UUIDv7("000000000000000000000000000000000000") == nil)
    }
}
