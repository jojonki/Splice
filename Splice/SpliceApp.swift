import SwiftUI

@main
struct SpliceApp: App {
    @State private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ProjectListView()
                .environment(store)
        }
    }
}
