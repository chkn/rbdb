import Foundation
import Testing

func assertJSON<T: Codable & Equatable>(_ value: T, expect: String) throws {
	let enc = JSONEncoder()
	let data = try enc.encode(value)
	let json = String(data: data, encoding: .utf8)!
	#expect(json == expect)

	let dec = JSONDecoder()
	let value2 = try dec.decode(T.self, from: data)
	#expect(value2 == value)
}
