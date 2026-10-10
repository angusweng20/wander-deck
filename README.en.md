# Wander Deck

**Turn the photos from a trip into a presentation you can jump around in.**

Pick photos → choose how to group them (by place, by date, by hand, or by AI) → click “Make”. Done.
The result is a plain folder: copy it to anyone, double-click, and it plays offline.

[繁體中文](README.md)

## Features

- 📍 **Automatic grouping** by country → city or one topic per day, read from each photo's location and time. Photos without a location borrow it from shots taken around the same time.
- ✨ **AI helper** — sign in with your own ChatGPT Plus/Pro subscription. The AI looks at your photos to name topics, write a title, or sort photos into topics you choose. No extra cost.
- 🎨 **Style packs** — built in: Watercolor Journey, Ukiyo-e, Classic Prints. Photos taken in Japan get Ukiyo-e automatically. The format is open; anyone can make and share one.
- 🔀 **Non-linear** — a few intro pages, then jump to any topic. Click a photo to zoom in, with a magnifier.
- 🎞️ **Animated intro** — lanterns sway, a balloon drifts, leaves move in the breeze, the title waves like a flag.
- 🍎 **Apple-first** — pick straight from the Photos app; HEIC, Live Photos and videos just work.
- 🔒 **Private** — generated images are stripped of GPS and camera data; the AI only sees small, cleaned thumbnails. Your originals are never changed.

## Install

Requires macOS 14 (Sonoma) or later.

### Option 1: one line (recommended)

Open Terminal, paste, press Return:

```bash
curl -fsSL https://raw.githubusercontent.com/angusweng20/wander-deck/main/scripts/install.sh | bash
```

It picks the right build for your Mac (Apple silicon or Intel), verifies it, installs it to Applications and opens it.

### Option 2: download

Get `Wander-Deck-…-AppleSilicon.zip` (M1 and later) or `…-Intel.zip` from
[Releases](https://github.com/angusweng20/wander-deck/releases/latest), unzip, and drag “Wander Deck” into Applications.

**macOS will block it the first time.** That's expected: Wander Deck is free open-source software and isn't paid-signed with Apple. To allow it:

1. Double-click it; when you see “cannot be opened”, click Done.
2. Open System Settings → Privacy & Security and scroll down.
3. Next to “Wander Deck was blocked…”, click **Open Anyway** and enter your password.
4. Open it again and click Open. You won't be asked again.

(If the app says “Your Mac blocked the AI helper (pi)”, allow pi the same way.)

## How to use

1. **Sign in** (optional): click “Sign in with ChatGPT” and log in in your browser. If you already use [Pi](https://pi.dev) on this Mac, that sign-in is reused.
2. **Pick photos** from the Photos app, or drag in photos and folders.
3. **Sort** by place, by date, by hand, or with AI. Rename topics on the left; drag photos between topics.
4. **Details**: title, subtitle (the AI can write them), style, background music, a QR code for the last page.
5. **Make** it, then click “Open presentation” — full screen with music, ready to present.

Presentations are saved to Documents/Wander Decks. To add photos later, put them in a topic folder inside the presentation folder and double-click “Update Presentation.command”.

## Style packs

A style pack is a folder (or a packed `.wdstyle` file) that sets colors, fonts, background and the animated intro.
Import and export them in Settings → Style packs. To make your own, see [docs/style-pack.md](docs/style-pack.md).

## With an AI agent

Wander Deck can also be driven by an AI assistant for deeper customization (e.g. turning your own illustration into an animated intro):
link `skills/wander-deck` into `~/.claude/skills/` for Claude Code, or ask any agent to read [AGENTS.md](AGENTS.md) first.

## Development

`app/` is the SwiftUI app plus the `wander` CLI (Swift package); `engine/` is the presentation itself (`deck.html`, the Python builder `build.py`, launchers); `styles/` holds the built-in packs.

```bash
scripts/test.sh              # all tests
scripts/package_app.sh       # build dist/Wander-Deck-<version>-AppleSilicon.zip and -Intel.zip
scripts/install.sh --local dist/Wander-Deck-<version>-AppleSilicon.zip
```

Needs Xcode 16+ (Swift 6). The Python `engine/build.py` and the Swift `DeckBuilder` must produce the same output; the tests compare them.

## License

Code: [MIT](LICENSE). Built-in style packs: CC BY 4.0 (sources in each pack's `CREDITS.md`).
Bundles [Pi](https://github.com/earendil-works/pi) (MIT). Your presentations, photos and assets are yours.
