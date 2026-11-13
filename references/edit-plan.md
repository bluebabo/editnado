# 편집 계획서 (plan.json)

보통은 `vc.cmd auto` 가 만들어 준다. AI 는 사용자 말에 따라 값만 고치고 `vc.cmd build plan.json [-Preview]` 로 다시 굽는다.

## 1. 형식

```json
{
  "template": "shorts_fast",
  "overrides": { "subtitles.margin": 0.26 },
  "title": "솔빛해변 하루",
  "date": "2026. 11. 8",
  "output": "D:/여행/1108/완성/솔빛해변 하루.mp4",
  "timeline": [
    { "media": "D:/여행/1108/IMG_0712.jpg", "zoom": [1.0, 1.15] },
    { "media": "D:/여행/1108/VID_0935.mp4", "in": 0.9, "focus_x": 0.5 },
    { "media": "D:/여행/1108/IMG_2210.jpg", "zoom": [1.0, 1.15], "crop": [0, 0, 0.8, 1] }
  ],
  "align": [1, 2, 3],
  "tail_seconds": 4.0,
  "narration": { "mode": "own", "file": "D:/여행/1108/소감.m4a" },
  "bgm": { "file": "D:/여행/1108/bgm_calm.wav" },
  "captions": { "srt": "D:/여행/1108/완성/고친자막.srt" }
}
```

| 키 | 뜻 | 없으면 |
|---|---|---|
| `template` | 템플릿 id (`templates/<id>/`). 옛 이름 `profile` 도 받음 | `default` |
| `overrides` | 이번 한 번만 바꿀 값, 점 경로 키 (`_base.json` 에 있는 키만) | 없음 |
| `title` · `date` | 인트로 그래픽의 `{title}`·`{date}` 자리, 인트로가 없는 템플릿은 화면 위 제목 | 제목 없음 |
| `output` | 결과 mp4. 같은 폴더에 `_vc_work\`·확인 그림·받아쓰기 파일이 생김 | 필수 |
| `timeline[]` | 장면 순서 (인트로 다음부터 이어 붙임) | 필수 |
| ↳ `media` | 영상·사진 경로 (`/`·`\` 둘 다 됨) | 필수 |
| ↳ `in`·`out` | 영상에서 쓸 구간(초) | 0 · 끝 |
| ↳ `seconds` · `zoom` | 사진 길이(`align` 이 있으면 무시) · 천천히 확대 [시작배, 끝배] | 템플릿 값 |
| ↳ `crop` | 사진 일부만 쓰기 [왼쪽, 위, 너비, 높이] 사진 크기 대비 0~1. 원본은 두고 `_vc_work` 에 잘라낸 PNG 사본 | 통째 |
| ↳ `focus_x` | 가로 원본을 세로 화면에 채울 때 보일 가로 위치 0~1. 원본이 화면보다 조금만 넓으면 움직일 여유가 작아 끝에 붙는다 | 0.5 |
| ↳ `audio` | `ambience`(현장음) · `dialogue`(말소리) · `none` | 템플릿 `audio.clip_audio` |
| `narration` | `own` = 사용자 녹음 `{"mode":"own","file":…,"at":초}` (at 없으면 인트로 바로 뒤) · `tts` = `{"mode":"tts","lines":[{"text":…,"at":초}]}` · `none` | 없음 |
| `bgm.file` | 배경음악. 영상보다 짧으면 이어 붙임, 말소리 때 자동으로 작아짐, 끝은 서서히 | 없음 |
| `captions.srt` | 직접 고친 자막 파일 (받아쓰기·TTS 자막 대신) | 자동 |
| `align` | 장면마다 보여 줄 내레이션 문장 번호 (1부터, 커지는 순서, 장면 수만큼). 있으면 장면 길이를 문장 시각으로 계산: 문장 사이 쉼의 가운데에서 장면을 바꾸고, 같은 문장의 장면은 그 자리를 똑같이 나누고, 장면이 없는 문장은 앞 장면이 이어서 덮는다. 영상이 모자라면 시작점을 앞으로 당기고, 그래도 모자라면 남는 시간을 다음 장면에 넘긴다 | 장면별 `seconds`·`out` |
| `tail_seconds` | `align` 일 때 말이 끝난 뒤 마지막 장면 여운(초) | 1.0 |

내레이션이 있으면 영상 현장음은 말할 때 템플릿 `audio.clip_duck_db`(기본 −12dB)만큼 작아진다.

## 2. auto 가 정하는 규칙

- 순서 = 찍은 시각 (사진 EXIF, 없으면 파일 시각)
- 영상 = 가운데 구간, 현장음은 살리고 내레이션 때 줄임 · 사진 = 확대·축소 번갈아
- 소리 파일 중 이름에 `소감|memo|녹음|voice|narration` → 내 목소리 내레이션 (하나뿐이면 그것). `bgm|music|음악` → 배경음악
- 받아쓴 내레이션이 있으면 `align` 을 정한다: 장면이 문장보다 많으면 찍은 시각 간격이 가장 짧은 곳부터 같은 문장으로 묶고, 적으면 문장을 고르게 나눠 맡긴다. 「말한 순서 = 찍은 순서」로 본 기본값이라 틀릴 수 있다 → AI 가 장면 모음과 `sentences` 를 보고 고친다
- 내레이션이 없거나 받아쓰지 않으면(`-NoTranscribe`): 영상 `video.clip_seconds` 초 · 사진 `video.photo_seconds` 초, 내레이션 길이에 맞춰 사진을 늘림 (한 장 최대 6초) · `video.max_seconds` 를 넘으면 같은 비율로 줄임 (장면당 최소 1.5초)
- 미리보기 = 절반 크기 `<제목>_preview.mp4`, `-Final` 이면 원본 크기
- 제목 = `-Title` 또는 폴더 이름, 날짜 = 첫 장면 찍은 날

## 3. AI 가 고를 때 (auto 결과를 손볼 때)

- 대표 장면 모음(`sheet_N.png`)에서 흔들림·가림·비슷한 장면을 빼고, 소감에 나온 순간(「노을」)이 꼭 들어가게
- **장면 ↔ 말이 먼저:** 문장 내용(「야경 드라이브」)과 그 장면(낮 바다)이 어긋나면 `align` 을 고친다. 한 문장에 장면 2~3개까지
- 쇼츠는 장면당 2~5초, 가로 영상은 4~8초 — `align` 이면 장면 수로 조절 (문장에 장면을 더 주면 짧아진다)
- 말하는 영상은 `audio: "dialogue"` 로 살리고, `align` 이 없으면 받아쓴 글에서 말이 끝나는 곳에 `out`
- 사람·주인공이 그림 어느 쪽에 있는지 보고 `focus_x`

## 4. 사용자에게 보여 줄 요약

```
32초 · 장면 9개 (인트로 포함) · 첫 자막 「오늘은 아침 일찍 바닷가에서 해」
미리보기: D:\여행\1108\완성\솔빛해변 하루_preview.mp4
```

## 5. 실행기 출력

- `auto`: `{"plan","output","check","seconds_total","intro_seconds","narration_seconds","scenes":[{"n","file","kind","taken","sentence","seconds"}],"sentences":[{"k","at","text"}],"warnings":[…]}` — `at` = 타임라인 초
- `build`: `{"output","seconds_total","check","scenes":[{"n","start","seconds"}],"sentences":[…],"warnings":[…]}`
- `stills`: `{"folder","stills":[{"video","seconds","image"}],"warnings":[…]}`
- 경고 예: 「인트로 제목이 4줄이라 넘쳐요」 · 「align 은 장면 수만큼…」 · 「마지막 영상이 짧아 N초 일찍 끝나요」
- 확인 그림(`*_check.png`) = 인트로 한 장 + 장면마다 가운데 한 장 (장면당 폭 약 300px)
