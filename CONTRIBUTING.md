# Contributing to Editnado

이 프로젝트는 **「찍고 말하면 편집되는」 대화형 영상 편집 스킬**을 지향합니다.

## 💡 기여할 수 있는 것

1. **FilmCraft 명령** — 새로 돌려 본 명령과 함정을 `references/filmcraft-commands.md` 표에 (실측 결과와 판 번호 함께)
2. **템플릿** — `templates/<id>/template.json` + 미리보기 (형식·판매 규칙은 `templates/README.md`). 남의 글꼴·음악·LUT 원본은 넣지 않는다
3. **열린 도구·자료** — ArtCraft 에 없는 일을 하는 무료 도구를 `references/toolchain.md` 기준대로 (공식 출처·라이선스·키 필요 여부)
4. **실행기** — `vc.ps1` 버그·이식성 (macOS·Linux 는 아직 없음)
5. **문서** — 오탈자, 영어판

## 🛠️ Pull Request

1. 저장소를 Fork
2. 브랜치 생성 (`git checkout -b feature/new-profile`)
3. 커밋 (`git commit -m "Add square card-news profile"`)
4. Push 후 Pull Request

## 📦 새 판 내기 (관리자)

1. 바꾼 것을 시험하고 `SKILL.md` 의 `metadata.version` 을 올린다 (예: 2.2.0 → 2.3.0, 고친 것만이면 2.2.1) · 개정 이력 한 줄
2. 커밋·푸시
3. `powershell -File release.ps1` 로 태그·바뀐 것 목록을 확인 → `release.ps1 -Publish` = 태그 `v<판>` + `editnado-<판>.zip`(git archive, `.gitattributes` 의 export-ignore 제외) + `SHA256SUMS.txt` 를 GitHub 릴리스로
4. 사용자는 `vc.cmd update` 로 받는다

## ⚠️ 원칙

1. **확인된 것만** — 명령·수치는 직접 돌려 본 것만 적고, 아니면 「시험 전」이라고 표시합니다
2. **AI 는 작은 입력으로 판단만** — 영상 원본이나 긴 로그를 LLM 에 넣는 방식은 받지 않습니다
3. **키·유료 서비스 금지** — 계정·API 키·크레딧이 드는 도구는 넣지 않습니다
4. **경로 하드코딩 금지** — 상대 경로나 환경변수(`VC_CRAFT_DIR`)로
5. **개인 자료는 PC 안에서** — 위치·얼굴 같은 개인 자료를 인터넷 서비스로 보내는 기능은 매번 사용자 허락을 받게 만듭니다
