import SwiftUI

/// The song playing, large: its cover, the seek bar and the buttons, and under them its lyrics or what comes next.
struct NowPlayingView: View {
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = .cover
    @State private var dragging: Double?

    enum Page { case cover, lyrics, queue }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title3.weight(.semibold)) }
                Spacer()
                Text("Now playing").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                sleepMenu
            }
            .padding(.horizontal)

            if let track = player.current {
                Group {
                    switch page {
                    case .cover:
                        Artwork(url: track.artwork, size: 300, corner: 16).shadow(radius: 20).frame(maxHeight: .infinity)
                    case .lyrics:
                        LyricsView(track: track)
                    case .queue:
                        QueueView()
                    }
                }
                .frame(maxHeight: .infinity)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title).font(.title3.bold()).lineLimit(2)
                        Text(player.error ?? track.artistLine).font(.body).foregroundStyle(player.error == nil ? .secondary : Color.red).lineLimit(1)
                    }
                    Spacer()
                    Button { store.toggleLike(track) } label: {
                        Image(systemName: store.isLiked(track) ? "heart.fill" : "heart").font(.title2)
                            .foregroundStyle(store.isLiked(track) ? Theme.accent : .primary)
                    }
                    .accessibilityIdentifier("like")
                }
                .padding(.horizontal, 24)

                VStack(spacing: 4) {
                    Slider(value: Binding(get: { dragging ?? player.position }, set: { dragging = $0 }),
                           in: 0...max(player.duration, 1)) { editing in
                        if !editing, let to = dragging { player.seek(to: to); dragging = nil }
                    }
                    HStack {
                        Text(formatTime(dragging ?? player.position))
                        Spacer()
                        Text(formatTime(player.duration))
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)

                HStack(spacing: 44) {
                    Button { player.previous() } label: { Image(systemName: "backward.fill").font(.title) }
                    Button { player.toggle() } label: {
                        ZStack {
                            Circle().fill(Theme.accent).frame(width: 76, height: 76)
                            if player.isLoading { ProgressView().tint(.black) } else {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.largeTitle).foregroundStyle(.black)
                            }
                        }
                    }
                    .accessibilityIdentifier("play-pause")
                    Button { player.next() } label: { Image(systemName: "forward.fill").font(.title) }
                }
                .foregroundStyle(.primary)

                HStack {
                    pageButton(.lyrics, "quote.bubble", "Lyrics")
                    Spacer()
                    Toggle(isOn: $store.autoplay) { Image(systemName: "infinity") }
                        .toggleStyle(.button)
                        .accessibilityLabel("Autoplay")
                    Spacer()
                    pageButton(.queue, "list.bullet", "Up next")
                }
                .font(.title3)
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
            } else {
                Spacer()
                Text("Nothing playing").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.top, 16)
        .background(Theme.background.ignoresSafeArea())
    }

    private func pageButton(_ target: Page, _ icon: String, _ label: String) -> some View {
        Button { withAnimation { page = page == target ? .cover : target } } label: {
            Image(systemName: icon).foregroundStyle(page == target ? Theme.accent : .primary)
        }
        .accessibilityLabel(label)
    }

    private var sleepMenu: some View {
        Menu {
            Button("Off") { player.sleep(minutes: nil) }
            Button("At the end of this song") { player.sleepAfterThisSong() }
            ForEach([15, 30, 45, 60, 90], id: \.self) { minutes in
                Button("In \(minutes) minutes") { player.sleep(minutes: minutes) }
            }
        } label: {
            Image(systemName: player.sleepAt != nil || player.sleepAtEndOfSong ? "moon.zzz.fill" : "moon.zzz").font(.title3)
                .foregroundStyle(player.sleepAt != nil || player.sleepAtEndOfSong ? Theme.accent : .primary)
        }
        .accessibilityLabel("Sleep timer")
    }
}

/// What comes after the song playing: tap one to play it now, swipe one away to take it out.
struct QueueView: View {
    @EnvironmentObject private var player: Player

    var body: some View {
        List {
            if player.upNext.isEmpty {
                Text(player.store.autoplay ? "Songs like this one follow when the queue runs out." : "Nothing after this song.")
                    .foregroundStyle(.secondary).listRowBackground(Color.clear)
            }
            ForEach(Array(player.upNext.enumerated()), id: \.offset) { offset, track in
                TrackRow(track: track) { player.jump(to: player.index + 1 + offset) }
                    .listRowBackground(Color.clear)
            }
            .onDelete { player.removeFromQueue(at: $0) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

/// The song's words, the line being sung lit and kept in view.
struct LyricsView: View {
    @EnvironmentObject private var player: Player
    var track: Track
    @State private var lyrics: Lyrics?
    @State private var searched = false

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let lyrics {
                        let now = lyrics.current(at: player.position)
                        ForEach(lyrics.lines) { line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(lyrics.synced ? .title3.weight(.bold) : .body)
                                .foregroundStyle(!lyrics.synced || line.id == now ? Color.primary : Color.secondary.opacity(0.6))
                                .id(line.id)
                                .onTapGesture { if lyrics.synced { player.seek(to: line.time) } }
                        }
                        Text("Lyrics from LRCLIB").font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                    } else if searched {
                        Text("No lyrics found for this song.").foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }
            .onChange(of: lyrics?.current(at: player.position)) { line in
                if let line { withAnimation { reader.scrollTo(line, anchor: .center) } }
            }
        }
        .task(id: track.key) {
            lyrics = nil; searched = false
            lyrics = await Lyrics.find(for: track)
            searched = true
        }
    }
}
