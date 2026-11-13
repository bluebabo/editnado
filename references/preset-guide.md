# 값(키) 안내 — 템플릿·개인 취향·이번만

## 1. 병합 순서

1. `profiles/_base.json` — 모든 키의 기본값
2. `templates/<id>/template.json` — 템플릿 (바꿀 값만. `id`·`meta` 는 표시용)
3. `profiles/local/<id>.json` — 개인 취향 (깃에 안 올라감)
4. 계획서 `overrides` — 이번 한 번만, 점 경로 키 (`"subtitles.color": "#FFFF00"`)

객체는 키별로 덮고, 배열·값은 통째로 덮는다. `overrides` 는 `_base.json` 에 있는 키만 받는다 — 없는 키는 「프로필에 없는 키(오타?)」로 멈춘다.

## 2. 키

| 키 | 뜻 · 단위 | 기본 |
|---|---|---|
| `video.width` · `height` · `fps` | 시퀀스 크기·프레임 | 1920 · 1080 · 30 |
| `video.export_preset` | FilmCraft 내보내기 프리셋 이름 | `YouTube 1080p Full HD` |
| `video.max_seconds` | 전체 길이 한도 (auto 는 넘으면 줄임, build 는 경고) | 3600 |
| `video.photo_seconds` · `photo_zoom` | 사진 길이(초) · 확대 [시작배, 끝배] | 3.0 · [1.0, 1.1] |
| `video.clip_seconds` | auto 에서 영상 한 개에 쓸 길이 | 4.0 |
| `video.transition` · `transition_seconds` | `cross_dissolve` 또는 `none` · 전환 길이 | 0.3 |
| `video.color_preset` | FilmCraft 색보정 프리셋 이름 (아래 4) 또는 null | null |
| `subtitles.enabled` | 자막 굽기 | true |
| `subtitles.font` · `font_style` · `size` | 글꼴 · 굵기 · 크기(null = 앱 기본, 약 64). 없는 글꼴은 맑은 고딕으로 바뀌고 경고 | Malgun Gothic · Bold · null |
| `subtitles.color` · `outline` · `outline_color` · `background` | 글자색 · 외곽선 두께 · 외곽선 색 · 뒤 상자 | #FFFFFF · 2 · #000000 · false |
| `subtitles.anchor` · `margin` | `bottom`/`top` · 가장자리에서 화면 높이 비율 (쇼츠는 0.22 — 화면 아래 제목·채널명 위) | bottom · 0.10 |
| `subtitles.max_chars` · `lines` · `min_seconds` · `max_seconds` | 자막 한 줄 글자 수(화면 줄바꿈 폭에 맞춤: 9:16 은 11) · 줄 수 · 최소·최대 표시 초. 받아쓴 자막을 이 한도로 고르게 나눈다 | 18 · 2 · 1.2 · 3.5 |
| `title.*` | 인트로가 없을 때 화면 위 제목: 글꼴·크기(px)·세로 위치(화면 높이 비율)·색·보이는 초 | 96px · 0.15 · 2.5초 |
| `intro` | EffectCraft 인트로 `{"template":"intro.ectemplate","wrap":5,"start":0,"seconds":3,"values":{"Title":"{title}"}}` 또는 null. `wrap` = 제목 한 줄 최대 글자(띄어쓰기에서 줄바꿈 — 세로 스토리는 5, 가로 제목 카드는 12) | null |
| `audio.loudness_lufs` | 내보낼 때 맞출 음량 | -14 |
| `audio.clip_audio` | 영상 소리 기본 종류 `ambience`/`dialogue` | ambience |
| `audio.clip_duck_db` | 내레이션 때 영상 현장음을 줄이는 양 (dB) | -12 |
| `audio.bgm` | 템플릿에 든 배경음악 파일 (템플릿 폴더 기준) 또는 null | null |
| `audio.bgm_duck_db` | 말소리 때 배경음악을 줄이는 양. −16.5 ≈ 15%, −13 ≈ 22%, −22 ≈ 8% (= 20·log10 비율) | -16.5 |
| `audio.bgm_fade_out_seconds` | 배경음악 끝 서서히 줄이기 | 2.0 |
| `narration.start_seconds` · `gap_seconds` | 기계 음성 첫 줄 시작 · 줄 사이 쉼 | 0.5 · 0.4 |
| `transcribe.model` · `language` | whisper.cpp 모델 파일 이름 또는 `auto`(large-v3-turbo → small → base 순으로 있는 것) · `auto`/`ko` | auto · auto |
| `photo.long_edge` · `quality` · `set` | LightCraft 사진 보정: 긴 변 px · JPEG 품질 · `--set` 조절값 | 1920 · 90 · vibrance 8, contrast 5 |
| `text.tone` | 제목·기계 음성 문장 말투 `습니다`/`해요`/`반말` (AI 가 읽음) | 해요 |
| `blog.tone` · `headings` · `photos` · `facts` | 블로그 초안 규칙 (AI 가 읽음) | 해요 · … |

## 3. 개인 취향 저장 · 새 템플릿

- 「앞으로 자막 조금 위로」 → `profiles/local/<템플릿id>.json` 에 `{"subtitles": {"margin": 0.26}}` 처럼 그 키만
- 새 템플릿 → `templates/<새id>/template.json` (형식은 `templates/README.md`). 기존 템플릿 하나를 복사해 바꿀 값만 남긴다

## 4. FilmCraft 색보정 프리셋 (`video.color_preset`)

Cinematic: Teal Shadows, Warm Skin · Night Exterior · Golden Dusk · Steel Blue · Hard Sun
Film Emulation: Faded Print · Silver Retention · Cross Processed · Warm Negative
Monochrome: Neutral Mono · Hard Mono · Sepia Tone · Cold Mono
Technical: Lift Shadows · Protect Highlights · Half Saturation · Boost Vibrance · Legal Range Squeeze
(목록: `filmcraft-cli --demo exec lumetri.presets`, FilmCraft 0.20.1)
