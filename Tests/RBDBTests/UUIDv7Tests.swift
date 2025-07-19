import Foundation
import Testing

@testable import RBDB

@Suite("UUIDv7 string conversion")
struct UUIDv7ConversionTests {
	@Test("Round-trip conversion: UUIDv7 -> String -> UUIDv7")
	func roundTrip() async throws {
		let uuid = UUIDv7()
		let str = uuid.description
		let reconstructed = UUIDv7(str)
		#expect(
			reconstructed != nil,
			"Should reconstruct from its own string description"
		)
		#expect(reconstructed! == uuid, "Parsed UUID must match original bytes")
	}

	@Test("Parse with and without hyphens")
	func parseWithHyphens() async throws {
		let uuid = UUIDv7()
		let hyphenated = uuid.description
		let nonHyphen = hyphenated.replacingOccurrences(of: "-", with: "")
		let uuid1 = UUIDv7(hyphenated)
		let uuid2 = UUIDv7(nonHyphen)
		#expect(
			uuid1 != nil && uuid2 != nil,
			"Should parse both hyphenated and non-hyphenated strings"
		)
		#expect(
			uuid1! == uuid2! && uuid1! == uuid,
			"Data should match original"
		)
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

@Suite("UUIDv7 format validation")
struct UUIDv7ValidationTests {
	@Test("UUIDv7 has correct format")
	func testUUIDv7Format() {
		let uuid = UUIDv7()

		// Convert to data to check the bits
		let data = uuid.withUnsafeBytes { Data($0) }

		// Check version (bits 12-15 of time_hi_and_version, byte 6)
		let versionNibble = (data[6] & 0xF0) >> 4
		#expect(versionNibble == 7, "Version should be 7")

		// Check variant (bits 14-15 of clock_seq_hi_and_reserved, byte 8)
		let variantBits = (data[8] & 0xC0) >> 6
		#expect(variantBits == 2, "Variant should be 10 (binary) = 2 (decimal)")
	}

	@Test("UUIDv7 validates version and variant bits on init")
	func testUUIDv7Validation() {
		// Create valid UUIDv7 data
		var validData = Data(count: 16)
		validData[6] = 0x70  // Version 7
		validData[8] = 0x80  // Variant 10

		let validUUID = UUIDv7(data: validData)
		#expect(validUUID != nil, "Should accept valid UUIDv7 data")

		// Test invalid version
		var invalidVersionData = validData
		invalidVersionData[6] = 0x40  // Version 4 instead of 7
		let invalidVersionUUID = UUIDv7(data: invalidVersionData)
		#expect(invalidVersionUUID == nil, "Should reject invalid version")

		// Test invalid variant
		var invalidVariantData = validData
		invalidVariantData[8] = 0x00  // Variant 00 instead of 10
		let invalidVariantUUID = UUIDv7(data: invalidVariantData)
		#expect(invalidVariantUUID == nil, "Should reject invalid variant")

		// Test wrong size
		let wrongSizeData = Data(count: 15)
		let wrongSizeUUID = UUIDv7(data: wrongSizeData)
		#expect(wrongSizeUUID == nil, "Should reject wrong size data")
	}
}
