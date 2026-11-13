# 도구 현황 · 열린 도구 쓰는 기준 · MCP

## 1. 기본 도구 — ArtCraft 무료 앱 (MIT/Apache-2.0, 계정·클라우드 없음)

| 앱 | 하는 일 | 확인한 판 (2026-11-12) |
|---|---|---|
| FilmCraft | 타임라인·자막·받아쓰기·덕킹·음량·내보내기 — 실행기의 엔진 | 0.20.1 |
| LightCraft | 사진 보정 `render --set` | 0.21.0 |
| PhotoCraft | 형식 변환·썸네일·사진 얼굴 찾기 | 0.23.0 |
| SoundCraft | 소리 정보·침묵 자르기 | 0.20.1 |
| EffectCraft | 모션 그래픽 (아직 레시피 없음) | 0.24.1 |

- 찾는 순서: 환경변수 `VC_CRAFT_DIR` → `VC_TOOLS_DIR\craft` → `<작업공간>\2.Common\tools\craft` → `%LOCALAPPDATA%\editnado\tools\craft` → PATH (`vc_paths.ps1`). 점검 `vc.cmd doctor`
- 설치 `vc.cmd setup -Yes`: GitHub 릴리스의 `*windows-x64-portable.zip` + `SHA256SUMS.txt` 대조 + 실행 파일 서명(`CN=Learning Machines Inc`) 확인. 이미 있으면 받지 않는다 (업데이트는 ArtCraft 쪽 방식 — 예: 작업공간의 `craft_bg_update.ps1`)
- 생성 AI 기능(유료 크레딧)은 쓰지 않는다

## 2. 열린 도구·자료를 쓰는 기준

1. ArtCraft 에 있으면 ArtCraft 먼저. 없거나 열린 것이 확실히 나을 때만
2. 공식 출처에서만 받고, 설치 없이 도는 판으로 `<작업공간>\2.Common\tools\<이름>\` 에 둔다
3. 계정·API 키·크레딧·종량 요금이 드는 것은 무료라도 쓰지 않는다
4. 도구·자료마다 라이선스·약관을 아래 표에 한 줄 남긴다
5. 사진·영상·위치 같은 개인 자료를 인터넷 서비스로 보낼 때는 그때마다 허락을 받는다. 개인 자료 처리는 PC 안에서, 인터넷은 공개 정보에만
6. 승격 조건: 화면 없이 명령줄로 끝남 · 이 PC 에서 돌려 확인 · 결과 품질 확인 · 포터블

## 3. 열린 도구·자료 후보 (2026-11-12 조사 — 표시 없는 칸은 조사 자료, 「확인」은 직접 대조)

| 쓰임 | 후보 | 라이선스 · 조건 | 상태 |
|---|---|---|---|
| 영상 속 얼굴 가리기 | deface 1.5.0 (`github.com/ORB-HD/deface`) | MIT | **설치** `<tools>\deface\deface.cmd` (LibreOffice Python + `lib\` 따로, 462MB). 실행 확인: 사진 1.8초, 5초 1080p 영상 48.6초(CPU). 사람 얼굴을 실제로 찾는지는 시험 전 |
| 영상 속 번호판·얼굴 가리기 | EgoBlur (`github.com/facebookresearch/EgoBlur`) | Apache-2.0 (모델 가중치 조건 미확인), Python 필요 | 저장소·라이선스 확인 · 미설치 |
| 한국어 받아쓰기 (**own 내레이션 자막의 엔진**) | whisper.cpp b5454 (= v1.9.5) `whisper-blas-bin-x64.zip` + `ggml-large-v3-turbo-q5_0.bin` 547MB (`huggingface.co/ggerganov/whisper.cpp`) | MIT | **설치** `<tools>\whisper-cli\` (613MB). 한국어 2문장 정확 (띄어쓰기 2곳만 다름), 8초 녹음에 약 35초(CPU). AMD 그래픽 가속(Vulkan) Windows 빌드는 배포 안 됨 (확인) |
| 가로→세로 사람 따라가기 | auto-vertical-reframe (`github.com/KazKozDev/auto-vertical-reframe`) | MIT | 저장소 확인, 별 25개로 작아 보류 — 대신 계획서 `focus_x` |
| 장소 이름 | OpenStreetMap Nominatim | 데이터 ODbL · 키 없음 · 1초 1회 · User-Agent 필수 · 대량 금지 | 시험 전 |
| 그날 날씨 | Open-Meteo 과거 기상 | 데이터 CC BY 4.0 · 키 없음 · 비상업 무료 · 하루 1만 회 | 시험 전 |
| 배경음악 | Incompetech · Audionautix | CC BY 4.0 — 영상 설명에 출처 표기 | 받아 둔 곡 없음 |
| 효과음 | SoundJay | 자체 무료 약관 (원본 재배포 금지) | 받아 둔 것 없음 |
| 글꼴 | 나눔고딕(`github.com/google/fonts` ofl/nanumgothic) · Pretendard 1.3.9 · D2Coding 1.4.0(`github.com/naver/d2-coding-font`) | SIL OFL 1.1 (라이선스 파일을 `<tools>\fonts\` 에 함께 둠) | **설치** (사용자 계정, `install_fonts.cmd`). 글꼴 이름 `NanumGothic`·`Pretendard`·`D2Coding`. FilmCraft 가 D2Coding 으로 그리는 것 확인 |
| 색감 LUT | slaycamera/luts | CC BY 4.0 | 별 23개로 작아 보류 — LightCraft 조절로 |
| 쇼츠 규격 | YouTube 고객센터 `support.google.com/youtube/answer/10059070` | 2024-10-15 부터 최대 3분 · 화면 글자 영역 픽셀 안내 없음 · 권장 음량 공식 수치 없음 (업계 통상 -14 LUFS) | 프로필 반영 |
| 영상 처리 보충 · 받아쓰기 전 소리 변환 | ffmpeg 9.0.2 essentials (`gyan.dev/ffmpeg/builds`) | GPL/LGPL | **설치** `<tools>\ffmpeg\bin\` (SHA256 일치). `h264_amf` 실제 동작: 1080p 3초 분량 0.7초 (x264 1.3초) |
| 본인 영상 레퍼런스 받기 | yt-dlp 2026.10.26 (`github.com/yt-dlp/yt-dlp`) | Unlicense | **설치** `<tools>\yt-dlp\yt-dlp.exe` (SHA256 일치) |

## 3-1. 에이전트별 스킬 자리와 무료 사용 (2026-11-13 조사, 표시한 것만 원문 대조)

| 에이전트 | 스킬 자리 | 명령 실행 | 무료로 쓸 수 있나 |
|---|---|---|---|
| Google Antigravity | 작업공간 `.agents/skills/<이름>/SKILL.md`, 전역 `~/.gemini/config/skills/` — **원문 대조** (`antigravity.google/docs/skills`, `description` 필수) | 됨 | 무료 등급 있음 (주간 한도) — 조사 자료 |
| OpenAI Codex | `.agents/skills/`, `~/.codex/skills/`, `AGENTS.md` | 됨 (사용자 승인) | ChatGPT 무료로는 사실상 안 됨 — 조사 자료 |
| ChatGPT Windows 앱 | Codex 연동으로 로컬 폴더·명령 | 됨 | 유료 등급 — 조사 자료 |
| Claude Code | `.claude/skills/`, `~/.claude/skills/` | 됨 | 유료 (Pro 이상 또는 API) — 조사 자료 |
| 공통 표준 | agentskills.io — Anthropic 이 만들어 공개. `name` 64자·소문자·하이픈·폴더 이름과 같게, `description` 1,024자, 본문 5천 토큰·500줄 이하 권장 — **원문 대조** | | |

→ 무료 사용자에게 현실적인 길은 **안티그래비티**. 소개서(README·llms.txt)도 안티그래비티를 먼저 적는다.

## 3-2. 템플릿 재료 — 유료 템플릿에 넣어 팔아도 되나 (조사 자료, 사이트별 약관 원문 확인 필요)

| 재료 | 받는 곳 예 | 유료 템플릿에 원본 넣기 |
|---|---|---|
| 한글 글꼴 | 눈누 (글꼴마다 다름) | 대부분 안 됨 · SIL OFL 은 「글꼴만 따로 팔지 않으면」 가능 |
| LUT | Fresh LUTs · Ground Control | 안 됨 (EULA) |
| 배경음악 | Bensound · Pixabay Music · Incompetech | 안 됨 (원본 추출 가능한 템플릿·번들 판매 금지) |
| 효과음 | Mixkit · SoundJay | 안 됨 |
| 그래픽 | Freepik | 안 됨 |

→ 판매 템플릿에는 **직접 만든 것 + OFL 글꼴 + MIT/Apache 자료(고지 유지)** 만 넣고, 나머지는 받는 곳만 안내한다 (`templates/README.md` 판매 규칙).

## 4. MCP 로 붙일 때 (대화하며 세밀하게 고칠 때만)

| 앱 | 도구 수 | LLM 에 실리는 양 (어림) |
|---|---|---|
| FilmCraft `mcp` | 17 | 약 3천 토큰 |
| PhotoCraft `mcp` | 26 | 약 9천 |
| LightCraft `mcp` | 409 | 약 6만 4천 — 쓰지 않는다 |
| LightCraft `mcp --compact` | 17 | 약 5천 |
| SoundCraft `mcp` | 17 | 약 1천 |
| EffectCraft `mcp` | 27 | 약 7천 |

(2026-11-12 이 PC 에서 `tools/list` 응답 크기 ÷ 3.5 로 어림)

등록 예 (Claude Code — 설정이 바뀌므로 사용자 허락 후, 읽기·쓰기 폴더를 작업 폴더로 제한):
```bat
claude mcp add filmcraft -- <craft>\filmcraft\filmcraft-cli.exe mcp
claude mcp add lightcraft -- <craft>\lightcraft\lightcraft-cli.exe mcp --compact
claude mcp add soundcraft -- <craft>\soundcraft\soundcraft-cli.exe mcp --automation-read-root <작업폴더> --automation-write-root <작업폴더>\out
```
PhotoCraft·SoundCraft 는 `--automation-read-root`·`--automation-write-root` 로 폴더를 제한할 수 있다 (도움말 확인). FilmCraft·LightCraft 의 폴더 제한 옵션은 미확인.

## 5. 업데이트 이력
- 2026-11-12: 도구 체인 정립 · 같은 날 다시 씀 — FilmCraft 를 엔진으로, 열린 도구는 보충, MCP 크기 실측
