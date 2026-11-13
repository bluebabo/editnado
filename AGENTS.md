# AGENTS.md

This repository is an **Agent Skill** for automatic video editing (Shorts, Reels, vlogs) on Windows.

- To use it, place this folder where your agent loads skills — `.claude/skills/editnado/` (Claude Code, tested) or `.agents/skills/editnado/` (Antigravity per its docs, not yet tested with this skill) — and follow [`SKILL.md`](SKILL.md).
- Ask the user before installing anything: run `vc.cmd setup`, show the table, then `vc.cmd setup -Yes`.
- Quality first, then tokens: run `vc.cmd auto` first; judge from its last JSON line, the contact sheet `sheet_1.png` and the `_check.png` image (scene ↔ sentence match, transcript typos, title fit). Let the PC do rendering and timing. Do not read `vc.ps1`; open original media only when the contact sheet is not enough.
- Never modify the user's original files; write only under `<folder>\완성\` or the `-Out` folder.

To change the editor itself: read [`references/filmcraft-commands.md`](references/filmcraft-commands.md) first (verified commands and Windows PowerShell 5.1 pitfalls), test with real FilmCraft runs, and keep `README.md` measurements honest.
