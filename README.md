# Noctorium for iOS

Noctorium on the iPhone and iPad: YouTube Music and SoundCloud in one player, native SwiftUI.

- **Home** — what's on YouTube Music and SoundCloud today, and what you played lately
- **Search** — songs or playlists on both services or one, and links: paste a YouTube, YouTube Music or SoundCloud
  link and it plays (or open `noctorium://open?url=<link>`)
- **Library** — liked songs, playlists of your own, and your history, all kept on the phone
- **Now playing** — synced lyrics from LRCLIB that follow the song, the queue (tap to jump, swipe to remove),
  autoplay once it runs out, and a sleep timer
- **In the background** — plays on with the screen locked, with the lock screen, Control Center, headphones,
  AirPlay and CarPlay's Now Playing

The music comes from the hosted web player's API (`noctorium-music.vercel.app/api/music`), which reads YouTube Music
and SoundCloud. A YouTube song's audio is asked for on the phone itself, the way yt-dlp asks: YouTube hands its
addresses to the device that asks. A SoundCloud track locked to SoundCloud's own app plays as the same recording on
YouTube Music, as the full Noctorium does.

## Installing it

It is not on the App Store. Each release has `Noctorium-<version>-ios.ipa`, unsigned: install it with
[AltStore](https://altstore.io) or [SideStore](https://sidestore.io), which sign it with your own Apple ID (and renew
it every seven days with a free one).

## Building it

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open Noctorium.xcodeproj
```

CI (`.github/workflows/ios.yml`) builds the unsigned .ipa on a Mac, runs the tests in the simulator — including one
that searches, plays a song and opens its lyrics — and keeps their screenshots.

Free software under the GPL-3.0. Not affiliated with YouTube, SoundCloud or Apple.
