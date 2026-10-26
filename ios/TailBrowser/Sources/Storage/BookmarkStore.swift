import Foundation
import Combine

struct Bookmark: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var host: String
    var port: Int
    var scheme: String = "http"

    var url: URL? {
        TailWebURL.make(host: host, port: port, scheme: scheme)
    }
}

final class BookmarkStore: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []

    private let bookmarksKey = "tailweb.bookmarks.v1"
    private let portsKey = "tailweb.lastPorts.v1"
    private var lastPorts: [String: Int] = [:]

    init() {
        load()
    }

    func add(name: String, host: String, port: Int) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? host : trimmedName
        guard !bookmarks.contains(where: { $0.host == host && $0.port == port }) else {
            return
        }
        bookmarks.append(Bookmark(name: displayName, host: host, port: port))
        persist()
    }

    func remove(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where bookmarks.indices.contains(index) {
            bookmarks.remove(at: index)
        }
        persist()
    }

    func isBookmarked(host: String, port: Int) -> Bool {
        bookmarks.contains { $0.host == host && $0.port == port }
    }

    func lastPort(for host: String) -> Int? {
        lastPorts[host.lowercased()]
    }

    func remember(host: String, port: Int) {
        lastPorts[host.lowercased()] = port
        if let data = try? JSONEncoder().encode(lastPorts) {
            UserDefaults.standard.set(data, forKey: portsKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: bookmarksKey),
           let decoded = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = decoded
        }
        if let data = UserDefaults.standard.data(forKey: portsKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            lastPorts = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarksKey)
        }
    }
}
