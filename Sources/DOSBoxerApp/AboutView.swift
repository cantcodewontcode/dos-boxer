import SwiftUI

/// DOS Boxer › About DOS Boxer.
struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text("DOS Boxer")
                .font(.title2.weight(.semibold))
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Link("GitHub", destination: URL(string: "https://github.com/cantcodewontcode/dos-boxer")!)
                Link("Buy me a coffee", destination: URL(string: "https://paypal.me/williamspry36")!)
            }
            .padding(.top, 6)
            VStack(spacing: 2) {
                Text("© 2026 William Spry")
                Text("Licensed under GPLv2 or later.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .fixedSize()
    }
}

/// Replaces the standard About panel with DOS Boxer's own.
struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About DOS Boxer") { openWindow(id: "about") }
        }
    }
}
