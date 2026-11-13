# 새 PC 에서 처음 쓸 때

## 1. 스킬 넣기

이 폴더를 에이전트의 스킬 자리에 둔다.

| 에이전트 | 자리 |
|---|---|
| Google Antigravity | 작업공간 `.agents/skills/editnado/` (전역 `~/.gemini/config/skills/editnado/`) |
| OpenAI Codex | 작업공간 `.agents/skills/editnado/` (조사 자료 — 미확인) |
| Claude Code | 작업공간 `.claude/skills/editnado/` 또는 `~/.claude/skills/editnado/` |

두 곳에서 다 쓰려면 복사하지 말고 연결한다: `mklink /J .claude\skills\editnado .agents\skills\editnado` (관리자 권한 불필요).

## 2. 도구 깔기

```bat
vc.cmd doctor          :: 무엇이 있고 없는지
vc.cmd setup           :: 받을 것과 크기 (아무것도 받지 않음) → 사용자에게 보여 주고 허락
vc.cmd setup -Yes      :: 설치
```

- 설치 자리: 환경변수 `VC_TOOLS_DIR` → 작업공간의 `2.Common\tools` (있을 때) → `%LOCALAPPDATA%\editnado\tools`
- 받는 것 (기본, 약 870MB): FilmCraft·EffectCraft (github.com/storytold, SHA256 + 서명 「Learning Machines Inc」 확인) · ffmpeg (gyan.dev, SHA256) · whisper.cpp (GitHub, SHA256) · 받아쓰기 모델 large-v3-turbo 547MB (Hugging Face, SHA256)
- 아주 낮은 사양이면 `-Quality normal` = small 181MB — 한국어를 자주 틀린다 (실측: 「해 뜨는」→「헤드는」), AI 가 받아쓴 글을 고쳐야 한다
- 사진 보정을 쓰려면 `-Photo` (LightCraft 118MB + PhotoCraft 137MB)
- 글꼴(`-Fonts`): 나눔고딕·Pretendard·D2Coding (SIL OFL) 을 사용자 계정에 설치. Claude 데스크톱 앱 안에서는 레지스트리 쓰기가 앱 전용 복사본에만 가므로 앱 밖에서 실행해야 한다
- 한국어 음성이 「없음」이면 기계 음성 내레이션을 못 쓴다 (Windows 설정 → 시간 및 언어 → 음성에서 추가 — 사용자가 직접)

## 2-1. 새 판 받기

```bat
vc.cmd update          :: 새 판이 있는지와 바뀐 것 (아무것도 바꾸지 않음) → 사용자에게 보여 주고 허락
vc.cmd update -Yes     :: 받기
```

- 깃으로 받은 폴더(`git clone`) = `git pull`. 이 폴더에서 고친 파일이 있으면 덮지 않고 멈춘다
- zip 으로 받은 폴더 = GitHub 최신 릴리스의 `editnado-<판>.zip` 을 `SHA256SUMS.txt` 로 확인한 뒤 덮는다. 직접 받은 zip 은 `vc.cmd update -Zip <파일> -Yes`
- `profiles/local/`(개인 취향)·설치한 템플릿은 그대로, 바뀌는 파일은 `<도구 자리>\backup\editnado-<옛 판>-<시각>\` 에 백업
- 비공개 저장소는 릴리스 정보를 로그인 없이 못 받으므로 `git clone` 으로 받아 쓴다

## 3. 개인 취향이 없을 때 (`profiles/local/` 이 비어 있음)

첫 편집 때 하나씩 묻는다 (한 번에 하나):
1. 주로 어디에 올리나요? (유튜브 가로 / 쇼츠·릴스 세로 / 블로그) → 템플릿
2. 자막은? (깔끔한 흰 글자 / 노란 굵은 글자 / 큰 글씨)
3. 말투는? (「~습니다」 / 「~해요」 / 반말)

답으로 `profiles/local/<템플릿id>.json` 에 바뀐 키만 쓴다.
