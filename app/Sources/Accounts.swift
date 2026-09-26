import AppKit
import SwiftUI

/// A Roblox account saved for quick switching.
struct RobloxAccount: Identifiable, Decodable, Equatable {
    let userId: String
    let username: String
    let displayName: String
    let savedAt: String?
    let active: Bool

    var id: String { userId }
    var name: String { displayName.isEmpty ? username : displayName }
}

/// The account whose session is in the Roblox app right now.
struct SignedInAccount: Decodable, Equatable {
    let userId: String
    let username: String
    let displayName: String

    var name: String { displayName.isEmpty ? username : displayName }
}

/// Saved accounts and switching between them. The work is done by
/// `roblox-bootstrapper accounts`, which swaps the Roblox app's own sign-in
/// file while Roblox is closed; this class only drives it and fetches avatars.
final class AccountStore: ObservableObject, @unchecked Sendable {
    @Published private(set) var accounts: [RobloxAccount] = []
    @Published private(set) var current: SignedInAccount?
    @Published private(set) var avatars: [String: URL] = [:]
    @Published private(set) var working = false
    @Published var error: String?

    private struct Listing: Decodable {
        let current: SignedInAccount?
        let signedIn: Bool
        let accounts: [RobloxAccount]
    }

    var currentIsSaved: Bool {
        guard let current else { return false }
        return accounts.contains { $0.userId == current.userId }
    }

    func avatar(for userId: String?) -> URL? { userId.flatMap { avatars[$0] } }

    func refresh() {
        ScriptRunner.run(["accounts", "list", "--json"], completion: { result in
            guard result.succeeded, let data = result.output.data(using: .utf8),
                  let listing = try? JSONDecoder().decode(Listing.self, from: data) else { return }
            self.accounts = listing.accounts
            self.current = listing.current
            self.fetchAvatars()
        })
    }

    /// Refreshes saved sessions after Roblox quits (and finishes adding a new account).
    func autoSave() {
        // A switch in progress saves the outgoing account itself.
        guard !working else { return }
        ScriptRunner.run(["accounts", "save", "--auto"], completion: { _ in self.refresh() })
    }

    func saveCurrent() { run(["accounts", "save"]) }

    func remove(_ account: RobloxAccount) { run(["accounts", "remove", account.userId]) }

    /// Switches Roblox to `account`, closing Roblox first if it's open. If it
    /// was open, it's started again on the new account.
    func switchTo(_ account: RobloxAccount, model: LauncherModel) {
        guard !working else { return }
        working = true
        error = nil
        let relaunch = model.robloxRunning
        model.quitRoblox {
            ScriptRunner.run(["accounts", "use", account.userId], completion: { result in
                self.working = false
                self.refresh()
                if !result.succeeded {
                    self.error = result.errorMessage
                } else if relaunch {
                    model.launch()
                }
            })
        }
    }

    /// Signs Roblox out on this Mac (after saving the current account) and
    /// opens it so another account can sign in. It's saved when Roblox quits.
    func addAccount(model: LauncherModel) {
        guard !working else { return }
        working = true
        error = nil
        model.quitRoblox {
            ScriptRunner.run(["accounts", "add"], completion: { result in
                self.working = false
                self.refresh()
                if result.succeeded {
                    model.launch()
                } else {
                    self.error = result.errorMessage
                }
            })
        }
    }

    private func run(_ args: [String]) {
        working = true
        error = nil
        ScriptRunner.run(args, completion: { result in
            self.working = false
            if !result.succeeded { self.error = result.errorMessage }
            self.refresh()
        })
    }

    private struct Headshots: Decodable {
        struct Item: Decodable {
            let targetId: Int64
            let imageUrl: String?
        }
        let data: [Item]
    }

    private func fetchAvatars() {
        let ids = Set(accounts.map(\.userId) + [current?.userId].compactMap { $0 }).filter { avatars[$0] == nil }
        guard !ids.isEmpty,
              let url = URL(string: "https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=\(ids.sorted().joined(separator: ","))&size=150x150&format=Png&isCircular=false")
        else { return }
        Task.detached(priority: .utility) {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let result = try? JSONDecoder().decode(Headshots.self, from: data) else { return }
            var found: [String: URL] = [:]
            for item in result.data {
                if let image = item.imageUrl.flatMap(URL.init(string:)) { found[String(item.targetId)] = image }
            }
            let urls = found
            DispatchQueue.main.async { self.avatars.merge(urls) { $1 } }
        }
    }
}

// MARK: - Views

/// A round avatar for an account, with a placeholder until the picture loads.
struct AccountAvatar: View {
    @EnvironmentObject var model: LauncherModel
    let url: URL?
    let size: CGFloat
    var ring: Color = .white.opacity(0.4)

    var body: some View {
        RemoteImage(url: url) {
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.42))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: size, height: size)
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: size, height: size)
        .background(Circle().fill(LinearGradient(colors: [model.theme.accent.mixed(with: .white, by: 0.2), model.theme.accent],
                                                 startPoint: .top, endPoint: .bottom)))
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ring, lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}

/// The popover behind the rail's avatar: switch accounts in one click.
struct AccountSwitcher: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var router: Router
    @EnvironmentObject var accounts: AccountStore
    @Binding var isPresented: Bool
    @State private var pending: RobloxAccount?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Accounts").font(.ui(16, .heavy))
                Spacer()
                if accounts.working || model.busy { ProgressView().controlSize(.small) }
            }

            VStack(spacing: 4) {
                ForEach(accounts.accounts) { account in
                    AccountRow(name: account.name, username: account.username,
                               avatar: accounts.avatar(for: account.userId), active: account.active) {
                        choose(account)
                    }
                }
                if let current = accounts.current, !accounts.currentIsSaved {
                    AccountRow(name: current.name, username: current.username,
                               avatar: accounts.avatar(for: current.userId), active: true, note: "Not saved yet") {}
                }
                if accounts.accounts.isEmpty && accounts.current == nil {
                    Text("Roblox is signed out on this Mac.")
                        .font(.ui(12.5))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
            }

            if let pending {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Roblox will close and reopen as \(pending.name).")
                        .font(.ui(12.5, .semibold))
                    HStack {
                        Button("Switch") {
                            accounts.switchTo(pending, model: model)
                            self.pending = nil
                        }
                        .buttonStyle(.chunky(model.theme.accent, size: .small))
                        Button("Cancel") { withAnimation(.bounce) { self.pending = nil } }
                            .buttonStyle(.chunkyGlass(size: .small))
                    }
                }
                .padding(10)
                .glass(corner: 12)
                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
            }

            if let error = accounts.error {
                Text(error).font(.ui(12)).foregroundStyle(.orange)
            }

            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)

            HStack(spacing: 8) {
                if let current = accounts.current, !accounts.currentIsSaved {
                    Button { accounts.saveCurrent() } label: {
                        Label("Save \(current.name)", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.chunky(model.theme.accent, size: .small))
                } else {
                    Button { router.go(LauncherTab.accounts); isPresented = false } label: {
                        Label("Add Account", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.chunky(model.theme.accent, size: .small))
                }
                Spacer()
                Button("Manage") {
                    router.go(LauncherTab.accounts)
                    isPresented = false
                }
                .buttonStyle(.chunkyGlass(size: .small))
            }
        }
        .padding(16)
        .frame(width: 300)
        .environment(\.colorScheme, .dark)
        .animation(.bounce, value: pending)
        .onAppear { accounts.refresh() }
    }

    private func choose(_ account: RobloxAccount) {
        guard !account.active, !accounts.working else { return }
        if model.robloxRunning {
            withAnimation(.bounce) { pending = account }
        } else {
            accounts.switchTo(account, model: model)
        }
    }
}

private struct AccountRow: View {
    @EnvironmentObject var model: LauncherModel
    let name: String
    let username: String
    let avatar: URL?
    let active: Bool
    var note: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AccountAvatar(url: avatar, size: 36, ring: active ? model.theme.accent : .white.opacity(0.3))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.ui(13.5, .bold)).lineLimit(1)
                    Text(note ?? "@\(username)").font(.ui(11.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer()
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(model.theme.onAccent, model.theme.accent)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hovering && !active ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.97))
        .onHover { h in withAnimation(.snappy) { hovering = h } }
        .help(active ? "Signed in now" : "Switch to \(name)")
    }
}

/// Launcher › Accounts.
struct AccountsTab: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var accounts: AccountStore
    @State private var pending: RobloxAccount?
    @State private var removing: RobloxAccount?
    @State private var confirmAdd = false

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 14, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                IconBadge(symbol: "person.2.fill", size: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Switch Roblox accounts in one click")
                        .font(.ui(16, .heavy))
                    Text("Each saved account is a copy of the Roblox app's own sign-in, kept only on this Mac and readable only by you. The launcher never sees your password, and removing an account here doesn't sign it out anywhere.")
                        .font(.ui(12.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .glass(corner: 20)
            .appearIn(1)

            if let error = accounts.error {
                ErrorBanner(message: error) { accounts.error = nil }
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(accounts.accounts.enumerated()), id: \.element.id) { i, account in
                    AccountCard(account: account, index: i + 2) {
                        if model.robloxRunning { pending = account } else { accounts.switchTo(account, model: model) }
                    } remove: {
                        removing = account
                    }
                }
                if let current = accounts.current, !accounts.currentIsSaved {
                    UnsavedCard(current: current)
                }
                AddCard { confirmAdd = true }
                    .appearIn(accounts.accounts.count + 3)
            }

            Text("Website Play buttons join with whichever account is signed in on roblox.com in your browser.")
                .font(.ui(12))
                .foregroundStyle(.white.opacity(0.5))
        }
        .onAppear { accounts.refresh() }
        .confirmationDialog("Switch to \(pending?.name ?? "")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Close Roblox and Switch") {
                if let pending { accounts.switchTo(pending, model: model) }
                pending = nil
            }
        } message: {
            Text("Roblox is open. It will close and reopen signed in as \(pending?.name ?? "that account").")
        }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                if let removing { accounts.remove(removing) }
                removing = nil
            }
        } message: {
            Text("The launcher forgets this account's saved sign-in. It stays signed in wherever else you use it.")
        }
        .confirmationDialog("Add another account?", isPresented: $confirmAdd) {
            Button("Sign Out and Open Roblox") { accounts.addAccount(model: model) }
        } message: {
            Text("Your current account is saved first. Roblox then opens signed out so you can sign in to another account; it's saved automatically when you quit Roblox.")
        }
    }
}

private struct AccountCard: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var accounts: AccountStore
    let account: RobloxAccount
    let index: Int
    let switchAction: () -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            AccountAvatar(url: accounts.avatar(for: account.userId), size: 54,
                          ring: account.active ? model.theme.accent : .white.opacity(0.3))
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name).font(.ui(16, .heavy)).lineLimit(1)
                Text("@\(account.username)").font(.ui(12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                if account.active {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .font(.ui(11.5, .bold))
                        .foregroundStyle(model.theme.accent.mixed(with: .white, by: 0.35))
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                if !account.active {
                    Button("Switch", action: switchAction)
                        .buttonStyle(.chunky(model.theme.accent, size: .small))
                        .disabled(accounts.working || model.busy)
                }
                Button(action: remove) { Image(systemName: "trash").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(.chunkyGlass(size: .small))
                    .help("Remove \(account.name) from the launcher")
            }
        }
        .padding(16)
        .glass(corner: 20, highlighted: account.active || hovering,
               tint: account.active ? model.theme.accent : .white.opacity(0.3))
        .scaleEffect(hovering ? 1.02 : 1)
        .onHover { h in withAnimation(.bounce) { hovering = h } }
        .appearIn(index)
    }
}

private struct UnsavedCard: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var accounts: AccountStore
    let current: SignedInAccount

    var body: some View {
        HStack(spacing: 14) {
            AccountAvatar(url: accounts.avatar(for: current.userId), size: 54, ring: .white.opacity(0.3))
            VStack(alignment: .leading, spacing: 3) {
                Text(current.name).font(.ui(16, .heavy)).lineLimit(1)
                Text("Signed in now · not saved").font(.ui(12)).foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
            Button("Save") { accounts.saveCurrent() }
                .buttonStyle(.chunky(model.theme.accent, size: .small))
                .disabled(accounts.working)
        }
        .padding(16)
        .glass(corner: 20)
        .appearIn(2)
    }
}

private struct AddCard: View {
    @EnvironmentObject var model: LauncherModel
    @EnvironmentObject var accounts: AccountStore
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 54, height: 54)
                    .background(Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 4])).foregroundStyle(.white.opacity(0.4)))
                    .rotationEffect(.degrees(hovering ? 90 : 0))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add account").font(.ui(16, .heavy))
                    Text("Sign in to another Roblox account").font(.ui(12)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(corner: 20, highlighted: hovering, tint: .white.opacity(0.3))
            .scaleEffect(hovering ? 1.02 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(pressedScale: 0.96))
        .disabled(accounts.working || model.busy)
        .onHover { h in withAnimation(.wobble) { hovering = h } }
    }
}
