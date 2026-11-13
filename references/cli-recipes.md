# 명령 레시피

표시: **확인** = 이 스킬에서 돌려 봄 · **시험 전** = 명령은 있으나 아직 안 돌려 봄 · **미설치** = 열린 도구라 설치해야 씀 (설치는 그때마다 허락)

## 1. 실행기 `vc.cmd` — 확인

```bat
vc.cmd doctor                                        :: 도구·모델·글꼴·음성·템플릿 점검
vc.cmd setup                                         :: 없는 것과 크기만 표로 (받지 않음)
vc.cmd setup -Yes [-Quality high] [-Fonts]           :: 설치 (사용자 허락 뒤)
vc.cmd auto D:\여행\1108 -Template shorts_fast [-Title "제목"] [-Out <결과 폴더>] [-Bgm <음악>]  :: 자동 초안(절반 크기) → 기본 D:\여행\1108\완성\
vc.cmd build D:\여행\1108\완성\plan.json -Preview     :: 반 크기 미리보기 + _check.png
vc.cmd build D:\여행\1108\완성\plan.json              :: 원본 크기 + .srt
vc.cmd transcribe D:\여행\1108\소감.m4a -Out <폴더>   :: 받아쓰기만 (.srt + .txt)
vc.cmd sheet D:\여행\1108 -Out <폴더>                 :: media.json + 장면 모음 그림 (소리 파일은 받아씀)
vc.cmd stills D:\여행\1108\완성\plan.json [-Out <폴더>] :: 블로그용 영상 한 컷 (쓰인 구간 가운데, 원본 화질 JPG) — 폴더를 주면 영상 가운데
vc.cmd template list | install <id 또는 zip>          :: 템플릿
vc.cmd update [-Yes] [-Zip <파일>]                    :: 스킬 새 판 (깃 = git pull · zip = 최신 릴리스, 개인 취향 보존)
```

## 2. LightCraft — 사진 보정 (확인)

```bat
lightcraft-cli render 원본.jpg -o 보정.jpg --set color.vibrance=8 --set light.contrast=5 --size 1920
```
- 조절 이름 전체: `lightcraft-cli run --demo develop.controls`. 범위 예: `light.exposure` -5~5 · `light.contrast`·`color.saturation`·`color.vibrance` -100~100 · `wb.temp` 2000~50000K (절대값 — JPEG 기준값 미확인이라 프로필에 넣지 않음)
- `batch` 하위명령은 없다. 여러 장은 사진마다 `render`

## 3. PhotoCraft

```bat
photocraft-cli convert 썸네일.png 썸네일.jpg --quality 90          :: 확인
photocraft-cli convert 입력.psd 결과.png --gpu                     :: --gpu 는 하위명령 뒤 (앞에 두면 실패)
photocraft-cli commands --filter detectFaces --json               :: 명령 찾기
```
- 사진 얼굴 찾기 `image.detectFaces` → `{faces:[{rect:[x,y,w,h]}]}`, 가리기 `filter.pixelate.mosaic` — **시험 전**
- `convert` 에는 `--width`·`--height` 가 없다. 크기 바꾸기는 LightCraft `render --size`

## 4. FilmCraft 직접 (확인)

```bat
filmcraft-cli --compact probe 파일                          :: 길이·크기
filmcraft-cli --project P.fcproj render --seconds 1 --out f.png  :: 한 장 (썸네일)
filmcraft-cli export --list-presets                         :: 내보내기 프리셋
filmcraft-cli commands caption                              :: 명령 찾기
```
명령표·함정은 `filmcraft-commands.md`.

## 5. 열린 도구 (ArtCraft 보충 — 출처·라이선스는 `toolchain.md`)

### ffmpeg — 설치 `<tools>\ffmpeg\bin\` (아래 세 줄 모두 확인)
```bat
:: 가로 → 세로 1080×1920 (가운데 자르기, 폭을 짝수로)
ffmpeg -i in.mp4 -vf "crop=trunc(ih*9/16/2)*2:ih,scale=1080:1920" -c:v h264_amf -c:a copy out.mp4

:: BGM 섞기 — normalize=0 이 없으면 목소리까지 절반으로 줄어든다. BGM 이 짧으면 반복, 끝 2초 줄이기(st = 영상길이-2)
ffmpeg -i video.mp4 -stream_loop -1 -i bgm.mp3 -filter_complex "[1:a]volume=0.2,afade=t=out:st=58:d=2[b];[0:a][b]amix=inputs=2:duration=first:normalize=0[a]" -map 0:v -map "[a]" -c:v copy out.mp4

:: 자막 굽기 — 자막 파일이 있는 폴더에서 상대경로로 (C: 의 콜론 때문에 절대경로는 실패)
ffmpeg -i in.mp4 -vf "subtitles=sub.srt:force_style='FontName=Malgun Gothic,Bold=1,Outline=2,MarginV=29'" out.mp4
```
- `MarginV`·`FontSize` 는 화면 높이 288 기준 값 — 29 면 아래에서 약 10% 에 그려짐 (확인)
- `h264_amf` = AMD 내장 그래픽 인코더 (1080p 3초 분량 0.7초, CPU x264 1.3초)
- 폰마다 코덱·fps·회전이 다른 클립은 `concat -c copy` 로 못 붙인다 → FilmCraft 로 붙이거나 다시 인코딩

### whisper.cpp — 설치 `<tools>\whisper-cli\`, 한국어 받아쓰기 (확인)
```bat
ffmpeg -i 녹음.m4a -ar 16000 -ac 1 rec16k.wav
whisper-cli -m models\ggml-large-v3-turbo-q5_0.bin -f rec16k.wav -l auto -osrt -of rec -ml 28 -sow -np
```
- `vc.cmd transcribe`·`auto`·`build`(own) 가 이 두 줄을 대신 돌린다. 원본 결과(`<이름>_raw.srt`)는 남겨 두고 녹음이 그대로면 다시 받아쓰지 않으며, 템플릿 자막 한도(`max_chars × lines`)로 문장을 고르게 나눈다
- 29초 녹음에 35초 (large-v3-turbo, CPU). FilmCraft 명령줄판에는 받아쓰기가 없어 이것을 쓴다

### deface — 설치 `<tools>\deface\deface.cmd`, 사진·영상 얼굴 흐림 (실행 확인, 얼굴 찾기 품질은 시험 전)
```bat
deface.cmd 사진.jpg -o 사진_가림.jpg
deface.cmd 영상.mp4 -o 영상_가림.mp4
```
5초 1080p 영상 48.6초 (CPU). 결과 영상은 다시 인코딩되어 화질이 낮아질 수 있으니 확인 후 쓴다. 번호판은 못 가린다.

### yt-dlp — 설치 `<tools>\yt-dlp\`, 사용자 본인 영상만 (스타일 따기용)
```bat
yt-dlp -o ref.mp4 "<본인 영상 주소>"
```
남의 영상·음악을 받아 쓰지 않는다.

### 장소 이름 — OpenStreetMap Nominatim, 시험 전 (사진 위치가 밖으로 나가므로 쓸 때마다 허락)
```powershell
Invoke-RestMethod "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=38.2070&lon=128.5918&accept-language=ko" -Headers @{ 'User-Agent' = 'editnado' }
```
1초에 한 번 이하, 대량 변환 금지 (이용 규칙). 좌표는 `media.json` 의 `lat`·`lon`.

### 그날 날씨 — Open-Meteo 과거 기상, 시험 전 (비상업 무료, 위치 전송이라 허락)
```powershell
Invoke-RestMethod "https://archive-api.open-meteo.com/v1/archive?latitude=38.21&longitude=128.59&start_date=2026-11-12&end_date=2026-11-12&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=Asia/Seoul"
```
