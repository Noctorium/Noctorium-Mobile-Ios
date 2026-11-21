import SwiftUI

@main
struct NoctoriumApp: App {
    @StateObject private var store: Store
    @StateObject private var player: Player

    init() {
        let store = Store()
        _store = StateObject(wrappedValue: store)
        _player = StateObject(wrappedValue: Player(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.706, green: 0.486, blue: 1.0)
    static let background = Color(red: 0.043, green: 0.039, blue: 0.063)
    static let card = Color(red: 0.09, green: 0.082, blue: 0.122)
}

/// The three tabs, with the mini player above the tab bar on each, and Now playing over everything.
struct ContentView: View {
    @EnvironmentObject private var player: Player
    @State private var tab = 0
    @State private var showingNowPlaying = false
    @State private var linkMessage: String?

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView().withMiniPlayer($showingNowPlaying) }
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            NavigationStack { SearchView().withMiniPlayer($showingNowPlaying) }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(1)
                .accessibilityIdentifier("tab-search")
            NavigationStack { LibraryView().withMiniPlayer($showingNowPlaying) }
                .tabItem { Label("Library", systemImage: "music.note.list") }.tag(2)
        }
        .sheet(isPresented: $showingNowPlaying) { NowPlayingView() }
        // noctorium://open?url=<a YouTube, YouTube Music or SoundCloud link>, from a share sheet shortcut or a browser.
        .onOpenURL { url in
            guard let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value else { return }
            Task {
                do {
                    let opened = try await API.link(link)
                    if let track = opened.track { player.play([track]); showingNowPlaying = true }
                } catch { linkMessage = error.localizedDescription }
            }
        }
        .alert("Could not open that link", isPresented: Binding(get: { linkMessage != nil }, set: { if !$0 { linkMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(linkMessage ?? "") }
    }
}

extension View {
    func withMiniPlayer(_ showing: Binding<Bool>) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayer(showingNowPlaying: showing) }
            .background(Theme.background.ignoresSafeArea())
    }
}

/// The song playing, along the bottom: tap for Now playing.
struct MiniPlayer: View {
    @EnvironmentObject private var player: Player
    @Binding var showingNowPlaying: Bool

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Rectangle().fill(Theme.accent)
                        .frame(width: player.duration > 0 ? geo.size.width * min(1, player.position / player.duration) : 0)
                }
                .frame(height: 2)
                HStack(spacing: 12) {
                    Artwork(url: track.artwork, size: 44, corner: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(player.error ?? (player.isLoading ? "Loading…" : track.artistLine))
                            .font(.caption).foregroundStyle(player.error == nil ? .secondary : Color.red).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title2).frame(width: 40, height: 40)
                    }
                    .accessibilityIdentifier("mini-play")
                    Button { player.next() } label: { Image(systemName: "forward.fill").font(.title3).frame(width: 40, height: 40) }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture { showingNowPlaying = true }
            }
            .foregroundStyle(.primary)
            .background(.ultraThinMaterial)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mini-player")
            .accessibilityValue(player.error.map { "error: \($0)" } ?? (player.isLoading ? "loading" : player.isPlaying ? "playing" : "paused"))
        }
    }
}
