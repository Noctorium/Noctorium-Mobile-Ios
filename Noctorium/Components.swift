import SwiftUI

/// A cover, or a quiet square while it loads or when there is none.
struct Artwork: View {
    var url: URL?
    var size: CGFloat
    var corner: CGFloat = 8

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.card
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

/// A song in a list: tap to play it from that list; hold for what else can be done with it.
struct TrackRow: View {
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var store: Store
    var track: Track
    var play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                Artwork(url: track.artwork, size: 48, corner: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(player.current == track ? Theme.accent : .primary)
                        .lineLimit(1)
                    Text("\(track.artistLine) · \(track.serviceName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if store.isLiked(track) { Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.accent) }
                if track.duration > 0 { Text(formatTime(track.duration)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("track-row")
        .contextMenu { TrackMenu(track: track) }
    }
}

/// Play next, add to the queue, like, or put in one of the listener's own playlists.
struct TrackMenu: View {
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var store: Store
    var track: Track

    var body: some View {
        Button { player.playNext(track) } label: { Label("Play next", systemImage: "text.insert") }
        Button { player.addToQueue(track) } label: { Label("Add to queue", systemImage: "text.append") }
        Button { store.toggleLike(track) } label: {
            Label(store.isLiked(track) ? "Unlike" : "Like", systemImage: store.isLiked(track) ? "heart.slash" : "heart")
        }
        Menu {
            ForEach(store.playlists) { playlist in
                Button(playlist.title) { store.add(track, to: playlist) }
            }
            Button { store.add(track, to: store.createPlaylist("New playlist")) } label: { Label("New playlist", systemImage: "plus") }
        } label: { Label("Add to a playlist", systemImage: "music.note.list") }
        if let source = track.sourceUrl, let url = URL(string: source) {
            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
        }
    }
}

/// A playlist as a cover with its name, for a row of them.
struct PlaylistCard: View {
    var playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Artwork(url: playlist.artwork, size: 140, corner: 10)
            Text(playlist.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(playlist.ownerName ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 140)
    }
}

struct PlaylistRow: View {
    var playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            Artwork(url: playlist.artwork, size: 48, corner: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.title).font(.body.weight(.semibold)).lineLimit(1)
                Text(["Playlist", playlist.ownerName, playlist.trackCount.map { "\($0) songs" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// Play and Shuffle, above a list of songs.
struct PlayButtons: View {
    @EnvironmentObject private var player: Player
    var tracks: [Track]

    var body: some View {
        HStack(spacing: 12) {
            Button { player.play(tracks) } label: { Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
            Button { player.shuffle(tracks) } label: { Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
        }
        .disabled(tracks.isEmpty)
    }
}

/// What went wrong, with a way to try again.
struct Failed: View {
    var message: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Try again", action: retry).buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
