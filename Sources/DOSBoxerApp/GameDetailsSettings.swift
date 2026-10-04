import DOSBoxerKit
import SwiftUI

/// Settings › Game Details: download, update or remove the LaunchBox details.
struct GameDetailsSettings: View {
    private let pack = GameDetailsPack.shared

    var body: some View {
        Form {
            Section {
                switch pack.state {
                case .notInstalled:
                    LabeledContent("Game details") { Text("Not downloaded").foregroundStyle(.secondary) }
                    Button("Download") { pack.install() }
                case .working(let step, let progress):
                    GameDetailsProgress(step: step, progress: progress) { pack.cancel() }
                case .installed(let count, let updated):
                    LabeledContent("Game details") {
                        Text("\(count.formatted()) games, updated \(updated.formatted(date: .abbreviated, time: .omitted))")
                    }
                    HStack {
                        Button("Update") { pack.install(onlyIfNewer: true) }
                        Button("Remove", role: .destructive) { pack.remove() }
                        if pack.isUpToDate {
                            Text("Already up to date.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                case .failed(let message):
                    Text(message).foregroundStyle(.secondary)
                    Button("Try Again") { pack.install() }
                }
            } footer: {
                Text("""
                    Release years, publishers, genres and descriptions come from the \
                    [LaunchBox Games Database](https://gamesdb.launchbox-app.com), kindly made \
                    available by LaunchBox. Removing them keeps the details already shown for your games.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Downloading…" with a progress bar and Cancel.
struct GameDetailsProgress: View {
    let step: GameDetailsPack.Step
    let progress: Double?
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgressView(value: progress) { Text(step.title).font(.callout) }
            Button("Cancel", action: cancel)
        }
    }
}

/// Asked once, on first launch: download the game details?
struct GameDetailsPrompt: View {
    @Environment(\.dismiss) private var dismiss
    private let pack = GameDetailsPack.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tint)
            Text("Download Game Details?")
                .font(.title3.weight(.semibold))
            Text("""
                Release years, publishers, genres and descriptions for thousands of DOS games, \
                from the LaunchBox Games Database.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch pack.state {
            case .working(let step, let progress):
                GameDetailsProgress(step: step, progress: progress) {
                    pack.cancel()
                    dismiss()
                }
            case .failed(let message):
                Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                buttons(download: "Try Again")
            default:
                buttons(download: "Download")
            }
        }
        .padding(24)
        .frame(width: 380)
        .onChange(of: pack.state) { _, state in
            if case .installed = state { dismiss() }
        }
    }

    private func buttons(download: String) -> some View {
        HStack {
            Button("Not Now") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(download) { pack.install() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
        }
        .controlSize(.large)
    }
}
