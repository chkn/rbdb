import Foundation
import SQLite3

struct UUIDv7: Equatable {
	public let data: (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8)

	public init() {
		// Get current timestamp in milliseconds
		let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)

		// Generate random bytes for the rest of the UUID
		var randomBytes = Data(count: 10)
		let result = randomBytes.withUnsafeMutableBytes { bytes in
			SecRandomCopyBytes(kSecRandomDefault, 10, bytes.bindMemory(to: UInt8.self).baseAddress!)
		}

		if result != errSecSuccess {
			// Fallback to arc4random if SecRandom fails
			randomBytes = Data((0..<10).map { _ in UInt8.random(in: 0...255) })
		}

		// Build UUID v7 according to RFC 4122

		// First 48 bits: timestamp (6 bytes)
		data.0 = UInt8((timestamp >> 40) & 0xFF)
		data.1 = UInt8((timestamp >> 32) & 0xFF)
		data.2 = UInt8((timestamp >> 24) & 0xFF)
		data.3 = UInt8((timestamp >> 16) & 0xFF)
		data.4 = UInt8((timestamp >> 8) & 0xFF)
		data.5 = UInt8(timestamp & 0xFF)

		// Next 12 bits: version (4 bits) + random (8 bits)
		data.6 = (0x70 | (randomBytes[0] & 0x0F)) // Version 7
		data.7 = randomBytes[1]

		// Next 14 bits: variant (2 bits) + random (12 bits)
		data.8 = (0x80 | (randomBytes[2] & 0x3F)) // Variant 10
		data.9 = randomBytes[3]

		// Remaining 48 bits: random
		data.10 = randomBytes[4]
		data.11 = randomBytes[5]
		data.12 = randomBytes[6]
		data.13 = randomBytes[7]
		data.14 = randomBytes[8]
		data.15 = randomBytes[9]
	}

	public init?(data: Data) {
		guard data.count == 16 else { return nil }
		self.data = (
			data[0], data[1], data[2], data[3],
			data[4], data[5], data[6], data[7],
			data[8], data[9], data[10], data[11],
			data[12], data[13], data[14], data[15]
		)
	}

	public func withUnsafeBytes<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
		var tupleCopy = data
		return try withUnsafePointer(to: &tupleCopy) { ptr in
			try ptr.withMemoryRebound(to: UInt8.self, capacity: 16) { bytePtr in
				let buffer = UnsafeBufferPointer(start: bytePtr, count: 16)
				return try body(buffer)
			}
		}
	}

	static func == (lhs: UUIDv7, rhs: UUIDv7) -> Bool {
		return lhs.data.0 == rhs.data.0 &&
			lhs.data.1 == rhs.data.1 &&
			lhs.data.2 == rhs.data.2 &&
			lhs.data.3 == rhs.data.3 &&
			lhs.data.4 == rhs.data.4 &&
			lhs.data.5 == rhs.data.5 &&
			lhs.data.6 == rhs.data.6 &&
			lhs.data.7 == rhs.data.7 &&
			lhs.data.8 == rhs.data.8 &&
			lhs.data.9 == rhs.data.9 &&
			lhs.data.10 == rhs.data.10 &&
			lhs.data.11 == rhs.data.11 &&
			lhs.data.12 == rhs.data.12 &&
			lhs.data.13 == rhs.data.13 &&
			lhs.data.14 == rhs.data.14 &&
			lhs.data.15 == rhs.data.15
	}
}

extension UUIDv7: LosslessStringConvertible {
	init?(_ description: String) {
		// Remove hyphens and lowercase the string
		let hex = description.replacingOccurrences(of: "-", with: "").lowercased()
		guard hex.count == 32 else { return nil }

		var bytes = [UInt8]()
		bytes.reserveCapacity(16)
		var index = hex.startIndex
		for _ in 0..<16 {
			let nextIndex = hex.index(index, offsetBy: 2)
			guard nextIndex <= hex.endIndex,
				  let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
				return nil
			}
			bytes.append(byte)
			index = nextIndex
		}
		guard bytes.count == 16 else { return nil }
		self.data = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
	}

	var description: String {
		String(format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
			data.0, data.1, data.2, data.3,
			data.4, data.5, data.6, data.7,
			data.8, data.9, data.10, data.11,
			data.12, data.13, data.14, data.15)
	}
}

// SQLite callback function
func uuidv7SQLiteFunction(context: OpaquePointer?, argc: Int32, argv: UnsafeMutablePointer<OpaquePointer?>?) {
	// Generate a new UUIDv7 as binary data
	let uuidData = UUIDv7()

	// Set the binary data as BLOB result
	uuidData.withUnsafeBytes { bytes in
		sqlite3_result_blob(context, bytes.baseAddress, Int32(bytes.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
	}
}
