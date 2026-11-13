# 🌪️ Editnado — AI video editing skill (Shorts · Reels · Vlogs)

### Edit? 나도! — 말 한마디에 편집 회오리
### Say a word, and an editing tornado hits. Edit? *Nado!* — Korean for "me too."

> 편집 프로그램 앞에서 얼어붙던 사람도 이제 말할 수 있습니다. **"에딧? 나도!"** 사진·영상을 던지고 그날 소감을 한마디 하면, **에디네이도**(Edit + Tornado)가 휘몰아쳐 장면·자막·음악을 한 번에 정리합니다. 바람이 지나간 자리엔 쇼츠 한 편.
>
> Say a word and an editing tornado whips through your photos — cuts, captions, music, done. And the name? *Nado* is Korean for "me too": **Edit? Nado!** — even if you've never edited a thing.

*읽는 법 둘, 뜻도 둘 — 에딧-나도(나도 편집) · 에디-네이도(편집 토네이도). 어느 쪽으로 읽어도 맞습니다.*

**Give your AI agent a folder of photos and videos, plus a voice memo of how the day felt. It installs what it needs and makes the video.**
**사진·영상 폴더와 그날 소감(음성 메모)만 주면, AI 에이전트가 필요한 프로그램을 깔고 영상을 만들어 줍니다.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/Windows-10%20%7C%2011-brightgreen.svg)
![Agent Skills](https://img.shields.io/badge/Agent%20Skills-SKILL.md-orange.svg)

An [Agent Skill](https://agentskills.io) for **Google Antigravity, OpenAI Codex, Claude Code** and other agents that read `SKILL.md`. Editing runs on your PC with free tools — [ArtCraft](https://getartcraft.com) FilmCraft · EffectCraft (MIT/Apache-2.0), ffmpeg, whisper.cpp. No paid API or credits.

---

## What it does

| | |
|---|---|
| 📂 **One folder in, one video out** | `vc.cmd auto <folder>` orders scenes by capture time, trims each clip to its middle, fits photo lengths to the narration, and renders a preview |
| 🎙️ **Your voice becomes captions** | A voice memo in the folder (`소감…`, `memo…`) is transcribed by whisper.cpp and burned in as Korean captions, broken into two-line pieces at natural Korean break points (after endings and particles) |
| 🎯 **Scenes follow what you say** | Each spoken sentence gets its scenes; cuts land in the pauses between sentences. The agent checks the match on a contact sheet and fixes it with one list of numbers (`align`) |
| 🎵 **Music that steps aside** | A `bgm…` file becomes background music that automatically drops when you speak (ducking) and fades out at the end; clip sound is kept and lowered under your voice; loudness set to −14 LUFS |
| 🎨 **Templates** | 6 free templates: title intro (EffectCraft graphics template with your title and date), color look, caption style, pacing. More can be installed from a template index |
| 💬 **Fix it by chatting** | "Captions a bit higher", "drop scene 3", "music quieter" → one line in `plan.json`, re-render |
| 🖥️ **Quality first, the PC does the work** | Rendering, transcription and timing run on your PC with free tools; the agent spends its effort on judgment (scene–speech match, transcript fixes, checking the result image) and never reads the source code or command lists |

## For AI agents · AI 에이전트라면

1. Put this folder where your agent loads skills: `.claude/skills/editnado/` (Claude Code — tested) · `.agents/skills/editnado/` (Antigravity — location from its docs; this skill not yet tested there) · Codex: location not confirmed yet
2. Read [`SKILL.md`](SKILL.md) and follow it
3. `vc.cmd doctor` → if tools are missing, run `vc.cmd setup`, **show the table (what, how many MB) to the user, ask**, then `vc.cmd setup -Yes`
4. `vc.cmd auto "<photo/video folder>" -Template shorts_fast` → read the last JSON line and the `_check.png` image → tell the user in one or two plain sentences
5. Apply the user's changes to `plan.json` → `vc.cmd build "<plan.json>"`

## For people · 사람이라면

Tell your agent (tested with Claude Code; Antigravity has a free tier but has not been tested with this skill yet):
> *"깃허브에서 editnado 스킬 찾아서 써 줘. D:\여행\1108 폴더로 쇼츠 만들어 줘. 소감은 폴더에 녹음해 뒀어."*
> *"Find the editnado skill on GitHub and make a Short from D:\Trips\1108. My voice memo is in the folder."*

## Update · 새 판 받기

Tell your agent *"스킬 업데이트해" / "update the editnado skill"*, or run:

```bat
vc.cmd update        :: shows what is new (nothing changes yet)
vc.cmd update -Yes   :: installs it
```

- Installed with `git clone` → `git pull` (stops if you edited files in the skill folder)
- Installed from a zip → downloads the latest GitHub Release zip, checks its SHA256, overlays it (`vc.cmd update -Zip <file> -Yes` for a zip you downloaded yourself)
- Your own settings (`profiles/local/`) and installed templates are kept; replaced files are backed up

## Templates · 템플릿

| id | 이름 | Screen | Look |
|---|---|---|---|
| `default` | 여행 브이로그 (가로) | 16:9 | title-card intro · warm color · white captions |
| `shorts_fast` | 빠른 쇼츠 | 9:16 | story intro · quick cuts · yellow captions |
| `calm_mood` | 잔잔한 감성 | 9:16 | slow zoom · faded film color · long dissolves |
| `food_quick` | 맛집·먹방 | 9:16 | vivid color · very quick cuts · large captions |
| `family_big` | 가족 기록 (큰 글씨) | 16:9 | large captions for older viewers · slow · golden color |
| `tech_tutorial` | 강의·리뷰 | 16:9 60fps | original color · no transitions · monospace captions |

Previews: `templates/<id>/preview.png` · format and selling rules: [`templates/README.md`](templates/README.md)

## Measured · 실측 (2026-11-13, laptop with AMD Radeon integrated graphics)

| Task | Result |
|---|---|
| `auto` — 8 photos/clips + 29 s voice memo + BGM → 9:16 Short (half-size preview) with intro and captions | 31.6 s video · 84 s the first time (transcription included) · 42 s when re-run |
| Re-render after the agent's fixes (`build -Preview`) · final 1080×1920 (`build`) | 33 s · 62 s for a 34.6 s video |
| Transcription, whisper.cpp large-v3-turbo q5 on CPU (setup default) | 29 s memo in 35 s, Korean text exact |
| Transcription, small q5 model (`setup -Quality normal`) | frequent Korean mistakes (「해 뜨는」→「헤드는」) — the agent should correct the text before rendering |
| Clean-PC run (tools installed by `setup` into an empty folder, no other tools) | `auto` finished end to end |
| Final render 1080×1920 30 fps, 11 s video | 17.8 s |
| EffectCraft intro (1080×1920, 8 s) with Korean title | 10.5 s |
| `setup` downloads (verified by SHA256 / signature) | FilmCraft 109 MB · EffectCraft 82 MB · ffmpeg 110 MB · whisper.cpp 21 MB · model 547 MB (large-v3-turbo, default) or 181 MB (small) · optional `-Photo` LightCraft 118 MB + PhotoCraft 137 MB |

## Limits · 한계 (honest)

- Windows only (PowerShell 5.1). macOS/Linux not yet
- FilmCraft's command-line build has no speech-to-text, so captions use whisper.cpp; transcription is CPU-bound
- Audio ducking and loudness are set by FilmCraft commands that succeed; levels have not been checked by ear or meter
- Face blurring (`deface`) runs, but detection on footage with people is not yet verified; license plates are not covered
- Background music is not bundled — use your own or license-checked free music (see `references/toolchain.md`)

## Files

```
SKILL.md            instructions for agents (agentskills.io format)
vc.cmd · vc.ps1     editor: doctor · auto · build · transcribe · sheet
vc_setup.ps1        setup (verified downloads) · template list / install
vc_paths.ps1        where tools live
templates/          6 free templates + index format
profiles/_base.json all default values · profiles/local/ = your own (not in git)
references/         plan format · verified FilmCraft commands · recipes · tool sources
llms.txt · AGENTS.md  short summaries for AI readers
```

**Keywords:** AI video editing, automatic video editor, YouTube Shorts maker, Reels, TikTok, travel vlog, Korean subtitles, whisper captions, voice memo narration, background music ducking, video templates, agent skill, SKILL.md, Antigravity, Codex, Claude Code, Windows, FilmCraft, ArtCraft, ffmpeg · 영상 편집 자동화, 쇼츠 만들기, 릴스, 브이로그, 자막 자동, 내레이션, 배경음악, 영상 템플릿

License: MIT. Bundled intro graphics are exported from EffectCraft built-in templates — EffectCraft, Copyright (c) 2026 ArtCraft Team and the EffectCraft contributors, MIT or Apache-2.0 (your choice). The ArtCraft name and logos are trademarks of the ArtCraft Team.
