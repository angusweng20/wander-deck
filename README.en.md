# Wander Deck 漫遊簡報

**Turn a folder of photos into a presentation you can wander through — not page by page.**

A home screen shows your topics as photo stacks. Jump to whichever one the conversation leads to,
click a photo to zoom in, hover with a magnifier for details. Made for travel talks, brand stories,
portfolios and event recaps. macOS only.

## Features

- 📁 One folder = one topic. Drop in HEIC / JPG / MOV as-is.
- 🔀 Non-linear: a few linear intro slides, then free navigation.
- 🔍 Click-to-zoom with a scroll-adjustable magnifier.
- 🖼️ Showcase walls for topics with just a few photos.
- 🎵 Looping background music that survives page changes, with play/pause and volume.
- 🎞️ Animated intro: swinging lanterns, walking camels, leaves in the breeze, a title that waves like a flag.
- 📱 QR-code outro page for your Instagram or website.
- 🔒 Generated images are auto-rotated and stripped of GPS / EXIF. Originals are never touched.
- ✈️ Fully offline: copy the folder, double-click, done.

## Built for your AI assistant

Wander Deck is designed to be **operated by an AI agent**. You describe what you want;
the agent follows [`skills/wander-deck/SKILL.md`](skills/wander-deck/SKILL.md).

**Claude Code**
```bash
git clone https://github.com/angusweng20/wander-deck.git ~/wander-deck
mkdir -p ~/.claude/skills && ln -s ~/wander-deck/skills/wander-deck ~/.claude/skills/wander-deck
```
Then: "Use Wander Deck to turn ~/Pictures/Kyoto into a talk deck."

**Other agents** (Codex, Cursor, …): "Read wander-deck/AGENTS.md, then build me a Wander Deck."

The operating guide is written in Traditional Chinese; modern agents read it fine.
Interface text can be switched to English with the `text` field in `deck.json`.

## Requirements

macOS (uses the built-in `sips`), Google Chrome for fullscreen + music autoplay.
Optional: `ffmpeg` for video posters; OpenCV (installed by the agent into `~/.wander-deck`) for animated intros.

## License

Code: [MIT](LICENSE). Your decks, photos and assets are yours.
