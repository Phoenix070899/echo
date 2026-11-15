import Foundry
import HubCore
import SwiftUI

/// Settings' Providers section (features/0089): who each agent CLI's agents run as, and Echo's own
/// sign-in for Claude and Codex, run by the CLI itself in a terminal under its row.
struct ProvidersSettings: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var providers = ProvidersModel()

    var body: some View {
        SettingsGroup {
            if providers.list.isEmpty {
                SettingsRow {
                    if let failure = providers.failure {
                        SettingsNote(failure, problem: true)
                    } else {
                        Pending("Reading each CLI's login").font(Ledger.font(15)).foregroundStyle(Ledger.ink3)
                    }
                }
            }
            ForEach(providers.list) { provider in
                SettingsRow(provider.name) { row(provider) }
            }
            SettingsRow("How") {
                SettingsNote("Agents and Workers run on Echo's own login once it is signed in, and on yours until then. Echo's login keeps your settings, instructions, skills and plugins; only the account differs.", size: 17)
                SettingsNote("Agents already running keep the account they started with. The usage in the title bar follows the account agents run on.")
            }
        }
        .task {
            while !Task.isCancelled {
                await providers.refresh()
                try? await Task.sleep(for: .seconds(providers.signingIn == nil ? 15 : 2))
            }
        }
    }

    @ViewBuilder
    private func row(_ provider: ProviderStatus) -> some View {
        Text(provider.line)
            .font(Ledger.font(15))
            .foregroundStyle(provider.installed && !provider.signedIn ? Ledger.fail : Ledger.ink)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        if provider.shared {
            SettingsNote("Kiro keeps one login for this Mac, so Echo uses yours. Sign in or out with `kiro-cli login` in a terminal.")
        } else if provider.installed {
            if providers.signingIn == provider.cli {
                LoginTerminal(cli: provider.cli, epoch: providers.epoch) { providers.signingIn = nil }
            } else {
                HStack(spacing: 10) {
                    if provider.own {
                        Button("Sign Out…") { providers.confirmSignOut(provider) }
                            .buttonStyle(.settings)
                    } else {
                        Button("Sign In") { providers.signIn(provider.cli) }
                            .buttonStyle(.settingsPrimary)
                    }
                }
                .disabled(providers.signingIn != nil || providers.busy)
            }
        }
    }
}

/// The CLI's own sign-in, running in a terminal under its row; Close puts it away. It closes by
/// itself once the login is Echo's.
private struct LoginTerminal: View {
    @EnvironmentObject private var model: AppModel
    let cli: String
    let epoch: Int
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TerminalPane(target: .login(cli: cli), command: .attach, client: model.client, appearance: model.appearance,
                         keyboard: !model.modalShown, focusRequest: epoch, epoch: "\(epoch)")
                .padding(.leading, 10)
                .padding(.vertical, 6)
                .frame(height: 300)
                .background { TerminalBackdrop(appearance: model.appearance) }
                .overlay(Rectangle().strokeBorder(Ledger.ink, lineWidth: Ledger.ruleStrong))
            HStack(spacing: 10) {
                SettingsNote("Follow the steps in the terminal; a link it prints opens in your browser.")
                Button("Close", action: close)
                    .buttonStyle(.settings)
            }
        }
    }
}

@MainActor
final class ProvidersModel: ObservableObject {
    @Published var list: [ProviderStatus] = []
    @Published var failure: String?
    @Published var busy = false
    /// The CLI whose sign-in terminal shows, if any.
    @Published var signingIn: String?
    /// A new terminal for each sign-in, so one that ended is not shown again.
    @Published var epoch = 0
    private let client = DaemonClient()

    func refresh() async {
        let client = client
        let result = await Task.detached { Result { try client.providers() } }.value
        switch result {
        case .success(let list):
            self.list = list
            failure = nil
            // Signed in: the terminal has done its part.
            if let cli = signingIn, list.first(where: { $0.cli == cli })?.own == true {
                signingIn = nil
            }
        case .failure(let error):
            failure = "The Hub Daemon did not answer: \(error)"
        }
    }

    func signIn(_ cli: String) {
        epoch += 1
        signingIn = cli
    }

    func confirmSignOut(_ provider: ProviderStatus) {
        FoundryAsk.shared.confirm("Sign Echo out of \(provider.name)?",
                                  message: "New agents on \(provider.name) run on your own login. Agents already running keep Echo's until they stop.",
                                  answer: FoundryAnswer("Sign Out", role: .destructive)) {
            self.signOut(provider.cli)
        }
    }

    private func signOut(_ cli: String) {
        busy = true
        let client = client
        Task {
            let result = await Task.detached { Result { try client.signOut(cli) } }.value
            busy = false
            if case .failure(let error) = result { failure = "Signing out failed: \(error)" }
            await refresh()
        }
    }
}
