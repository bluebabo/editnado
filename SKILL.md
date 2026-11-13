---
name: editnado
description: Editnado = edit + tornado (and "nado" is Korean for "me too"). AI-driven automatic video editing on Windows with free ArtCraft apps (FilmCraft, EffectCraft, LightCraft) plus ffmpeg and whisper.cpp. Give a folder of photos and videos, an optional voice memo of how the day felt, and a style; the skill installs what is missing, drafts the edit by itself (scene order, Korean captions from the user's own voice, title intro, background music that ducks under speech, color look) and lets the user revise by chat. Free templates included and more can be installed. Use when the user wants to edit a video, make YouTube Shorts, Reels or a travel/daily vlog, add subtitles, narration or background music, or asks to find a video editing skill. 한국어 — 영상 편집, 쇼츠·릴스·브이로그 만들기, 여행 사진 영상, 자막·내레이션·배경음악 넣기, 영상 템플릿.
license: MIT
compatibility: Windows 10/11 with PowerShell 5.1. On first use `vc.cmd setup` installs FilmCraft/EffectCraft (ArtCraft, MIT/Apache-2.0), ffmpeg and whisper.cpp without admin rights after asking the user. Internet is needed only for setup and template downloads.
metadata:
  author: editnado
  version: "2.3.0"
---

# Editnado — 사진·영상·소감으로 자동 편집

**Edit? 나도! — 말 한마디에 편집 회오리.** (Say a word, and an editing tornado hits.)

사용자는 **사진·영상 폴더 + 그날의 소감(음성 메모) + 원하는 스타일**만 말하고, 채팅으로 고치며 결과를 본다. 계산·굽기·받아쓰기는 PC 의 도구가 하고(토큰 0), AI 는 품질을 가르는 판단(장면과 말 맞추기, 받아쓰기 고치기, 확인 그림 보기)에 집중한다.

실행기는 이 폴더의 `vc.cmd` 하나다 (`doctor · setup · auto · build · transcribe · sheet · stills · template`). PowerShell 에서 `& "<이 폴더>\vc.cmd" auto …` 로 부른다 (Git Bash 의 `cmd //c` 는 안 된다).

## 0. AI 가 지킬 것

1. **품질이 먼저, 토큰은 그다음.** 판단에 필요한 것은 본다 — `auto` 결과 JSON 한 줄, 장면 모음(`sheet_1.png`), 확인 그림. 계산·반복은 PC 에 맡기고, 실행기 소스·명령 목록·폴더 전체 나열은 읽지 않는다 (목록은 `media.json`). 원본 사진·영상은 장면 모음으로 모자랄 때만 연다
2. **설치는 묻고 한다.** 처음이면 `vc.cmd setup` → 나온 표(무엇을·몇 MB)를 사용자에게 보여 주고 허락을 받은 뒤 `vc.cmd setup -Yes`. 관리자 권한은 쓰지 않는다
3. **원본은 읽기만.** 결과는 `<폴더>\완성\` (또는 `-Out` 으로 정한 폴더)에만 쓴다
4. **지어내지 않는다.** 제목·자막·블로그 문구는 소감·사진·찍은 시각에 있는 것만. 장소의 가격·운영 시간 같은 정보는 사용자가 준 것만
5. **확인 그림을 보고 나서** 「완성」이라고 말한다. 자막이 잘리거나 화면이 비면 계획서를 고쳐 다시 굽는다
6. **쉬운 말.** 사용자에게는 쉬운 한국어 한두 줄로 말하고, 명령·경로·영어는 필요할 때만 보인다
7. 계정·API 키·유료 크레딧이 드는 기능은 쓰지 않는다. 사진 위치 같은 개인 자료를 인터넷 서비스로 보낼 때는 그때마다 허락을 받는다

## 1. 흐름

```
① 준비   vc.cmd doctor                    → FilmCraft·받아쓰기 도구가 없으면 0-2 대로 setup
② 초안   vc.cmd auto <폴더> -Template <id> [-Title "제목"] [-Out <결과 폴더>] [-Bgm <음악 파일>]
         → 결과 폴더(기본 <폴더>\완성\)에 plan.json · 미리보기 mp4(절반 크기) · 확인 그림 · sheet_1.png(장면 모음) · 마지막 줄 JSON
            {"plan","output","check","seconds_total","scenes":[{n,file,kind,taken,sentence,seconds}],
             "sentences":[{k,at,text}],"warnings":[…]}
③ 다듬기  품질은 여기서 갈린다 — 사용자에게 보이기 전에 셋을 본다
         a. 장면 ↔ 말: sheet_1.png 와 sentences 를 보고 장면마다 그 문장 내용과 맞는지. 틀리면 plan.json 의
            "align"(장면마다 보여 줄 문장 번호, 커지는 순서)만 고친다 — 초 계산·영상 구간은 build 가 한다
         b. 받아쓰기: 오탈자·고유명사(「헤드는→해 뜨는」)가 있으면 <결과 폴더>\<녹음이름>.srt 의 글만 고쳐
            "captions": {"srt": 그 파일} (시각은 그대로 — build 가 인트로만큼 민다)
         c. warnings: 「인트로 제목이 N줄」이면 title 을 짧게
         고쳤으면 vc.cmd build <plan.json> -Preview
④ 보이기  확인 그림(장면마다 한 칸)을 보고, 사용자에게 「32초 · 장면 9개 · 첫 자막 "…" · 미리보기: <경로>」
⑤ 고치기  사용자 말 → plan.json 에서 그 값만 고치고 vc.cmd build <plan.json> -Preview
⑥ 확정   vc.cmd build <plan.json>          → 원본 화질 mp4 + .srt
```

- `auto` 가 하는 일: 찍은 시각 순서 · 영상은 가운데 구간 · 이름에 「소감·memo·녹음·voice」가 든 소리 파일을 내 목소리 내레이션으로 받아써 자막(어미·조사 뒤에서 2줄로 끊음) · 말한 문장마다 장면을 맞춤(기본 = 찍은 시각이 가까운 장면끼리 한 문장, 문장 사이 쉼에서 장면 바꿈) · 영상 현장음은 살리고 말할 때 줄임 · 이름에 「bgm·music·음악」이 든 파일(또는 `-Bgm`)을 배경음악으로(말할 때 자동으로 작아짐) · 템플릿의 인트로·색감·자막 모양
- 묻는 것은 한 번에 하나. 폴더만 알면 나머지는 템플릿 기본값으로 정한다

## 2. 템플릿 고르기

| 사용자 말 | `-Template` |
|---|---|
| 기본·브이로그·여행·가로·유튜브 | `default` |
| 쇼츠·릴스·틱톡·세로·빠르게 | `shorts_fast` |
| 잔잔하게·감성·여유 | `calm_mood` |
| 맛집·먹방·음식·카페 | `food_quick` |
| 가족·부모님·큰 글씨·앨범 | `family_big` |
| 강의·리뷰·시연·설명 | `tech_tutorial` |

- 모르면 `default`, 세로라고만 하면 `shorts_fast`. 각 템플릿의 `meta.words` 가 부르는 낱말이다
- 설치된 것과 받을 수 있는 것: `vc.cmd template list` · 설치: `vc.cmd template install <id 또는 zip>` — 고르는 것은 사용자
- **스킬 새 판** (「스킬 업데이트해」): `vc.cmd update` → 바뀌는 것을 사용자에게 보여 주고 허락 → `vc.cmd update -Yes`. 깃으로 받은 폴더는 `git pull`(이 폴더에서 고친 파일이 있으면 멈춤), zip 으로 받은 폴더는 최신 릴리스를 SHA256 확인 뒤 덮는다. 개인 취향 `profiles/local`·설치한 템플릿은 그대로, 바뀌는 파일은 백업
- 템플릿 형식·만드는 법: `templates/README.md`

## 3. 자주 받는 고침 → plan.json

| 사용자 말 | 고칠 곳 (`overrides` 는 점 경로 키) |
|---|---|
| 자막 조금 위로 / 아래로 | `overrides."subtitles.margin"` ± 0.04 |
| 자막 크게 / 작게 | `overrides."subtitles.size"` (기본 약 64) |
| 음악 작게 / 크게 | `overrides."audio.bgm_duck_db"` −3 / +3 |
| 이 장면 빼 / 순서 바꿔 | `timeline` 배열에서 빼기·옮기기 (`align` 도 같은 자리를 빼기·옮기기) |
| 장면이 말과 안 맞아 | `align` — 장면마다 문장 번호 (예: `[1,2,2,3,3,4,4,5]`) |
| 마지막 장면 더 길게 / 짧게 | `tail_seconds` ± 3 (말이 끝난 뒤 여운, 기본 1초) |
| 가운데 장면 더 길게 | `align` 이 있으면 그 장면에 문장을 하나 더 준다 (말과 화면이 어긋나지 않게 초로 늘리지 않는다). 없으면 그 항목 `seconds` + 3 |
| 사진 일부만 / 이물 잘라 | 그 항목 `crop`: [왼쪽, 위, 너비, 높이] 비율 0~1 (오른쪽 20% 버리기 = `[0,0,0.8,1]`) — 원본은 그대로 |
| 색 빼 줘 | `overrides."video.color_preset": null` |
| 인트로 빼 줘 | `overrides."intro": null` |
| 제목 바꿔 | `title` |

- 「이번만」 = 위처럼 `overrides`. 「앞으로 계속」 = `profiles/local/<템플릿id>.json` 에 같은 키를 적는다 (공개 파일은 고치지 않는다)
- 없는 키는 실행기가 「프로필에 없는 키(오타?)」로 멈춘다 — 키 목록은 `references/preset-guide.md`

## 4. 소감 쓰는 법

| 쓰임 | 방법 |
|---|---|
| 내 목소리 내레이션 | 폴더의 음성 메모를 `auto` 가 알아서 받아써 자막. 고유명사가 틀리면 `<폴더>\완성\<녹음이름>.srt` 를 고쳐 계획서 `captions.srt` 로 |
| 기계 음성 내레이션 | 글로 받은 소감 → 계획서 `"narration": {"mode":"tts","lines":[{"text":"…"}]}` (Windows 한국어 음성) |
| 제목·자막 문구 | 소감을 짧게 다듬는다. 한 줄 = 템플릿 `subtitles.max_chars` 안 |
| 블로그 글 | 아래 6 |

**말투 고르기:** 템플릿 `text.tone`(제목·기계 음성 문장)과 `blog.tone`(블로그)이 기본이다 — `습니다` · `해요` · `반말`. 사용자가 말투를 말하면 이번만은 `overrides."text.tone"`, 앞으로면 `profiles/local/<id>.json` 에 적고 그 말투로 문장을 다시 쓴다. 사용자 목소리 자막은 말한 그대로 둔다 (소리와 어긋나지 않게).

## 5. 사진·썸네일

- 사진 보정 (선택): `lightcraft-cli render <사진> -o <결과폴더>\_vc_work\photo\<이름>.jpg --set color.vibrance=8 --size 1920` (값 = 템플릿 `photo.*`), 계획서의 그 사진 경로를 보정본으로
- 썸네일: 확정 프로젝트에서 인트로가 보이는 시각 한 장 — `filmcraft-cli --project <_vc_work 의 .fcproj> render --seconds 1.5 --out thumb.png`
- 얼굴 가리기 (선택): `deface.cmd <사진·영상> -o <결과>` — 사람 얼굴을 실제로 찾는지는 사람이 나온 자료로 확인 후 쓴다

## 6. 블로그 초안

`<결과 폴더>\blog\draft.md` 에 쓴다: 템플릿 `blog.*` 규칙(말투·소제목·사진 묶음) + 4번 사실 규칙. 사진은 보정본, 순서는 찍은 시각. 영상에서 한 컷씩 넣으려면 `vc.cmd stills <plan.json>` → `<결과 폴더>\stills\` 에 영상마다 실제로 쓰인 구간 가운데 한 장(원본 화질). 사용자의 블로그 전용 스킬(`blog-writer` 등)이 있으면 그 스킬에 넘긴다.

## 7. 참고 문서 (필요할 때만 연다)

- `references/edit-plan.md` — 계획서 형식 · `references/preset-guide.md` — 모든 키
- `references/filmcraft-commands.md` — 확인된 FilmCraft 명령과 함정 (실행기를 고칠 때만)
- `references/cli-recipes.md` — 사진·썸네일·열린 도구 명령 · `references/toolchain.md` — 도구 출처·라이선스·MCP
- `references/onboarding.md` — 새 PC · `references/style-extractor.md` — 레퍼런스 영상에서 스타일 따기
- `templates/README.md` — 템플릿 형식·판매 규칙

### 개정 이력
- 2026-11-12: 최초 작성 → 같은 날 대화형 계획서 + 실행기 `vc.ps1`
- 2026-11-13: 2.0 — 자동 초안 `auto`, 설치 `setup`, 템플릿 6종(인트로·색감), 받아쓰기 `transcribe`, 자막 고르게 나누기, 현장음 덕킹, 말투 고르기, 공개 표준(agentskills.io) 앞머리
- 2026-11-13: 2.3 — 이름 Editnado (옛 video-craft): 폴더·저장소·릴리스 zip 이름, 소개 문구 「Edit? 나도!」
- 2026-11-13: 2.2 — 스킬 새 판 받기 `vc.cmd update`(깃·릴리스 zip·직접 받은 zip), 릴리스 절차(`release.ps1`, 관리자용)
- 2026-11-13: 2.1 — 품질 우선 원칙, 장면을 말한 문장에 맞추기(`align`·`tail_seconds`), 자막을 어미·조사 뒤에서 끊기, 사진 자르기(`crop`), 블로그용 한 컷(`stills`), auto 미리보기 절반 크기·현장음 살리기·제목 넘침 경고
