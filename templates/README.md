# Templates · 템플릿

A template is one folder. The editor (`vc.cmd`) reads `template.json`; the AI only fills in values (title text, captions).
템플릿 = 폴더 하나. 실행기가 `template.json` 을 읽고, AI 는 값(제목·자막 글)만 채운다.

## Built-in free templates · 기본 무료 템플릿

| id | 이름 | 화면 | 특징 |
|---|---|---|---|
| `default` | 여행 브이로그 (가로) | 16:9 | 제목 카드 인트로 · Warm Negative 색감 · 흰 자막 |
| `shorts_fast` | 빠른 쇼츠 | 9:16 | 세로 스토리 인트로 · 짧은 컷 · 노란 자막 (한 줄 11자) |
| `calm_mood` | 잔잔한 감성 | 9:16 | 느린 확대 · Faded Print 색감 · 긴 전환 · 작은 자막 |
| `food_quick` | 맛집·먹방 | 9:16 | Boost Vibrance 색감 · 아주 빠른 컷 · 큰 자막 |
| `family_big` | 가족 기록 (큰 글씨) | 16:9 | 큰 자막(80) · 느린 전개 · Golden Dusk 색감 · 「~습니다」 말투 |
| `tech_tutorial` | 강의·리뷰 | 16:9 60fps | 원본 색 · 전환 없음 · 고정폭 글꼴 |

## Folder · 폴더

```
templates/<id>/
├── template.json      # 필수 — 메타 정보 + 프로필 값
├── intro.ectemplate   # 선택 — EffectCraft 그래픽 템플릿 (글자 칸에 제목·날짜를 넣어 인트로 영상으로 렌더)
├── preview.png        # 선택 — 미리보기 그림 (갤러리·목록용)
└── (bgm·LUT·글꼴 파일) # 선택 — 직접 만들었거나 재배포가 허락된 것만
```

## template.json

```json
{
  "id": "calm_mood",
  "meta": {
    "name": "Calm Mood", "name_ko": "잔잔한 감성",
    "description": "한 줄 설명", "words": ["잔잔하게", "감성"],
    "author": "editnado", "version": "1.0.0", "license": "MIT",
    "price": "free", "aspect": "9:16", "preview": "preview.png",
    "credits": "포함된 남의 자료와 그 라이선스"
  },
  "video":     { "...": "profiles/_base.json 의 같은 절에서 바꿀 값만" },
  "subtitles": { }, "title": { }, "audio": { }, "narration": { }, "photo": { },
  "intro": {
    "template": "intro.ectemplate", "wrap": 5, "start": 0, "seconds": 3.0,
    "values": { "Headline": "{title}", "Call to Action": "{date}" }
  },
  "text": { "tone": "해요" },
  "blog": { "tone": "해요", "headings": "…", "photos": "…" }
}
```

- 값 병합: `profiles/_base.json` → 이 파일 → `profiles/local/<id>.json`(개인 취향) → 계획서 `overrides`
- `intro.values` 의 키는 그 `.ectemplate` 의 글자 칸 이름(`effectcraft-cli exec essential.templateInfo` 로 확인). `{title}`·`{date}` 는 계획서 값으로 바뀐다
- `video.color_preset` = FilmCraft 색보정 프리셋 이름 (`filmcraft-cli --demo exec lumetri.presets`)
- `text.tone` = 제목·기계 음성 문장 말투, `blog.*` = 블로그 초안 규칙 — AI 가 읽는다
- `meta.price` = `"free"` 또는 `{"amount": 3900, "currency": "KRW"}`

## Rules for sellers · 판매용 템플릿 규칙

1. **남의 자료를 넣어 팔지 않는다.** 무료 글꼴·음악·LUT·그림이라도 대부분 「원본 파일을 템플릿에 넣어 재판매」를 금지한다 (2026-11-13 조사: 눈누 글꼴 대부분, Pixabay Music, Bensound, Mixkit, Freepik, LUT 배포처 EULA). 넣어도 되는 것: 직접 만든 것 · SIL OFL 글꼴(글꼴만 따로 팔지 않는 조건) · MIT/Apache 자료(고지 유지). 그 밖에는 `meta.credits` 에 받는 곳만 안내한다
2. **실행되는 것을 넣지 않는다.** 설치 명령은 `json md txt png jpg webp mp4 ectemplate cube wav mp3 m4a ttf otf` 만 받고, 패키지 안의 무엇도 실행하지 않는다
3. `id` = 폴더 이름 = zip 안 최상위 폴더 이름

## Install · 설치

```bat
vc.cmd template list                        :: 설치된 것 + 목록 파일(index.json)에 있는 것
vc.cmd template install calm_mood          :: 목록에서 받아 설치 (무료)
vc.cmd template install D:\받은파일\pack.zip :: 구매해서 받은 zip 설치 (유료)
```

목록 파일 형식은 `index.example.json`.
