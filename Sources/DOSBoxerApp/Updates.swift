import Combine
import Sparkle
import SwiftUI

/// Software updates, through Sparkle: checks in the background at launch and
/// daily (unless turned off in Settings › Updates), and on request.
@MainActor @Observable
final class Updates {
    static let shared = Updates()

    private let controller = SPUStandardUpdaterController(startingUpdater: Updates.isConfigured,
                                                          updaterDelegate: nil, userDriverDelegate: nil)

    /// Builds without the update signing key (development builds) don't
    /// check: Sparkle would refuse, with an alert at every launch.
    static var isConfigured: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && key != "SPARKLE_PUBLIC_KEY"
    }
    private(set) var canCheck = false
    private(set) var lastChecked: Date?
    @ObservationIgnored private var observers: Set<AnyCancellable> = []

    private var updater: SPUUpdater { controller.updater }

    private init() {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheck = $0 }
            .store(in: &observers)
        updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastChecked = $0 }
            .store(in: &observers)
    }

    var checksAutomatically: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    func checkNow() {
        controller.checkForUpdates(nil)
    }
}

/// DOS Boxer › Check for Updates…
struct UpdateCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Updates.shared.checkNow() }
                .disabled(!Updates.shared.canCheck)
        }
    }
}

/// Settings › Updates.
struct UpdateSettings: View {
    private let updates = Updates.shared
    @State private var automatic = Updates.shared.checksAutomatically

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: $automatic)
                    .onChange(of: automatic) { _, on in updates.checksAutomatically = on }
                LabeledContent("Last checked") {
                    Text(updates.lastChecked?.formatted(.relative(presentation: .named)) ?? "Never")
                        .foregroundStyle(.secondary)
                }
                Button("Check Now") { updates.checkNow() }
                    .disabled(!updates.canCheck)
            } footer: {
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
