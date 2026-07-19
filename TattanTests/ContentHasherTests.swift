import Foundation
import Testing
@testable import Tattan

struct ContentHasherTests {

    @Test func sameInputProducesSameHash() {
        let payload = Data("hello".utf8)
        #expect(ContentHasher.hash(kind: .text, payload: payload)
            == ContentHasher.hash(kind: .text, payload: payload))
    }

    @Test func differentPayloadProducesDifferentHash() {
        #expect(ContentHasher.hash(kind: .text, payload: Data("a".utf8))
            != ContentHasher.hash(kind: .text, payload: Data("b".utf8)))
    }

    /// 同じバイト列でも種別が違えば別物として扱う（C-9 の同一性は kind 込み）
    @Test func sameBytesDifferentKindProducesDifferentHash() {
        let payload = Data("/Users/ken/file.png".utf8)
        #expect(ContentHasher.hash(kind: .text, payload: payload)
            != ContentHasher.hash(kind: .fileReference, payload: payload))
    }
}
