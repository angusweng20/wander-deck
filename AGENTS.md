# AGENTS.md

This repo is **Wander Deck（漫遊簡報）**, a macOS tool that turns a folder of photos into a
non-linear, offline HTML presentation. You (the AI agent) operate it on the user's behalf.

**Read [`skills/wander-deck/SKILL.md`](skills/wander-deck/SKILL.md) before doing anything** — it has the workflow,
the commands, the `deck.json` recipes, and the pitfalls we already hit. Settings reference: [`docs/deck-json.md`](docs/deck-json.md).

In that guide, `$WD` means the root of this repository.

## Working on the engine itself

- `engine/deck.html` is copied into every deck as `簡報.html`; `engine/build.py` as `_wander/build.py`.
  Existing decks pick up changes with `scripts/new_deck.sh --upgrade <deck>`.
- build.py must stay dependency-free: Python standard library + macOS `sips` (+ optional `ffmpeg`).
- Verify UI changes with `scripts/preview.sh` screenshots at 1920x1080 and 1440x900 before reporting done.
- Never commit anyone's photos, music or brand assets. Demo content must be license-clear.
