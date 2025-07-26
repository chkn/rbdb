import Foundation
import Testing

@testable import RBDB

@Test func predicateNameIsLowercased() async throws {
	let predicate = Predicate(name: "FooBar", arguments: [])
	#expect(predicate.name == "foobar")
}

@Test func predicateNameWithMixedCase() async throws {
	let predicate = Predicate(name: "SomePredicateName", arguments: [.string("test")])
	#expect(predicate.name == "somepredicatename")
}

@Test func predicateNameAlreadyLowercase() async throws {
	let predicate = Predicate(name: "lowercase", arguments: [])
	#expect(predicate.name == "lowercase")
}
