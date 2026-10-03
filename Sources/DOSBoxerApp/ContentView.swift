import DOSBoxerKit
import SwiftUI

struct ContentView: View {
    let emulator: Emulator

    @State private var choosingFolder = false
    @State private var mountedFolder: URL?

    var body: some View {
        ZStack {
            Color.black
            EmulatorView(emulator: emulator)
                .opacity(emulator.isRunning ? 1 : 0)

            if !emulator.isRunning {
                StartCard(emulator: emulator, chooseFolder: { choosingFolder = true })
            }
        }
        .ignoresSafeArea()
        .navigationTitle(mountedFolder?.lastPathComponent ?? "DOS Boxer")
        .toolbar {
            ToolbarItemGroup {
                Button("Choose Game Folder…", systemImage: "folder.badge.plus") {
                    choosingFolder = true
                }
                Button("Restart", systemImage: "arrow.clockwise") {
                    Relauncher.relaunch(withFolder: mountedFolder)
                }
                .disabled(!emulator.isRunning)
                Button("Turn Off", systemImage: "power") {
                    emulator.stop()
                }
                .disabled(!emulator.isRunning)
            }
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            if emulator.canStart {
                start(folder: url)
            } else {
                Relauncher.relaunch(withFolder: url)
            }
        }
        .task {
            if let pending = Relauncher.consumePendingStart() {
                start(folder: pending)
            }
        }
    }

    /// Starts DOS, with `folder` (if any) as drive C.
    private func start(folder: URL?) {
        mountedFolder?.stopAccessingSecurityScopedResource()
        mountedFolder = folder
        var arguments: [String] = []
        if let folder, folder.startAccessingSecurityScopedResource() {
            arguments += ["-c", "MOUNT C \"\(folder.path(percentEncoded: false))\"", "-c", "C:"]
        }
        emulator.start(arguments: arguments)
    }
}

/// Shown while DOS isn't running: a floating glass card over the black screen.
private struct StartCard: View {
    let emulator: Emulator
    let chooseFolder: () -> Void

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 16) {
                Image(systemName: "pc")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.title2.weight(.semibold))
                Text("Start a DOS prompt, or choose a folder with a game in it to use as drive C.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 320)
                HStack(spacing: 12) {
                    Button("Choose Game Folder…", action: chooseFolder)
                        .buttonStyle(.glass)
                    Button(emulator.canStart ? "Start DOS" : "Start Again") {
                        if emulator.canStart {
                            emulator.start()
                        } else {
                            Relauncher.relaunch(withFolder: nil)
                        }
                    }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
            .padding(32)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
        .padding()
    }

    private var title: String {
        if case .stopped(let code) = emulator.state, code != 0 {
            return "DOS stopped unexpectedly"
        }
        return emulator.state == .stopping ? "Turning off…" : "DOS Boxer"
    }
}
