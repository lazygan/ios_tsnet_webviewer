import SwiftUI

@main
struct TailWebApp: App {
    @StateObject private var manager = TailscaleManager()
    @StateObject private var bookmarks = BookmarkStore()
    @StateObject private var keepAlive = BackgroundKeepAlive()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(manager)
                .environmentObject(bookmarks)
                .environmentObject(keepAlive)
        }
    }
}
