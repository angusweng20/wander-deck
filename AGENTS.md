# AGENTS.md

This repo is **Wander Deck（漫遊簡報）**, a macOS tool that turns a folder of photos into a
non-linear, offline HTML presentation. It ships two ways:

- a **Mac app** (`app/`, SwiftUI) for people: pick photos → group → details → make;
- an **AI-operated toolkit** (`engine/`, `scripts/`, `skills/`) for agents doing custom work.

When operating it for a user, **read [`skills/wander-deck/SKILL.md`](skills/wander-deck/SKILL.md) first** — workflow,
commands, `deck.json` recipes, pitfalls. Settings: [`docs/deck-json.md`](docs/deck-json.md).
Style packs: [`docs/style-pack.md`](docs/style-pack.md). In those guides `$WD` means the root of this repository.

## Working on the code

- `engine/deck.html` is copied into every deck as its `.html`; `engine/build.py` as `_wander/build.py`.
  Existing decks pick up changes with `scripts/new_deck.sh --upgrade <deck>`.
- build.py must stay dependency-free: Python standard library + macOS `sips` (+ optional `ffmpeg`).
- **Two builders, one output.** `app/Sources/WanderCore/DeckBuilder.swift` is the Swift port of `build.py`
  (the app can't assume Python exists). Change both together; `DeckTests.testMakeDeckEndToEnd` compares them.
- Styles live in `styles/<id>/` (`wander-style/1`). Validate with `python3 scripts/style_pack.py check <dir>`;
  the Swift validator in `StylePacks.swift` must apply the same rules.
- Run `scripts/test.sh` before reporting done. UI changes to the deck: also check `scripts/preview.sh` screenshots
  at 1920x1080 and 1440x900. App UI: run the debug app with `WANDER_SNAPSHOT_DIR=<dir>` (it writes its own window
  as PNG every 2 s; `WANDER_DEMO=<photo folder>` + `WANDER_DEMO_STEP=sort|theme|make` jumps to a step).
- Build with `--scratch-path "$TMPDIR/wanderdeck-build"` (the scripts already do): if the repo sits in an iCloud-synced
  folder, File Provider xattrs break code signing and sync huge build folders.
- Package with `scripts/package_app.sh` (ad-hoc signed — the project deliberately has no Apple Developer account).
  Publishing a release / pushing is the owner's call; never do it unasked.
- AI calls go through Pi (`pi --mode rpc`, provider `openai-codex`, model `gpt-5.5` — ChatGPT-subscription logins
  can't use the mini models). Send only `ImageTools.aiThumbnail` output (downscaled, metadata-free), never originals.
- Never commit anyone's photos, music or brand assets. Demo content must be license-clear (see each `CREDITS.md`).
