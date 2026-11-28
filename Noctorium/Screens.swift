import PhotosUI
import SwiftUI

// MARK: - Home

/// What is on YouTube Music and SoundCloud today, and what the listener played lately.
struct HomeView: View {
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var store: Store
    @State private var sections: [HomeSection] = []
    @State private var failure: String?
    @State private var loading = false
    @State private var showingAccount = false
    @State private var showingStats = false
    @EnvironmentObject private var account: Account

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if !store.recent.isEmpty {
                    Heading("Played lately")
                    ForEach(Array(store.recent.prefix(5).enumerated()), id: \.element.key) { i, track in
                        TrackRow(track: track) { player.play(Array(store.recent.prefix(30)), from: i) }.padding(.horizontal)
                    }
                }
                if loading && sections.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
                if let failure, sections.isEmpty { Failed(message: failure) { Task { await load() } } }
                ForEach(sections, id: \.identity) { section in
                    Heading(section.title)
                    if !section.playlists.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(section.playlists) { playlist in
                                    NavigationLink(value: playlist) { PlaylistCard(playlist: playlist) }.buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    ForEach(Array(section.tracks.prefix(6).enumerated()), id: \.element.key) { i, track in
                        TrackRow(track: track) { player.play(section.tracks, from: i) }.padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .navigationTitle("Noctorium")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                // The picture opens a choice of the account or its Stats, as in the other apps.
                Menu {
                    Button { showingAccount = true } label: { Label("Account", systemImage: "person.crop.circle") }
                    Button { showingStats = true } label: { Label("Stats", systemImage: "chart.bar") }
                } label: { Avatar(size: 32) }
                .accessibilityLabel("Noctorium account")
            }
        }
        .sheet(isPresented: $showingAccount) { AccountView().environmentObject(account) }
        .sheet(isPresented: $showingStats) { StatsView().environmentObject(account) }
        .navigationDestination(for: Playlist.self) { PlaylistView(playlist: $0) }
        .refreshable { await load() }
        .task { if sections.isEmpty { await load() } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { sections = try await API.home(); failure = nil } catch { failure = error.localizedDescription }
    }
}

struct Heading: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.title2.bold()).padding(.horizontal).padding(.top, 14)
    }
}

// MARK: - Search

/// Songs or playlists on both services or one, and links: a pasted YouTube, YouTube Music or SoundCloud link plays.
struct SearchView: View {
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var store: Store
    @State private var query = ""
    @State private var kind: SearchKind = .songs
    @State private var results: SearchResults?
    @State private var failure: String?
    @State private var searching = false
    @State private var opened: Playlist?

    var body: some View {
        List {
            Section {
                Picker("Where", selection: $store.searchMode) {
                    ForEach(SearchMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("What", selection: $kind) {
                    ForEach(SearchKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            if searching { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
            if let failure { Text(failure).foregroundStyle(.secondary).listRowBackground(Color.clear) }
            if let results {
                if results.tracks.isEmpty && results.playlists.isEmpty && (results.albums ?? []).isEmpty {
                    Text("Nothing found for “\(query)”.").foregroundStyle(.secondary).listRowBackground(Color.clear)
                }
                let lists = results.playlists + (results.albums ?? []).map(\.asPlaylist)
                if !lists.isEmpty {
                    Section(kind == .playlists ? "Playlists" : "Playlists and albums") {
                        ForEach(kind == .playlists ? lists : Array(lists.prefix(6))) { playlist in
                            NavigationLink(value: playlist) { PlaylistRow(playlist: playlist) }
                        }
                    }
                }
                if !results.tracks.isEmpty {
                    Section("Songs") {
                        ForEach(Array(results.tracks.enumerated()), id: \.element.key) { i, track in
                            TrackRow(track: track) { player.play(results.tracks, from: i) }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("Search")
        .navigationDestination(for: Playlist.self) { PlaylistView(playlist: $0) }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Songs, artists, or a link")
        .onSubmit(of: .search) { Task { await run() } }
        .onChange(of: store.searchMode) { _ in Task { await run() } }
        .onChange(of: kind) { _ in Task { await run() } }
        .navigationDestination(isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } })) {
            if let opened { PlaylistView(playlist: opened) }
        }
    }

    private func run() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        defer { searching = false }
        failure = nil
        do {
            if q.hasPrefix("http") || q.contains("youtu.be/") || q.contains("soundcloud.com/") {
                let link = try await API.link(q)
                if let track = link.track { player.play([track]) }
                if let key = link.playlist?.key { opened = Playlist(key: key, title: "Playlist") }
                return
            }
            results = try await API.search(q, mode: store.searchMode, kind: kind)
        } catch {
            failure = error.localizedDescription
        }
    }
}

// MARK: - A playlist on a service

struct PlaylistView: View {
    @EnvironmentObject private var player: Player
    var playlist: Playlist
    @State private var title: String?
    @State private var tracks: [Track] = []
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Artwork(url: playlist.artwork ?? tracks.first?.artwork, size: 200, corner: 14)
                    Text(title ?? playlist.title).font(.title2.bold()).multilineTextAlignment(.center)
                    Text([playlist.ownerName, tracks.isEmpty ? nil : "\(tracks.count) songs"].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary)
                    PlayButtons(tracks: tracks)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            if let failure { Failed(message: failure) { Task { await load() } }.listRowBackground(Color.clear) }
            if tracks.isEmpty && failure == nil { ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear) }
            ForEach(Array(tracks.enumerated()), id: \.element.key) { i, track in
                TrackRow(track: track) { player.play(tracks, from: i) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .task { if tracks.isEmpty { await load() } }
    }

    private func load() async {
        do {
            let reply = try await API.playlist(playlist.key)
            tracks = reply.tracks ?? []
            if let name = reply.title, !name.isEmpty { title = name }
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

// MARK: - Library

/// The Noctorium account: sign in with a code on the service's page -- Discord, Telegram or email -- and what
/// plays here is counted, and shown as your Discord status and Telegram bio.
struct AccountSection: View {
    @EnvironmentObject private var account: Account
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            if account.signedIn {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Signed in as \(account.name)").font(.headline)
                    Text("\(account.streams) listens counted").font(.caption).foregroundStyle(.secondary)
                }
                Button("Sign out", role: .destructive) { account.signOut() }
            } else if let code = account.code {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Allow Noctorium in your browser. Check it shows this code:").font(.subheadline).foregroundStyle(.secondary)
                    Text(code).font(.system(.title, design: .monospaced).weight(.bold)).textSelection(.enabled)
                    Text("Waiting for you to allow it…").font(.caption).foregroundStyle(.secondary)
                }
                if let page = account.pageURL { Button("Open page") { openURL(page) } }
                Button("Cancel", role: .cancel) { account.cancel() }
            } else {
                Text(account.message ?? "Sign in with Discord, Telegram or email to count your listening, show what you play on Discord and Telegram, and scrobble to the Last.fm and ListenBrainz linked to your account.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { account.signIn() } label: { Label("Sign in", systemImage: "person.crop.circle") }
            }
        } header: { Text("Noctorium account") }
    }
}

/// The listener's round picture, or the initial of their name when there is none.
struct Avatar: View {
    @EnvironmentObject private var account: Account
    var size: CGFloat

    var body: some View {
        if let url = account.avatarURL {
            Artwork(url: url, size: size, corner: size / 2)
        } else {
            ZStack {
                Circle().fill(Theme.card)
                if account.name.isEmpty {
                    Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundStyle(Theme.accent)
                } else {
                    Text(account.name.prefix(1).uppercased()).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(Theme.accent)
                }
            }
            .frame(width: size, height: size)
        }
    }
}

/// A picture as the 256-pixel square JPEG the account service keeps, cropped from its middle.
func squareJPEG(_ image: UIImage, side: CGFloat = 256) -> Data? {
    guard image.size.width > 0, image.size.height > 0 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let scale = side / min(image.size.width, image.size.height)
    let width = image.size.width * scale
    let height = image.size.height * scale
    let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
        image.draw(in: CGRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height))
    }
    return square.jpegData(compressionQuality: 0.85)
}

/// Signing in and out, and once signed in what the account page on the service offers: the picture, the name, the
/// email, the password and deleting, with the password and two-step code a change asks for.
@MainActor
struct AccountView: View {
    @EnvironmentObject private var account: Account
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var fresh = ""
    @State private var confirm = ""
    @State private var picked: PhotosPickerItem?
    @State private var busy = false
    @State private var status: String?
    @State private var failed = false

    private var twoStep: Bool { account.totp || account.telegramCodes }
    private var proofs: [String: String] { ["password": password, "code": code.trimmingCharacters(in: .whitespaces)] }

    var body: some View {
        NavigationStack {
            Form {
                if account.signedIn { signedIn } else { AccountSection() }
            }
            .disabled(busy)
            .navigationTitle("Noctorium account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: account.name + "|" + account.email) {
                name = account.name
                email = account.email
            }
            .onChange(of: picked) { item in
                guard let item else { return }
                picked = nil
                run { await upload(item) }
            }
        }
    }

    @ViewBuilder private var signedIn: some View {
        Section {
            VStack(spacing: 8) {
                Avatar(size: 96)
                Text([account.name, account.email, "\(account.streams) listens"].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let status {
                    Text(status).font(.footnote).foregroundStyle(failed ? Color.red : Color.secondary).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
        Section("Picture") {
            PhotosPicker(selection: $picked, matching: .images) { Label("Choose a photo", systemImage: "photo") }
            if account.discordLinked { Button("Use Discord's picture") { run { await account.change("avatar-discord") } } }
            if account.telegramLinked { Button("Use Telegram's picture") { run { await account.change("avatar-telegram") } } }
            if account.avatarURL != nil {
                Button("Remove the picture", role: .destructive) { run { await account.change("avatar-remove") } }
            }
        }
        Section("Name") {
            TextField("Name", text: $name)
            Button("Save") { run { await account.change("name", ["name": name.trimmingCharacters(in: .whitespaces)]) } }
        }
        if account.hasPassword || twoStep {
            Section {
                if account.hasPassword { SecureField("Your password", text: $password) }
                if twoStep { TextField("Two-step code", text: $code).keyboardType(.numberPad) }
                if account.telegramCodes { Button("Send a code by Telegram") { run { await account.telegramCode() } } }
            } header: {
                Text("Proof")
            } footer: {
                Text("Changing the email or password, or deleting the account, asks for these.")
            }
        }
        Section("Email") {
            TextField("Email", text: $email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Change email") {
                var fields = proofs
                fields["email"] = email.trimmingCharacters(in: .whitespaces)
                run { await account.change("email", fields) }
            }
        }
        Section(account.hasPassword ? "Password" : "Add a password") {
            SecureField("New password", text: $fresh)
            Button("Set password") {
                let fields = ["current": password, "code": proofs["code"] ?? "", "password": fresh]
                run { await account.change("password", fields) }
            }
        }
        Section {
            TextField("Type “delete my account”", text: $confirm).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Delete the account", role: .destructive) {
                var fields = proofs
                fields["confirm"] = confirm
                run { await account.change("delete", fields) }
            }
        } header: {
            Text("Delete the account")
        } footer: {
            Text("Everything on the account goes, for good, and every device is signed out.")
        }
        Section { Button("Sign out", role: .destructive) { account.signOut() } }
    }

    /// One change at a time, its outcome said under the picture.
    private func run(_ work: @escaping @MainActor () async -> String?) {
        busy = true
        failed = false
        status = "Working…"
        Task { @MainActor in
            let problem = await work()
            busy = false
            failed = problem != nil
            status = problem ?? "Saved."
        }
    }

    private func upload(_ item: PhotosPickerItem) async -> String? {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
              let jpeg = squareJPEG(image) else { return "That picture could not be opened." }
        return await account.upload(jpeg)
    }
}


/// Liked songs, the listener's own playlists, and what they played lately — all on the phone.
struct LibraryView: View {
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var store: Store
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        List {
            AccountSection()
            Section {
                NavigationLink {
                    SongsView(title: "Liked songs", tracks: store.liked)
                } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            Image(systemName: "heart.fill").foregroundStyle(.white)
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading) {
                            Text("Liked songs").font(.headline)
                            Text("\(store.liked.count) songs").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                ForEach(store.playlists) { playlist in
                    NavigationLink {
                        LocalPlaylistView(id: playlist.id)
                    } label: {
                        HStack(spacing: 12) {
                            Artwork(url: playlist.tracks.first?.artwork, size: 48, corner: 6)
                            VStack(alignment: .leading) {
                                Text(playlist.title).font(.body.weight(.semibold))
                                Text("\(playlist.tracks.count) songs").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in offsets.map { store.playlists[$0] }.forEach(store.delete) }
                Button { newName = ""; naming = true } label: { Label("New playlist", systemImage: "plus") }
            } header: { Text("Your playlists") }
            if !store.recent.isEmpty {
                Section {
                    ForEach(Array(store.recent.enumerated()), id: \.element.key) { i, track in
                        TrackRow(track: track) { player.play(store.recent, from: i) }
                    }
                    Button("Clear history", role: .destructive) { store.clearHistory() }
                } header: { Text("Played lately") }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Library")
        .navigationDestination(for: Playlist.self) { PlaylistView(playlist: $0) }
        .alert("New playlist", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Create") { store.createPlaylist(newName) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct SongsView: View {
    @EnvironmentObject private var player: Player
    var title: String
    var tracks: [Track]

    var body: some View {
        List {
            PlayButtons(tracks: tracks).listRowBackground(Color.clear)
            if tracks.isEmpty {
                Text("Hold a song anywhere and choose Like to keep it here.").foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
            ForEach(Array(tracks.enumerated()), id: \.element.key) { i, track in
                TrackRow(track: track) { player.play(tracks, from: i) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(title)
    }
}

struct LocalPlaylistView: View {
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var store: Store
    var id: UUID
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let playlist = store.playlist(id)
        let tracks = playlist?.tracks ?? []
        List {
            PlayButtons(tracks: tracks).listRowBackground(Color.clear)
            if tracks.isEmpty {
                Text("Hold a song anywhere and choose Add to a playlist.").foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
            ForEach(Array(tracks.enumerated()), id: \.element.key) { i, track in
                TrackRow(track: track) { player.play(tracks, from: i) }
            }
            .onDelete { offsets in if let playlist { store.remove(at: offsets, from: playlist) } }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(playlist?.title ?? "Playlist")
        .toolbar {
            Button("Rename") { newName = playlist?.title ?? ""; renaming = true }
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { if let playlist { store.rename(playlist, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}
