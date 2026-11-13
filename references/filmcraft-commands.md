# FilmCraft 명령 — 확인된 것만 (filmcraft-cli 0.20.1, Windows 11)

실행기 `vc.ps1` 가 쓰는 명령과, 실측으로 알게 된 함정. 여기 없는 명령은 `filmcraft-cli commands <낱말>` · `describe <명령>` 으로 찾고, 돌려 본 뒤 이 표에 더한다.

## 1. 실행 방식

- 새 프로젝트: `filmcraft-cli --compact --keep-going --save-as P.fcproj run X.jsonl`
- 이어서: `filmcraft-cli --compact --keep-going --project P.fcproj --save run X.jsonl`
- 한 줄 = `{"id":"<명령>","params":{…}}`, `#` 줄은 주석. 결과는 명령마다 JSON 한 줄 (`ok`, `result` 또는 `error`)
- 시간: 1초 = 254016000000 틱
- 정보: `filmcraft-cli --compact probe <파일>` (사진은 `kind:"Still"`) · 한 장: `--project P render --seconds S --scale 0.5 --out f.png`

## 2. 함정 (실측)

| 함정 | 증상 | 대처 |
|---|---|---|
| jsonl 앞의 UTF-8 BOM | 첫 줄에서 `expected value` 로 실패 | BOM 없이 쓴다. PowerShell 5.1 `Set-Content -Encoding utf8` 은 BOM 을 붙임 |
| `timeline.place` 시작 시각 | `"time":{"seconds":4}` 로 주면 무시되어 모두 0초에 덮어씀 | `"seconds":4` 를 바로 넣는다 (`sourceIn`·`duration` 은 `{"seconds":x}` 형태가 맞음) |
| ID | 시퀀스·항목·클립이 카운터 하나를 같이 써서 미리 알 수 없음 | 단계마다 run 을 나눠 결과에서 ID 를 읽는다 |
| 16:9 시퀀스 + 쇼츠 프리셋 | 가운데 약 607px 를 잘라 1.78배로 늘려 흐림 · 자막 앞뒤가 화면 밖으로 잘림 | 처음부터 1080×1920 시퀀스 (`file.newSequence`) + `clip.fillFrame` |
| 시퀀스 크기만 바꿈 | 클립이 원래 크기로 왼쪽 위에 붙음 (`scaledClips:0`) | 클립마다 `clip.fillFrame` |
| 제목 위치 | `graphics.newText` 의 position 은 글자 시작점이라 가운데가 아님 | `graphics.set {align:center}` + `graphics.align {hcenter}` |
| 미리보기 크기 | `file.exportMedia` 의 `scale:0.5` 는 프리셋 크기에 눌려 원본 크기로 나옴 | `width`·`height` 를 반으로 직접 준다 → 540×960, 굽기 19.5초 → 7.4초 |
| PowerShell 5.1 — 네이티브 인자 | exe 에 JSON 문자열을 인자로 넘기면 큰따옴표가 지워져 「key must be a string」 | JSON 은 파일로 (`run --commands 파일`, `--values 파일`) |
| PowerShell 5.1 — JSON 배열 | `@(Get-Content … \| ConvertFrom-Json)` 은 배열 전체가 한 항목이 된다 | 변수에 먼저 받고 `@($x \| ForEach-Object { $_ })` |
| PowerShell 5.1 — 변수 이름 | 대소문자를 안 가려 `$Lines`(인자)와 `$lines`(지역)가 같은 변수, `$T` 와 `$t` 도 같음 | 다른 이름 |
| PowerShell 5.1 에서 부를 때 | 정상 진행 문구(`rendered…`)도 표준오류라 `$ErrorActionPreference='Stop'` 이면 멈춤 · 결과 한 줄이면 배열이 풀려 `.Count` 없음 · BOM 없는 JSON 을 `Get-Content` 가 ANSI 로 읽음 | 부르는 동안 `Continue` · `return ,$배열` · `-Encoding UTF8` (`vc.ps1` 에 반영) |

## 3. 명령표

| 명령 | params | 결과 · 확인 |
|---|---|---|
| `file.newSequence` | `name, width, height, fps, video:3, audio:3` | `{sequence}` 확인 |
| `file.import` | `paths:[…]` | `{items:[…]}` 넣은 순서 · 확인 |
| `file.newSequenceFromClip` | `items:[id]` | 확인 |
| `timeline.place` | `item, track:"V1", audioTrack:"A1", seconds, insert:false, sourceIn:{seconds}, duration:{seconds}` · 소리만 `track:"A2", video:false` | `{clips:[영상, 소리]}` · 확인 |
| `clip.fillFrame` | `{}` = 방금 놓은 클립 | `{clips:[{clip, scale}]}` (16:9 → 9:16 = 177.78) · 확인 |
| `effects.toggleAnimation` | `clip, effect:"motion", param:"scale"` | 확인 |
| `effects.setParam` | 확대 `clip, effect:"motion", param:"scale", value, time:<시퀀스 틱>` · 구도 `param:"position", value:[x,y]` (화면 픽셀, 클립 가운데) | 확인 — 사진 3초 178→215% 로 확대됨 · x 1393 = 원본 왼쪽 1/4 지점이 가운데 |
| `sequence.applyVideoTransition` | `clip, effect:"cross_dissolve", frames, edge:"in"` | 확인 |
| `sequence.applyAudioTransition` | `clip, effect:"exponential_fade", frames, edge:"out"` | 확인 |
| `essentialSound.setType` | `clips:[…], type:"dialogue"|"music"|"ambience"|"sfx"` | 확인 |
| `essentialSound.set` | `clips:[bgm], values:{"ducking.enabled":true, "ducking.reduceDb":-16.5}` | 확인 |
| `essentialSound.generateDucking` | `clips:[bgm]` | 내레이션 2줄 구간 [0.6–3.13], [4.44–6.89] 초에 -16.5dB · 확인 |
| `captions.import` | `path, language:"ko"` | 확인 |
| `captions.setStyle` | `track:"C1", font, fontStyle, color, outline, outlineColor, background, anchor, margin(화면 높이 비율)` | 화면 폭에 맞춰 자동 2줄 · 확인 |
| `graphics.newText` | `text, position:[x,y], size, font, fontStyle, seconds` | `{clip, layer}` · 확인 |
| `graphics.set` · `graphics.align` | `clip, layer:0, props:{align:"center", fill_color}` · `clip, layers:[0], align:"hcenter", to:"frame"` | 가운데 정렬 확인 |
| `file.exportMedia` | `path, preset, burnCaptions, hardwareEncoding:"auto", loudnessLufs, captionSidecar:"srt", width, height` | 확인 (하드웨어 인코딩 실제 사용 여부·음량은 측정 안 함) |
| `transcript.models` · `transcript.downloadModel` | `{}` · `model=whisper-base` | 목록·내려받기는 됨 (base 277MB, 38초). 그러나 `available:false` |
| `transcript.generate` | | **이 명령줄판에서는 안 됨** — 「speech-to-text is not available in this build (built without the `whisper` feature)」(0.20.1 실측). 받아쓰기는 whisper.cpp 로 (`cli-recipes.md`), 결과 SRT 를 `captions.import` |
| `transcript.set` · `createCaptions` · `removePauses` · `removeFillers` | | 시험 전 (받아쓰기 결과를 `transcript.set` 으로 넣으면 쓸 수 있을 것으로 보임) |
| `clip.sceneEditDetection` | `clips, sensitivity, applyCuts:false, generateMarkers:true` | 시험 전 |
| `lumetri.applyPreset` | `name, clips:[…]` (목록 `lumetri.presets`) | 「Golden Dusk」 3클립 적용, 화면이 따뜻해짐 · 확인 |
| `captions.setStyle` 의 `size` | 숫자 (기본 약 64 로 추정, 90 이면 9:16 에서 3줄) | 확인 |
| `essentialSound.set` + `generateDucking` 을 **ambience** 클립에 | `values:{"ducking.enabled":true,"ducking.reduceDb":-12}` | 내레이션 구간 0.6~3.13초에 −12dB · 확인 |

## 3-1. EffectCraft (effectcraft-cli 0.24.1) — 인트로 그래픽 템플릿

| 명령 | 결과 · 확인 |
|---|---|
| `effectcraft-cli exec templates.list --params "{}"` | 기본 템플릿 8개: lower-third · title-card · logo-reveal · kinetic-type · social-square · vertical-story · slideshow · text-orbit-3d (글자 칸 이름 포함) |
| `run --commands 파일` 에 `{"command":"templates.create","params":{"id":"vertical-story"}}` + `{"command":"essential.exportTemplate","params":{"path":"….ectemplate"}}` | `.ectemplate` 파일 (143~161KB) · 확인 |
| `render --template T.ectemplate --values V.json --out intro.mp4 --format h264` | `V.json` = `{"Headline":"솔빛해변\n하루 여행","Call to Action":"2026. 11. 8"}` → 1080×1920 8초, 10.5초, 한글 정상 · 확인 |
| `render-frame --template … --values … --time 1.5 --max-side 320 --out f.png` | 한 장 · 확인. 글자는 1~1.5초에 다 나타남 |

내보내기 프리셋 (곱하기는 `×`): `YouTube Shorts 1080×1920` · `YouTube 1080p Full HD` · `YouTube 2160p 4K Ultra HD` · 전체 목록 `filmcraft-cli export --list-presets`

## 4. 실측 기록 (2026-11-12, AMD Radeon 내장 그래픽 PC)

| 시험 | 결과 |
|---|---|
| 1080×1920, 영상 2개(4초씩) + 사진 1장(3초) + 기계 음성 2줄 + BGM, 덕킹·확대·전환·자막·제목, 원본 화질 | 11초 영상, 330프레임, 렌더 18.4초 (17.9fps), H.264 High 30fps, .srt 함께 |
| 데모 5초 쇼츠 내보내기 | 11.7초 (10fps) |
| 기계 음성 (Windows `Microsoft Heami Desktop`) | 문장당 약 3.4초 wav, 22.05kHz |
