import Foundation

extension Shelf {
    /// Adds a jar at the right end. Nil when the shelf is full or the name is blank.
    @discardableResult
    public mutating func addJar(named raw: String) -> Jar? {
        guard jars.count < Self.maxJars, let name = Self.cleanName(raw) else { return nil }
        let jar = Jar(name: name)
        jars.append(jar)
        return jar
    }

    /// Takes a jar off the shelf with everything in it; the caller deletes the stored files.
    @discardableResult
    public mutating func removeJar(_ id: UUID) -> Jar? {
        guard let i = jarIndex(id) else { return nil }
        return jars.remove(at: i)
    }

    @discardableResult
    public mutating func rename(_ id: UUID, to raw: String) -> Bool {
        guard let i = jarIndex(id), let name = Self.cleanName(raw) else { return false }
        jars[i].name = name
        return true
    }

    /// Remembers where the jar was left. False when nothing changed, so the caller can skip saving.
    @discardableResult
    public mutating func place(_ jarID: UUID, at place: Place) -> Bool {
        guard let i = jarIndex(jarID), jars[i].place != place else { return false }
        jars[i].place = place
        return true
    }

    /// Something was taken out of the jar: its dust starts again from now.
    public mutating func markTaken(from jarID: UUID, at date: Date = Date()) {
        guard let i = jarIndex(jarID) else { return }
        jars[i].lastTakenAt = date
    }

    public mutating func add(_ items: [Item], to jarID: UUID) {
        guard let i = jarIndex(jarID) else { return }
        jars[i].items.append(contentsOf: items)
    }

    /// Takes everything out of the jar for good; the caller deletes the stored files.
    @discardableResult
    public mutating func empty(_ jarID: UUID) -> [Item] {
        guard let i = jarIndex(jarID) else { return [] }
        let items = jars[i].items
        jars[i].items.removeAll()
        return items
    }

    /// Takes the item out for good.
    @discardableResult
    public mutating func remove(_ itemID: UUID) -> Item? {
        guard let at = locate(itemID) else { return nil }
        return jars[at.jar].items.remove(at: at.item)
    }

    public mutating func update(_ itemID: UUID, _ change: (inout Item) -> Void) {
        guard let at = locate(itemID) else { return }
        change(&jars[at.jar].items[at.item])
    }

    /// Whether the jar already holds this address, so the same link is not kept twice.
    public func contains(link: String, in jarID: UUID) -> Bool {
        guard let i = jarIndex(jarID) else { return false }
        return jars[i].items.contains { $0.kind == .link && $0.url == link }
    }

    /// Every stored file the shelf still points to.
    public var referencedFiles: Set<String> {
        Set(jars.flatMap { $0.items.compactMap(\.fileName) })
    }
}
