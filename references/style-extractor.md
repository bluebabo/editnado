# 레퍼런스 영상에서 스타일 따기

사용자가 예전에 만든 영상(또는 마음에 드는 영상)을 주면 **뽑을 수 있는 것만** 프로필로 옮긴다.

## 1. 뽑는 것과 방법

| 항목 | 방법 | 프로필 키 |
|---|---|---|
| 가로/세로·크기·fps | `filmcraft-cli --compact probe ref.mp4` (확인된 명령) | `video.width`·`height`·`fps`·`export_preset` |
| 장면 길이 (템포) | 영상을 FilmCraft 에 넣고 `clip.sceneEditDetection {"applyCuts":false,"generateMarkers":true}` → 표시 사이 평균 초 (시험 전) | `video.photo_seconds`, 계획서 장면 길이 |
| 자막 위치·색·외곽선 유무·굵기 | `vc.cmd sheet ref.mp4 -Out <폴더>` 의 장면 그림을 LLM 이 보고 판단 | `subtitles.anchor`·`margin`·`color`·`outline`·`font_style` |
| 제목 유무·위치 | 같은 그림 | `title.enabled`·`y_fraction` |

## 2. 뽑지 않는 것 (못 하는 것)

- **BGM 크기 비율** — 이미 섞인 소리에서 거꾸로 못 뽑는다. 기본값을 쓰고 사용자에게 묻는다
- **글꼴 이름** — 그림으로 정확히 못 맞춘다. 「굵은 고딕 / 명조 / 손글씨」 정도로만 말하고 가까운 설치 글꼴을 고른다
- 남의 영상은 스타일 값만 참고하고 영상·음악을 내려받아 쓰지 않는다 (본인 영상은 `cli-recipes.md` 의 yt-dlp)

## 3. 블로그 글투

블로그 주소를 주면 글투(높임말·문단 길이·이모티콘)는 `blog-writer` 스킬에 넘긴다. 이 스킬은 사진 크기(`photo.long_edge`)만 맞춘다.

## 4. 결과

`profiles/local/<이름>.json` 에 바뀐 키만 쓰고, 사용자에게 뽑은 값과 「뽑지 못한 것」을 한 표로 보여 준다.
