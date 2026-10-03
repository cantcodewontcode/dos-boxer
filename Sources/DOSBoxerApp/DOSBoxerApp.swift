import DOSBoxerKit
import SwiftUI

@main
struct DOSBoxerApp: App {
    @State private var emulator = Emulator()

    var body: some Scene {
        Window("DOS Boxer", id: "main") {
            ContentView(emulator: emulator)
                .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 960, height: 720)
        .windowToolbarStyle(.unified)
    }
}
