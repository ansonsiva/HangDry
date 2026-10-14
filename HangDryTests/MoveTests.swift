import Foundation
import Testing

@MainActor
struct MoveTests {
    private func store(_ names: [String]) throws -> (Sandbox, RopeStore) {
        let sandbox = try Sandbox()
        let store = RopeStore(directory: sandbox.url("Support"))
        store.hang(try names.map { try sandbox.file($0) }, origin: .dropped)
        return (sandbox, store)
    }

    private func id(_ name: String, in store: RopeStore) -> UUID {
        store.items.first { $0.name == name }!.id
    }

    @Test func movesForward() throws {
        let (_, store) = try store(["a", "b", "c", "d"])
        store.move([id("a", in: store)], to: 3)
        #expect(store.items.map(\.name) == ["b", "c", "a", "d"])
    }

    @Test func movesBackward() throws {
        let (_, store) = try store(["a", "b", "c", "d"])
        store.move([id("d", in: store)], to: 1)
        #expect(store.items.map(\.name) == ["a", "d", "b", "c"])
    }

    @Test func movesSeveralKeepingTheirOrder() throws {
        let (sandbox, store) = try store(["a", "b", "c", "d", "e"])
        store.move([id("d", in: store), id("a", in: store)], to: 3)
        #expect(store.items.map(\.name) == ["b", "c", "a", "d", "e"])
        #expect(RopeStore(directory: sandbox.url("Support")).items.map(\.name) == ["b", "c", "a", "d", "e"], "要存盘")
    }

    @Test func toTheEndAndStart() throws {
        let (_, store) = try store(["a", "b", "c"])
        store.move([id("a", in: store)], to: 3)
        #expect(store.items.map(\.name) == ["b", "c", "a"])
        store.move([id("a", in: store)], to: 0)
        #expect(store.items.map(\.name) == ["a", "b", "c"])
    }
}
