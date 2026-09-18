import Foundation

/// Gemmer alle svar, der har været vist. Et svar forsvinder fra låseskærmen, når
/// det næste kommer — men det står her bagefter.
@MainActor
final class HistoryStore: ObservableObject {

    @Published private(set) var replies: [ReplyRecord] = []

    private let fileURL: URL
    private let maximumEntries = 500

    init(filename: String = "svarhistorik.json") {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            // Oprettes med det samme med den beskyttelsesklasse, der tillader
            // skrivning, mens telefonen er låst.
            FileManager.default.createFile(
                atPath: fileURL.path,
                contents: nil,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        }
        load()
    }

    /// Nyeste først.
    var sorted: [ReplyRecord] {
        replies.sorted { $0.createdAt > $1.createdAt }
    }

    func record(_ reply: ReplyRecord) {
        replies.append(reply)
        if replies.count > maximumEntries {
            replies.removeFirst(replies.count - maximumEntries)
        }
        save()
    }

    /// Kaldes når et svar fjernes fra skærmen til fordel for et nyere.
    func markRetired(_ id: UUID, at date: Date = Date()) {
        guard let index = replies.firstIndex(where: { $0.id == id }) else { return }
        guard replies[index].retiredAt == nil else { return }
        replies[index].retiredAt = date
        save()
    }

    func delete(_ id: UUID) {
        replies.removeAll { $0.id == id }
        save()
    }

    func deleteAll() {
        replies.removeAll()
        save()
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        replies = (try? decoder.decode([ReplyRecord].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(replies) else { return }
        // Historikken skal kunne skrives, mens telefonen er låst.
        try? data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }
}
