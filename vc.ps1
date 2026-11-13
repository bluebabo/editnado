[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('doctor', 'sheet', 'build', 'transcribe', 'auto', 'stills')]
    [string]$Command,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments,
    [string]$Out,
    [string]$Template,
    [string]$Title,
    [string]$Bgm,
    [switch]$Preview,
    [switch]$Final,
    [switch]$NoTranscribe
)

. (Join-Path $PSScriptRoot 'vc_paths.ps1')

$ErrorActionPreference = 'Stop'
$script:TicksPerSecond = 254016000000
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:TemplateDir = Get-TemplatesDir

function Write-JsonLines {
    param([string]$Path, [string[]]$Lines)
    [IO.File]::WriteAllText($Path, (($Lines -join "`n") + "`n"), $script:Utf8NoBom)
}

function Invoke-Craft {
    param([string]$Exe, [string[]]$CliArgs)
    $ErrorActionPreference = 'Continue'
    $lines = & $Exe @CliArgs 2>$null
    $parsed = @()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $parsed += ($line | ConvertFrom-Json) } catch {}
    }
    return ,$parsed
}

function Invoke-Run {
    param([string]$Exe, [string]$Project, [string]$Work, [string]$Stage, [object[]]$Commands, [switch]$NewProject)
    $jsonl = Join-Path $Work "$Stage.jsonl"
    $rows = @()
    foreach ($item in $Commands) { $rows += (ConvertTo-Json -InputObject $item -Depth 30 -Compress) }
    Write-JsonLines $jsonl $rows
    $path = $jsonl.Replace('\', '/')
    if ($NewProject) {
        $cliArgs = @('--compact', '--keep-going', '--save-as', $Project.Replace('\', '/'), 'run', $path)
    } else {
        $cliArgs = @('--compact', '--keep-going', '--project', $Project.Replace('\', '/'), '--save', 'run', $path)
    }
    $results = Invoke-Craft $Exe $cliArgs
    foreach ($result in $results) {
        if ($result.ok -eq $false) {
            Write-Host "[$Stage] $($result.id) 줄 $($result.line): $($result.error)"
            exit 1
        }
    }
    return $results
}

function New-Command {
    param([string]$Id, [hashtable]$Params)
    return @{ id = $Id; params = $Params }
}

function Get-Result {
    param($Rows, [string]$Id)
    $row = $Rows | Where-Object { $_.id -eq $Id } | Select-Object -Last 1
    if ($row) { return $row.result }
    return $null
}

function Merge-Object {
    param($Base, $Overlay)
    foreach ($property in $Overlay.PSObject.Properties) {
        if ($property.Name -in 'id', 'meta') { continue }
        $old = $Base.PSObject.Properties[$property.Name]
        if ($old -and $old.Value -is [pscustomobject] -and $property.Value -is [pscustomobject]) {
            $null = Merge-Object $old.Value $property.Value
        } elseif ($old) {
            $Base.$($property.Name) = $property.Value
        } else {
            $Base | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
        }
    }
    return $Base
}

function Set-DottedValue {
    param($Object, [string]$Path, $Value)
    $parts = $Path.Split('.')
    $current = $Object
    for ($i = 0; $i -lt $parts.Length - 1; $i++) { $current = $current.($parts[$i]) }
    if (-not $current -or -not $current.PSObject.Properties[$parts[-1]]) { throw "프로필에 없는 키: '$Path'" }
    $current.($parts[-1]) = $Value
}

function Get-Profile {
    param([string]$Name, $Plan)
    if (-not $Name) { $Name = 'default' }
    $basePath = Join-Path $PSScriptRoot 'profiles\_base.json'
    $base = Get-Content -LiteralPath $basePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $templateFolder = Join-Path (Get-TemplatesDir) $Name
    $templatePath = Join-Path $templateFolder 'template.json'
    if (Test-Path -LiteralPath $templatePath) {
        $template = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $base = Merge-Object $base $template
        # 인트로 같은 템플릿 안 파일을 찾는 기준 폴더
        $script:TemplateDir = $templateFolder
    } else {
        $profilePath = Join-Path $PSScriptRoot "profiles\$Name.json"
        if (Test-Path -LiteralPath $profilePath) {
            $base = Merge-Object $base (Get-Content -LiteralPath $profilePath -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
    }
    $localPath = Join-Path $PSScriptRoot "profiles\local\$Name.json"
    if (Test-Path -LiteralPath $localPath) { $base = Merge-Object $base (Get-Content -LiteralPath $localPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    if ($Plan.overrides) {
        foreach ($property in $Plan.overrides.PSObject.Properties) { Set-DottedValue $base $property.Name $property.Value }
    }
    return $base
}

function Get-Probe {
    param([string]$Exe, [string]$File)
    $rows = Invoke-Craft $Exe @('--compact', 'probe', $File.Replace('\', '/'))
    if (@($rows).Count -gt 0) { return @($rows)[0] }
    return $null
}

function Get-InstalledFontNames {
    Add-Type -AssemblyName System.Drawing
    return @((New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object Name)
}

function Get-MediaFiles {
    param([string[]]$Inputs)
    $allowed = @('.mp4', '.mov', '.m4v', '.mkv', '.jpg', '.jpeg', '.png', '.wav', '.m4a', '.mp3', '.aac')
    $files = @()
    foreach ($inputPath in $Inputs) {
        if (Test-Path -LiteralPath $inputPath -PathType Container) {
            $files += Get-ChildItem -LiteralPath $inputPath -File | Where-Object { $allowed -contains $_.Extension.ToLowerInvariant() } | ForEach-Object FullName
        } elseif (Test-Path -LiteralPath $inputPath -PathType Leaf) {
            $files += (Resolve-Path -LiteralPath $inputPath).Path
        }
    }
    return $files
}

function Get-MediaInfo {
    param([string]$Path, [string]$Exe)
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    $kind = if ($extension -in '.mp4', '.mov', '.m4v', '.mkv') { 'video' } elseif ($extension -in '.jpg', '.jpeg', '.png') { 'photo' } else { 'audio' }
    $probe = Get-Probe $Exe $Path
    $taken = (Get-Item -LiteralPath $Path).LastWriteTime
    $lat = $null
    $lon = $null
    if ($kind -eq 'photo') {
        Add-Type -AssemblyName System.Drawing
        $image = [System.Drawing.Image]::FromFile($Path)
        try {
            if ($image.PropertyIdList -contains 0x9003) {
                $raw = [Text.Encoding]::ASCII.GetString($image.GetPropertyItem(0x9003).Value).Trim([char]0)
                $taken = [datetime]::ParseExact($raw, 'yyyy:MM:dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
            }
        } finally { $image.Dispose() }
    }
    return [pscustomobject]@{
        file = $Path; kind = $kind
        seconds = if ($kind -ne 'photo' -and $probe.duration) { [math]::Round([double]$probe.duration / $script:TicksPerSecond, 2) } else { $null }
        width = if ($probe.video) { $probe.video.width } else { $null }
        height = if ($probe.video) { $probe.video.height } else { $null }
        taken = $taken.ToString('yyyy-MM-dd HH:mm:ss')
        lat = $lat; lon = $lon; transcript = $null; srt = $null
    }
}

function New-SrtTime {
    param([double]$Seconds)
    $ms = [int][math]::Round(($Seconds - [math]::Floor($Seconds)) * 1000)
    $span = [timespan]::FromSeconds([math]::Floor($Seconds))
    return ('{0:00}:{1:00}:{2:00},{3:000}' -f [math]::Floor($span.TotalHours), $span.Minutes, $span.Seconds, $ms)
}

# 자막 한 덩이를 PieceCount 조각으로 — 길이를 고르게 하되 꾸밈말 중간(「해 / 뜨는」)보다 어미·조사 뒤에서 끊는다
# 비용 = Σ(조각 길이 − 목표)² + 끊는 자리 벌점(어미·문장부호 0 · 조사 40 · 그 밖 80), 같으면 뒤에서 끊기 (2.1)
function Get-SubtitlePieces {
    param([string[]]$Words, [int]$Limit, [int]$PieceCount)

    $n = $Words.Count
    if ($n -eq 1) { return ,@($Words[0]) }

    $total = ($Words -join ' ').Length
    $first = [Math]::Max($PieceCount, [int][Math]::Ceiling($total / [double]$Limit))

    for ($p = $first; $p -le $n; $p++) {
        $goal = $total / [double]$p
        $dp = @{}
        $dp['0,0'] = @{ Cost = 0.0; Cuts = @() }

        for ($k = 1; $k -le $p; $k++) {
            for ($i = $k; $i -le $n - ($p - $k); $i++) {
                $best = $null
                for ($j = $k - 1; $j -lt $i; $j++) {
                    $prior = $dp["$($k - 1),$j"]
                    if ($null -eq $prior) { continue }

                    $len = ($Words[$j..($i - 1)] -join ' ').Length
                    if ($len -gt $Limit -and $i - $j -gt 1) { continue }

                    $cost = $prior.Cost + ($len - $goal) * ($len - $goal)
                    $cuts = @($prior.Cuts)
                    if ($i -lt $n) {
                        $tail = $Words[$i - 1]
                        if ($tail -notmatch '[,.!?…]$' -and
                            $tail -notmatch '(서|고|며|면|데|니까|지만|요|다|죠|네)$') {
                            if ($tail -match '(은|는|이|가|을|를|에|로|랑|와|과|도|만|까지|부터|하고|에게|께)$') {
                                $cost += 40
                            } else {
                                $cost += 80
                            }
                        }
                        $cuts += $i
                    }

                    $take = $null -eq $best -or $cost -lt $best.Cost - 1e-9
                    if (-not $take -and [Math]::Abs($cost - $best.Cost) -lt 1e-9) {
                        for ($q = 0; $q -lt $cuts.Count; $q++) {
                            if ($cuts[$q] -gt $best.Cuts[$q]) { $take = $true; break }
                            if ($cuts[$q] -lt $best.Cuts[$q]) { break }
                        }
                    }
                    if ($take) { $best = @{ Cost = $cost; Cuts = $cuts } }
                }
                if ($null -ne $best) { $dp["$k,$i"] = $best }
            }
        }

        $answer = $dp["$p,$n"]
        if ($null -ne $answer) {
            $parts = @()
            $start = 0
            foreach ($cut in $answer.Cuts) {
                $parts += ,(($Words[$start..($cut - 1)]) -join ' ')
                $start = $cut
            }
            $parts += ,(($Words[$start..($n - 1)]) -join ' ')
            return ,$parts
        }
    }

    return ,@(($Words -join ' '))
}

function Split-Srt {
    param([string]$Path, [int]$MaxChars, [int]$Lines, [double]$MinSeconds)
    $raw = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
    $limit = $MaxChars * $Lines
    # 아래에서 RemoveAt 을 쓰므로 고정 크기 배열이 아닌 List
    $blocks = New-Object System.Collections.Generic.List[object]
    foreach ($block in ($raw -split "\r?\n\r?\n")) {
        # PowerShell 변수는 대소문자를 안 가려 $Lines(인자)와 다른 이름을 쓴다
        $rows = @($block -split "\r?\n")
        if ($rows.Count -lt 3 -or $rows[1] -notmatch '(\d\d):(\d\d):(\d\d),(\d\d\d) --> (\d\d):(\d\d):(\d\d),(\d\d\d)') { continue }
        $start = [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + [int]$Matches[3] + [int]$Matches[4] / 1000.0
        $end = [int]$Matches[5] * 3600 + [int]$Matches[6] * 60 + [int]$Matches[7] + [int]$Matches[8] / 1000.0
        $text = (($rows[2..($rows.Count - 1)] -join ' ') -replace '\s+', ' ').Trim()
        $words = @($text -split ' ')
        # 한도까지 채우고 남은 꼬리를 떼면 「맑았습니다.」 같은 토막이 생긴다 → 조각 수를 먼저 정해 고르게 나눈다
        $pieceCount = [math]::Max(1, [math]::Ceiling($text.Length / $limit))
        # @( ) 로 감싸면 돌려받은 배열이 한 겹 더 싸여 두 조각이 한 덩이(4줄)가 된다 (실측) — 그대로 받는다
        $parts = Get-SubtitlePieces -Words $words -Limit $limit -PieceCount $pieceCount
        $totalChars = [math]::Max(1, ($parts | ForEach-Object Length | Measure-Object -Sum).Sum)
        $cursor = $start
        foreach ($part in $parts) {
            $duration = ($end - $start) * $part.Length / $totalChars
            $blocks.Add([pscustomobject]@{ start = $cursor; end = ($cursor + $duration); text = $part })
            $cursor += $duration
        }
    }
    for ($i = 0; $i -lt $blocks.Count; $i++) {
        if (($blocks[$i].end - $blocks[$i].start) -lt $MinSeconds) {
            if ($i -gt 0 -and ($blocks[$i - 1].text.Length + 1 + $blocks[$i].text.Length) -le $limit) {
                $blocks[$i - 1].text += " $($blocks[$i].text)"
                $blocks[$i - 1].end = $blocks[$i].end
                $blocks.RemoveAt($i)
                $i--
            } elseif ($i + 1 -lt $blocks.Count -and ($blocks[$i].text.Length + 1 + $blocks[$i + 1].text.Length) -le $limit) {
                $blocks[$i].text += " $($blocks[$i + 1].text)"
                $blocks[$i].end = $blocks[$i + 1].end
                $blocks.RemoveAt($i + 1)
                $i--
            }
        }
    }
    $out = @()
    for ($i = 0; $i -lt $blocks.Count; $i++) {
        $out += [string]($i + 1)
        $out += "$(New-SrtTime $blocks[$i].start) --> $(New-SrtTime $blocks[$i].end)"
        $out += $blocks[$i].text
        $out += ''
    }
    [IO.File]::WriteAllText($Path, ($out -join "`r`n"), $script:Utf8NoBom)
    return ,$blocks
}

function Get-SentenceSpans {
    # 자막 덩이를 문장 끝(. ! ? …)까지 이어 붙여 문장마다 시작·끝·글을 낸다. 문장부호가 하나도 없으면 덩이 하나 = 문장
    param([string]$Path)
    $chunks = @()
    foreach ($block in ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) -split "\r?\n\r?\n")) {
        $rows = @($block -split "\r?\n")
        if ($rows.Count -lt 3 -or $rows[1] -notmatch '(\d\d):(\d\d):(\d\d),(\d\d\d) --> (\d\d):(\d\d):(\d\d),(\d\d\d)') { continue }
        $chunks += [pscustomobject]@{
            start = [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + [int]$Matches[3] + [int]$Matches[4] / 1000.0
            end = [int]$Matches[5] * 3600 + [int]$Matches[6] * 60 + [int]$Matches[7] + [int]$Matches[8] / 1000.0
            text = (($rows[2..($rows.Count - 1)] -join ' ') -replace '\s+', ' ').Trim()
        }
    }
    $stop = '[.!?…。]$'
    if (-not @($chunks | Where-Object { $_.text -match $stop }).Count) { return ,$chunks }
    $sentences = @()
    $current = $null
    foreach ($chunk in $chunks) {
        if ($current) { $current.end = $chunk.end; $current.text += " $($chunk.text)" }
        else { $current = [pscustomobject]@{ start = $chunk.start; end = $chunk.end; text = $chunk.text } }
        if ($chunk.text -match $stop) { $sentences += $current; $current = $null }
    }
    if ($current) { $sentences += $current }
    return ,$sentences
}

function Get-AlignedSeconds {
    # Align[i] = 장면 i 가 보여 줄 문장 번호(1부터, 커지는 순서). 문장 사이 쉼의 가운데에서 장면을 바꾸고,
    # 같은 문장의 장면들은 그 자리를 똑같이 나눈다. 장면이 없는 문장은 앞 장면이 이어서 덮는다
    param($Sentences, [int[]]$Align, [double]$StartAt, [double]$Tail)
    $m = @($Sentences).Count
    $bounds = @($StartAt)
    for ($k = 1; $k -lt $m; $k++) { $bounds += ($Sentences[$k - 1].end + $Sentences[$k].start) / 2 }
    $bounds += $Sentences[$m - 1].end + $Tail
    $seconds = New-Object double[] $Align.Count
    $i = 0
    while ($i -lt $Align.Count) {
        $j = $i
        while ($j + 1 -lt $Align.Count -and $Align[$j + 1] -eq $Align[$i]) { $j++ }
        $from = if ($i -eq 0) { $bounds[0] } else { $bounds[$Align[$i] - 1] }
        $to = if ($j + 1 -lt $Align.Count) { $bounds[$Align[$j + 1] - 1] } else { $bounds[$m] }
        for ($k = $i; $k -le $j; $k++) { $seconds[$k] = ($to - $from) / ($j - $i + 1) }
        $i = $j + 1
    }
    return ,$seconds
}

function New-TtsAudio {
    # 1판 기능 복원 (2판에서 빠졌던 것). Offset = 인트로 길이 — 첫 줄 기본 시작이 인트로 뒤로
    param($Plan, $Profile, [string]$Work, [string]$Exe, [double]$Offset)
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    $koVoice = @($synth.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -eq 'ko-KR' })
    if (-not $koVoice.Count) { Write-Host '한국어 기계 음성이 없어요 — Windows 설정 → 시간 및 언어 → 음성에서 한국어를 추가하세요'; exit 1 }
    $synth.SelectVoice($koVoice[0].VoiceInfo.Name)
    $entries = @()
    $cursor = $Offset + [double]$Profile.narration.start_seconds
    $index = 0
    foreach ($line in $Plan.narration.lines) {
        $index++
        if ($null -ne $line.at) { $start = [double]$line.at }
        elseif ($index -eq 1) { $start = $Offset + [double]$Profile.narration.start_seconds }
        else { $start = $cursor + [double]$Profile.narration.gap_seconds }
        $wav = Join-Path $Work ('nar_{0:D2}.wav' -f $index)
        $synth.SetOutputToWaveFile($wav)
        $synth.Speak([string]$line.text)
        $synth.SetOutputToNull()
        $duration = [double](Get-Probe $Exe $wav).duration / $script:TicksPerSecond
        $entries += [pscustomobject]@{ file = $wav; start = $start; duration = $duration; text = [string]$line.text }
        $cursor = $start + $duration
    }
    $synth.Dispose()
    $srt = Join-Path $Work 'nar.srt'
    $out = @()
    for ($i = 0; $i -lt $entries.Count; $i++) {
        $out += [string]($i + 1)
        $out += "$(New-SrtTime $entries[$i].start) --> $(New-SrtTime ($entries[$i].start + $entries[$i].duration))"
        $out += $entries[$i].text
        $out += ''
    }
    [IO.File]::WriteAllText($srt, ($out -join "`r`n"), $script:Utf8NoBom)
    $null = Split-Srt $srt $Profile.subtitles.max_chars $Profile.subtitles.lines $Profile.subtitles.min_seconds
    return @{ entries = $entries; srt = $srt }
}

function Invoke-Transcribe {
    param([string]$File, [string]$OutputDir, $Profile)
    $ffmpeg = Get-ToolPath 'ffmpeg'
    $whisper = Get-ToolPath 'whisper-cli'
    if (-not $ffmpeg -or -not $whisper) {
        Write-Host '받아쓰기 도구가 없어요 — vc.cmd setup 으로 설치하세요'
        exit 1
    }
    $modelName = [string]$Profile.transcribe.model
    $modelDir = Join-Path (Split-Path $whisper -Parent) 'models'
    if ($modelName -eq 'auto') {
        $models = @(Get-ChildItem -LiteralPath $modelDir -Filter '*.bin' -File)
        $model = $models | Where-Object Name -like '*large-v3-turbo*' | Select-Object -First 1
        if (-not $model) { $model = $models | Where-Object Name -like '*small*' | Select-Object -First 1 }
        if (-not $model) { $model = $models | Where-Object Name -like '*base*' | Select-Object -First 1 }
        if (-not $model) { $model = $models | Select-Object -First 1 }
        if ($model) { $modelName = $model.Name }
    }
    $modelPath = Join-Path $modelDir $modelName
    if (-not (Test-Path -LiteralPath $modelPath)) {
        Write-Host '받아쓰기 모델이 없어요 — vc.cmd setup 으로 설치하세요'
        exit 1
    }
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $stem = [IO.Path]::GetFileNameWithoutExtension($File)
    $wav = Join-Path $OutputDir "$stem`_16k.wav"
    $rawBase = Join-Path $OutputDir "$stem`_raw"
    $srt = Join-Path $OutputDir "$stem.srt"
    $txt = Join-Path $OutputDir "$stem.txt"
    $rawSrt = "$rawBase.srt"
    # 받아쓰기는 느리다(CPU 에서 녹음 길이의 1~4배). 녹음이 그대로면 원본 결과를 다시 쓰고, 템플릿마다 다른 자막 길이는 아래 Split-Srt 가 맡는다
    if (-not (Test-Path -LiteralPath $rawSrt) -or (Get-Item -LiteralPath $rawSrt).LastWriteTime -lt (Get-Item -LiteralPath $File).LastWriteTime) {
        $null = Invoke-Craft $ffmpeg @('-hide_banner', '-loglevel', 'error', '-y', '-i', $File, '-ar', '16000', '-ac', '1', $wav)
        $null = Invoke-Craft $whisper @('-m', $modelPath, '-f', $wav, '-l', [string]$Profile.transcribe.language, '-osrt', '-of', $rawBase, '-np')
        Remove-Item -LiteralPath $wav -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -LiteralPath $rawSrt)) {
        Write-Host '받아쓰기 결과를 만들지 못했어요'
        exit 1
    }
    Copy-Item -LiteralPath $rawSrt -Destination $srt -Force
    $blocks = Split-Srt $srt $Profile.subtitles.max_chars $Profile.subtitles.lines $Profile.subtitles.min_seconds
    $text = (@($blocks | ForEach-Object text) -join ' ')
    [IO.File]::WriteAllText($txt, $text, $script:Utf8NoBom)
    $probe = Get-Probe (Get-CraftPath 'filmcraft') $File
    $seconds = if ($probe.duration) { [math]::Round([double]$probe.duration / $script:TicksPerSecond, 2) } else { $null }
    Write-Output (ConvertTo-Json -InputObject ([ordered]@{ srt = $srt; txt = $txt; seconds = $seconds; text = $text.Substring(0, [math]::Min(400, $text.Length)) }) -Compress)
}

function Invoke-Sheet {
    param([string[]]$Inputs, [string]$OutputDir, [string]$TemplateId, [switch]$SkipTranscribe)
    $exe = Get-CraftPath 'filmcraft'
    if (-not $exe) { Write-Host 'FilmCraft 가 없어요 — vc.cmd setup 으로 설치하세요'; exit 1 }
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $work = Join-Path $OutputDir '_vc_work\sheet'
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Add-Type -AssemblyName System.Drawing
    $media = @(Get-MediaFiles $Inputs | ForEach-Object { Get-MediaInfo $_ $exe } | Sort-Object taken)
    if (-not @($media | Where-Object kind -in 'photo', 'video').Count) {
        Write-Host "사진·영상이 없어요: $($Inputs[0])"
        exit 1
    }
    $profilePlan = [pscustomobject]@{}
    $profile = Get-Profile $TemplateId $profilePlan
    foreach ($item in $media | Where-Object kind -eq 'audio') {
        # 배경음악 파일은 받아쓰지 않는다 (말이 없고 시간만 든다)
        if (-not $SkipTranscribe -and [IO.Path]::GetFileName($item.file) -notmatch 'bgm|music|음악') {
            $result = Invoke-Transcribe $item.file $OutputDir $profile | ConvertFrom-Json
            $item.transcript = $result.text
            $item.srt = $result.srt
        }
    }
    $list = @($media | ForEach-Object {
        [pscustomobject]@{ index = $_.index; file = $_.file; kind = $_.kind; seconds = $_.seconds; width = $_.width; height = $_.height; taken = $_.taken; lat = $_.lat; lon = $_.lon; transcript = $_.transcript; srt = $_.srt }
    })
    $json = if ($list.Count) { ConvertTo-Json -InputObject $list -Depth 8 } else { '[]' }
    Write-JsonLines (Join-Path $OutputDir 'media.json') @($json)
    $thumbs = @()
    for ($i = 0; $i -lt $media.Count; $i++) { $media[$i] | Add-Member -NotePropertyName index -NotePropertyValue ($i + 1) }
    foreach ($item in $media) {
        $itemThumbs = @()
        if ($item.kind -eq 'photo') {
            $img = [System.Drawing.Image]::FromFile($item.file)
            $h = [int][math]::Max(1, [math]::Round($img.Height * 240.0 / $img.Width))
            $bmp = New-Object System.Drawing.Bitmap(240, $h)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.DrawImage($img, 0, 0, 240, $h)
            $png = Join-Path $work "photo_$($item.index).png"
            $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
            $g.Dispose(); $bmp.Dispose(); $img.Dispose()
            $itemThumbs += $png
        } elseif ($item.kind -eq 'video') {
            $project = Join-Path $work "sheet_$($item.index).fcproj"
            $imp = Invoke-Run $exe $project $work "sheet_import_$($item.index)" @((New-Command 'file.import' @{ paths = @($item.file.Replace('\', '/')) })) -NewProject
            $mediaId = (Get-Result $imp 'file.import').items[0]
            $null = Invoke-Run $exe $project $work "sheet_seq_$($item.index)" @((New-Command 'file.newSequenceFromClip' @{ items = @($mediaId) }))
            $thumbScale = [math]::Round(240.0 / [double]$item.width, 4)
            foreach ($percent in @(10, 35, 60, 85)) {
                $png = Join-Path $work ("sheet_$($item.index)_$percent.png")
                $seconds = [double]$item.seconds * $percent / 100
                $null = Invoke-Craft $exe @('--project', $project.Replace('\', '/'), '--compact', 'render', '--seconds', "$seconds", '--scale', "$thumbScale", '--out', $png.Replace('\', '/'))
                $itemThumbs += $png
            }
        }
        $thumbs += ,@{ item = $item; paths = $itemThumbs }
    }
    $pages = [math]::Ceiling($media.Count / 12.0)
    for ($page = 0; $page -lt $pages; $page++) {
        $rows = @()
        for ($i = $page * 12; $i -lt [math]::Min($media.Count, ($page + 1) * 12); $i++) {
            $entry = $thumbs[$i]
            $label = "#$($entry.item.index) $($entry.item.kind)"
            if ($entry.item.kind -eq 'video') { $label += " $($entry.item.seconds)s`n10·35·60·85%" }
            $labelBmp = New-Object System.Drawing.Bitmap(220, 140)
            $g = [System.Drawing.Graphics]::FromImage($labelBmp)
            $g.Clear([System.Drawing.Color]::White)
            $g.DrawString($label, [System.Drawing.Font]::new('Malgun Gothic', 11), [System.Drawing.Brushes]::Black, 4, 4)
            $g.Dispose()
            $labelPath = Join-Path $work "label_$($entry.item.index).png"
            $labelBmp.Save($labelPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $labelBmp.Dispose()
            $rows += ,(@($labelPath) + $entry.paths)
        }
        $rowHeights = @()
        $width = 220
        foreach ($row in $rows) {
            $rowWidth = 0; $rowHeight = 140
            foreach ($p in $row) {
                $im = [System.Drawing.Image]::FromFile($p)
                $rowWidth += $im.Width; $rowHeight = [math]::Max($rowHeight, $im.Height); $im.Dispose()
            }
            $width = [math]::Max($width, $rowWidth)
            $rowHeights += $rowHeight
        }
        $height = ($rowHeights | Measure-Object -Sum).Sum
        $sheet = New-Object System.Drawing.Bitmap([int]$width, [int]$height)
        $g = [System.Drawing.Graphics]::FromImage($sheet)
        $g.Clear([System.Drawing.Color]::White)
        $y = 0
        for ($r = 0; $r -lt $rows.Count; $r++) {
            $x = 0
            foreach ($p in $rows[$r]) {
                $im = [System.Drawing.Image]::FromFile($p)
                $g.DrawImage($im, $x, $y, $im.Width, $im.Height)
                $x += $im.Width
                $im.Dispose()
            }
            $y += $rowHeights[$r]
        }
        $sheet.Save((Join-Path $OutputDir "sheet_$($page + 1).png"), [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $sheet.Dispose()
    }
    Remove-Item -LiteralPath $work -Recurse -Force
    foreach ($item in $media) { Write-Output ("#{0} {1} {2} {3}" -f $item.index, $item.kind, $item.seconds, $item.file) }
}

function Invoke-Build {
    # Preview·Final 을 인자로 받는다 — 없으면 스크립트 단 값(auto 때는 false)을 읽어 auto 초안이 원본 크기로 구워졌다
    param([string]$PlanFile, [switch]$Preview, [switch]$Final)
    $plan = Get-Content -LiteralPath $PlanFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $templateId = if ($plan.template) { [string]$plan.template } elseif ($plan.profile) { [string]$plan.profile } else { 'default' }
    $profile = Get-Profile $templateId $plan
    $script:TemplateDir = Join-Path (Get-TemplatesDir) $templateId
    $exe = Get-CraftPath 'filmcraft'
    if (-not $exe) { Write-Host 'FilmCraft 가 없어요 — vc.cmd setup 으로 설치하세요'; exit 1 }
    $output = [IO.Path]::GetFullPath([string]$plan.output)
    $outDir = Split-Path $output -Parent
    $baseName = [IO.Path]::GetFileNameWithoutExtension($output)
    $work = Join-Path $outDir "_vc_work\$baseName"
    New-Item -ItemType Directory -Force -Path $work | Out-Null

    $introFile = $null
    $introSeconds = 0.0
    if ($profile.intro -and $profile.intro.template) {
        $introTemplate = Join-Path $script:TemplateDir ([string]$profile.intro.template)
        $effectcraft = Get-CraftPath 'effectcraft'
        if ((Test-Path -LiteralPath $introTemplate) -and $effectcraft) {
            $values = @{}
            # 세로 인트로는 한 줄에 5자 남짓 — 넘치면 화면 밖으로 잘리므로(실측) 띄어쓰기에서 줄을 바꾼다
            $titleText = [string]$plan.title
            if ($profile.intro.wrap) {
                $wrapLines = @()
                $current = ''
                foreach ($word in ($titleText -split ' ')) {
                    $joined = if ($current) { "$current $word" } else { $word }
                    if ($current -and $joined.Length -gt [int]$profile.intro.wrap) { $wrapLines += $current; $current = $word } else { $current = $joined }
                }
                if ($current) { $wrapLines += $current }
                # 3줄부터는 인트로 상자 밖으로 넘친다 (실측: 「11월 8일 바닷가 하루」 → 4줄)
                if ($wrapLines.Count -gt 2) { $script:Warnings.Add("인트로 제목이 $($wrapLines.Count)줄이라 넘쳐요 — 띄어쓰기 기준 한 줄 $($profile.intro.wrap)자, 2줄 이내로 짧게") }
                $titleText = $wrapLines -join "`n"
            }
            foreach ($p in $profile.intro.values.PSObject.Properties) {
                $value = [string]$p.Value
                $value = $value.Replace('{title}', $titleText)
                $value = $value.Replace('{date}', [string]$plan.date)
                $values[$p.Name] = $value
            }
            $valuesFile = Join-Path $work 'intro_values.json'
            [IO.File]::WriteAllText($valuesFile, (ConvertTo-Json -InputObject $values -Depth 10), $script:Utf8NoBom)
            $introFile = Join-Path $work 'intro.mp4'
            # 진행 문구가 표준오류로 나와 Stop 에서 멈추므로 Invoke-Craft 로 부른다
            $null = Invoke-Craft $effectcraft @('render', '--template', $introTemplate, '--values', $valuesFile, '--out', $introFile, '--format', 'h264')
            if (-not (Test-Path -LiteralPath $introFile)) { $script:Warnings.Add('인트로를 만들지 못해 건너뜁니다'); $introFile = $null }
            $introSeconds = if ($introFile -and $profile.intro.seconds) { [double]$profile.intro.seconds } else { 0.0 }
        } else { $script:Warnings.Add('인트로 템플릿 또는 EffectCraft가 없어 인트로를 건너뜁니다') }
    }

    $narration = $null
    if ($plan.narration.mode -eq 'tts') { $narration = New-TtsAudio $plan $profile $work $exe $introSeconds }
    $ownSrt = $null
    if ($plan.narration.mode -eq 'own' -and $profile.subtitles.enabled) {
        # 자막 원본: AI 가 고친 자막(captions.srt — 녹음 기준 시각)이 있으면 그것, 없으면 받아쓰기 (결과 폴더에 남겨 재사용)
        $sourceSrt = if ($plan.captions.srt) { [string]$plan.captions.srt } else { (Invoke-Transcribe ([string]$plan.narration.file) $outDir $profile | ConvertFrom-Json).srt }
        $ownSrt = Join-Path $work 'own.srt'
        $at = if ($null -ne $plan.narration.at) { [double]$plan.narration.at } else { $introSeconds }
        $raw = [IO.File]::ReadAllText($sourceSrt, [Text.Encoding]::UTF8)
        $shifted = [regex]::Replace($raw, '(\d\d):(\d\d):(\d\d),(\d\d\d)', [Text.RegularExpressions.MatchEvaluator]{
            param($m) New-SrtTime ([int]$m.Groups[1].Value * 3600 + [int]$m.Groups[2].Value * 60 + [int]$m.Groups[3].Value + [int]$m.Groups[4].Value / 1000.0 + $at)
        })
        [IO.File]::WriteAllText($ownSrt, $shifted, $script:Utf8NoBom)
    }

    # 문장 맞추기: plan.align = 장면마다 보여 줄 문장 번호. 어느 장면이 어느 말인지는 AI 가 장면 모음을 보고 정하고, 초 계산은 여기서
    $syncSrt = if ($ownSrt) { $ownSrt } elseif ($narration) { $narration.srt } else { $null }
    $sentences = if ($syncSrt) { Get-SentenceSpans $syncSrt } else { @() }
    $alignSeconds = $null
    if ($plan.align) {
        $align = @($plan.align | ForEach-Object { [int]$_ })
        $sceneCount = @($plan.timeline).Count
        $valid = $sentences.Count -gt 0 -and $align.Count -eq $sceneCount
        for ($i = 0; $valid -and $i -lt $align.Count; $i++) {
            if ($align[$i] -lt 1 -or $align[$i] -gt $sentences.Count -or ($i -gt 0 -and $align[$i] -lt $align[$i - 1])) { $valid = $false }
        }
        if ($valid) {
            $tail = if ($null -ne $plan.tail_seconds) { [double]$plan.tail_seconds } else { 1.0 }
            $alignSeconds = Get-AlignedSeconds $sentences $align $introSeconds $tail
        } else { $script:Warnings.Add("align 은 장면 수($sceneCount)만큼, 1~$($sentences.Count) 사이 숫자를 커지는 순서로 써야 해요 — 무시하고 장면 길이를 그대로 씁니다") }
    }

    # 사진 일부만 쓰기: crop = [왼쪽, 위, 너비, 높이] (사진 크기 대비 0~1). 원본은 두고 작업 폴더에 잘라낸 PNG 사본을 쓴다
    $mediaPaths = @()
    foreach ($entry in $plan.timeline) {
        $mediaPath = [string]$entry.media
        if ($entry.crop -and $mediaPath -match '\.(jpg|jpeg|png)$') {
            Add-Type -AssemblyName System.Drawing
            $box = @($entry.crop | ForEach-Object { [double]$_ })
            $source = [System.Drawing.Image]::FromFile($mediaPath)
            $rect = New-Object System.Drawing.Rectangle ([int]($source.Width * $box[0])), ([int]($source.Height * $box[1])), ([int]($source.Width * $box[2])), ([int]($source.Height * $box[3]))
            $cropped = New-Object System.Drawing.Bitmap($rect.Width, $rect.Height)
            $pen = [System.Drawing.Graphics]::FromImage($cropped)
            $pen.DrawImage($source, (New-Object System.Drawing.Rectangle 0, 0, $rect.Width, $rect.Height), $rect, [System.Drawing.GraphicsUnit]::Pixel)
            $mediaPath = Join-Path $work ('crop_{0}.png' -f ($mediaPaths.Count + 1))
            $cropped.Save($mediaPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $pen.Dispose(); $cropped.Dispose(); $source.Dispose()
        }
        $mediaPaths += $mediaPath
    }

    # import 순서(인트로 → 장면 → 내레이션 → BGM)가 아래 item 대응 순서다
    $allPaths = @()
    if ($introFile) { $allPaths += $introFile }
    $allPaths += $mediaPaths
    if ($narration) { $allPaths += @($narration.entries | ForEach-Object file) }
    if ($plan.narration.mode -eq 'own') { $allPaths += [string]$plan.narration.file }
    if ($plan.bgm) { $allPaths += [string]$plan.bgm.file }
    $project = Join-Path $work "$baseName.fcproj"
    $newSeq = New-Command 'file.newSequence' @{ name = $baseName; width = [int]$profile.video.width; height = [int]$profile.video.height; fps = [int]$profile.video.fps; video = 3; audio = 3 }
    $import = New-Command 'file.import' @{ paths = @($allPaths | ForEach-Object { ([string]$_).Replace('\', '/') }) }
    $a = Invoke-Run $exe $project $work 'A' @($newSeq, $import) -NewProject
    $imported = @(Get-Result $a 'file.import').items
    $cursor = 0
    $introItem = $null
    if ($introFile) { $introItem = $imported[$cursor]; $cursor++ }
    $timelineItems = @()
    foreach ($entry in $plan.timeline) {
        $isPhoto = [string]$entry.media -match '\.(jpg|jpeg|png)$'
        $audioType = if ($isPhoto) { 'none' } elseif ($entry.audio) { [string]$entry.audio } else { [string]$profile.audio.clip_audio }
        $timelineItems += [pscustomobject]@{ plan = $entry; item = $imported[$cursor]; isPhoto = $isPhoto; audioType = $audioType; start = 0.0; duration = 0.0; inPoint = 0.0; placeLine = 0; fillLine = 0; videoClip = $null; audioClip = $null; scale = 100.0 }
        $cursor++
    }
    $narrItems = @()
    if ($narration) {
        foreach ($e in $narration.entries) { $narrItems += [pscustomobject]@{ item = $imported[$cursor]; start = $e.start; placeLine = 0; clip = $null }; $cursor++ }
    }
    if ($plan.narration.mode -eq 'own') {
        $narrAt = if ($null -ne $plan.narration.at) { [double]$plan.narration.at } else { $introSeconds }
        $narrItems += [pscustomobject]@{ item = $imported[$cursor]; start = $narrAt; placeLine = 0; clip = $null }
        $cursor++
    }
    $bgmItem = if ($plan.bgm) { $imported[$cursor] } else { $null }
    $start = $introSeconds
    $placeCommands = @()
    if ($introItem) {
        $introStart = if ($null -ne $profile.intro.start) { [double]$profile.intro.start } else { 0.0 }
        # 인트로 영상의 start 지점부터 잘라 타임라인 0초에 놓는다
        $placeCommands += New-Command 'timeline.place' @{ item = $introItem; track = 'V1'; seconds = 0; insert = $false; sourceIn = @{ seconds = $introStart }; duration = @{ seconds = $introSeconds }; audio = $false }
        $placeCommands += New-Command 'clip.fillFrame' @{}
    }
    $carry = 0.0
    $sceneIndex = 0
    foreach ($entry in $timelineItems) {
        $p = $entry.plan
        $inPoint = if ($null -ne $p.in) { [double]$p.in } else { 0.0 }
        if ($alignSeconds) {
            # 영상이 문장 자리만큼 길지 않으면 시작점을 앞으로 당기고, 그래도 모자라면 남는 시간을 다음 장면에 넘긴다 (검은 화면 방지)
            $duration = $alignSeconds[$sceneIndex] + $carry
            $carry = 0.0
            if (-not $entry.isPhoto) {
                $clipSeconds = [double](Get-Probe $exe $p.media).duration / $script:TicksPerSecond
                if ($inPoint + $duration -gt $clipSeconds) { $inPoint = [math]::Max(0.0, $clipSeconds - $duration) }
                if ($duration -gt $clipSeconds) { $carry = $duration - $clipSeconds; $duration = $clipSeconds }
            }
        }
        elseif ($entry.isPhoto) { $duration = if ($p.seconds) { [double]$p.seconds } else { [double]$profile.video.photo_seconds } }
        elseif ($null -ne $p.out) { $duration = [double]$p.out - $inPoint }
        else { $duration = [double](Get-Probe $exe $p.media).duration / $script:TicksPerSecond - $inPoint }
        $entry.start = $start; $entry.duration = $duration; $entry.inPoint = $inPoint
        $start += $duration
        if ($entry.isPhoto) {
            $params = @{ item = $entry.item; track = 'V1'; seconds = $entry.start; insert = $false; duration = @{ seconds = $entry.duration } }
        } else {
            $params = @{ item = $entry.item; track = 'V1'; seconds = $entry.start; insert = $false; sourceIn = @{ seconds = $inPoint }; duration = @{ seconds = $entry.duration } }
            if ($entry.audioType -eq 'none') { $params.audio = $false } else { $params.audioTrack = 'A1' }
        }
        $placeCommands += New-Command 'timeline.place' $params
        $entry.placeLine = $placeCommands.Count
        $placeCommands += New-Command 'clip.fillFrame' @{}
        $entry.fillLine = $placeCommands.Count
        $sceneIndex++
    }
    if ($carry -gt 0.05) { $script:Warnings.Add(("마지막 영상이 짧아 {0:0.0}초 일찍 끝나요 — 사진을 뒤에 두거나 tail_seconds 를 줄이세요" -f $carry)) }
    # stills 가 영상에 실제로 쓰인 구간(align 이면 여기서 정해짐)을 알도록 남긴다
    $usedRows = @($timelineItems | ForEach-Object { [ordered]@{ media = [string]$_.plan.media; in = $_.inPoint; seconds = $_.duration } })
    [IO.File]::WriteAllText((Join-Path $work 'scenes.json'), (ConvertTo-Json -InputObject $usedRows -Depth 4), $script:Utf8NoBom)
    foreach ($entry in $narrItems) {
        $placeCommands += New-Command 'timeline.place' @{ item = $entry.item; track = 'A2'; video = $false; seconds = $entry.start; insert = $false }
        $entry.placeLine = $placeCommands.Count
    }
    $bgmLines = @()
    if ($bgmItem) {
        $bgmSeconds = [double](Get-Probe $exe $plan.bgm.file).duration / $script:TicksPerSecond
        $remaining = $start; $at = 0.0
        while ($remaining -gt 0.01) {
            $length = [math]::Min($remaining, $bgmSeconds)
            $placeCommands += New-Command 'timeline.place' @{ item = $bgmItem; track = 'A3'; video = $false; seconds = $at; insert = $false; duration = @{ seconds = $length } }
            $bgmLines += $placeCommands.Count
            $at += $length; $remaining -= $length
        }
    }
    $b = Invoke-Run $exe $project $work 'B' $placeCommands
    $rowOf = @{}
    foreach ($row in $b) { $rowOf[[int]$row.line] = $row }
    foreach ($entry in $timelineItems) {
        $clips = @($rowOf[$entry.placeLine].result.clips)
        $entry.videoClip = $clips[0]
        if ($clips.Count -gt 1) { $entry.audioClip = $clips[1] }
        $entry.scale = [double]$rowOf[$entry.fillLine].result.clips[0].scale
    }
    if ($introItem) { $introClip = @($rowOf[1].result.clips)[0] }
    foreach ($entry in $narrItems) { $entry.clip = @($rowOf[$entry.placeLine].result.clips)[0] }
    $bgmClips = @($bgmLines | ForEach-Object { @($rowOf[$_].result.clips)[0] })

    $c = @()
    foreach ($entry in $timelineItems) {
        if ($entry.isPhoto) {
            $zoom = if ($entry.plan.zoom) { $entry.plan.zoom } else { $profile.video.photo_zoom }
            $c += New-Command 'effects.toggleAnimation' @{ clip = $entry.videoClip; effect = 'motion'; param = 'scale' }
            $c += New-Command 'effects.setParam' @{ clip = $entry.videoClip; effect = 'motion'; param = 'scale'; value = $entry.scale * [double]$zoom[0]; time = [long]($entry.start * $script:TicksPerSecond) }
            $c += New-Command 'effects.setParam' @{ clip = $entry.videoClip; effect = 'motion'; param = 'scale'; value = $entry.scale * [double]$zoom[1]; time = [long](($entry.start + $entry.duration) * $script:TicksPerSecond) }
        }
    }
    if ($profile.video.color_preset) {
        $c += New-Command 'lumetri.applyPreset' @{ name = [string]$profile.video.color_preset; clips = @($timelineItems | ForEach-Object videoClip) + @($introClip | Where-Object { $_ }) }
    }
    foreach ($entry in $timelineItems) {
        if ($entry.audioClip -and $entry.audioType -in 'ambience', 'dialogue') {
            $c += New-Command 'essentialSound.setType' @{ clips = @($entry.audioClip); type = $entry.audioType }
        }
    }
    if ($narrItems.Count) { $c += New-Command 'essentialSound.setType' @{ clips = @($narrItems | ForEach-Object clip); type = 'dialogue' } }
    if ($narrItems.Count -and $profile.audio.clip_duck_db -ne $null) {
        $ambience = @($timelineItems | Where-Object audioClip | ForEach-Object audioClip)
        if ($ambience.Count) {
            $c += New-Command 'essentialSound.setType' @{ clips = $ambience; type = 'ambience' }
            $c += New-Command 'essentialSound.set' @{ clips = $ambience; values = @{ 'ducking.enabled' = $true; 'ducking.reduceDb' = [double]$profile.audio.clip_duck_db } }
            $c += New-Command 'essentialSound.generateDucking' @{ clips = $ambience }
        }
    }
    if ($bgmClips.Count) {
        $c += New-Command 'essentialSound.setType' @{ clips = $bgmClips; type = 'music' }
        $c += New-Command 'essentialSound.set' @{ clips = $bgmClips; values = @{ 'ducking.enabled' = $true; 'ducking.reduceDb' = [double]$profile.audio.bgm_duck_db } }
        $c += New-Command 'essentialSound.generateDucking' @{ clips = $bgmClips }
        $c += New-Command 'sequence.applyAudioTransition' @{ clip = $bgmClips[-1]; effect = 'exponential_fade'; frames = [int][math]::Round([double]$profile.audio.bgm_fade_out_seconds * [double]$profile.video.fps); edge = 'out' }
    }
    if ($profile.subtitles.enabled) {
        # own 이면 captions.srt 도 녹음 기준 → 위에서 민 own.srt. tts 는 nar.srt. 내레이션이 없으면 captions.srt 그대로(영상 기준)
        $captionFile = if ($ownSrt) { $ownSrt } elseif ($narration) { $narration.srt } else { $plan.captions.srt }
        if ($captionFile) {
            $c += New-Command 'captions.import' @{ path = ([string]$captionFile).Replace('\', '/'); language = 'ko' }
            $style = @{
                track = 'C1'; font = [string]$profile.subtitles.font; fontStyle = [string]$profile.subtitles.font_style
                color = [string]$profile.subtitles.color; outline = [int]$profile.subtitles.outline
                outlineColor = [string]$profile.subtitles.outline_color; background = [bool]$profile.subtitles.background
                anchor = [string]$profile.subtitles.anchor; margin = [double]$profile.subtitles.margin
            }
            if ($null -ne $profile.subtitles.size) { $style.size = [double]$profile.subtitles.size }
            $c += New-Command 'captions.setStyle' $style
        }
    }
    if ($plan.title -and -not $introItem) {
        $c += New-Command 'graphics.newText' @{ text = [string]$plan.title; position = @(([double]$profile.video.width / 2), ([double]$profile.video.height * [double]$profile.title.y_fraction)); size = [int]$profile.title.size; font = [string]$profile.title.font; fontStyle = [string]$profile.title.font_style; seconds = [double]$profile.title.seconds }
    }
    $cResults = Invoke-Run $exe $project $work 'C' $c
    $d = @()
    if ($plan.title -and -not $introItem) {
        $graphic = Get-Result $cResults 'graphics.newText'
        $d += New-Command 'graphics.set' @{ clip = $graphic.clip; layer = 0; props = @{ align = 'center'; fill_color = [string]$profile.title.color } }
        $d += New-Command 'graphics.align' @{ clip = $graphic.clip; layers = @(0); align = 'hcenter'; to = 'frame' }
    }
    $exportPath = $output
    if ($Preview -and -not $Final) { $exportPath = Join-Path $outDir ("$baseName`_preview" + [IO.Path]::GetExtension($output)) }
    $exportParams = @{ path = $exportPath.Replace('\', '/'); preset = [string]$profile.video.export_preset; burnCaptions = [bool]$profile.subtitles.enabled; hardwareEncoding = 'auto'; loudnessLufs = [double]$profile.audio.loudness_lufs; captionSidecar = 'srt' }
    if ($Preview -and -not $Final) { $exportParams.width = [int]($profile.video.width / 2); $exportParams.height = [int]($profile.video.height / 2) }
    $d += New-Command 'file.exportMedia' $exportParams
    $dResults = Invoke-Run $exe $project $work 'D' $d
    $exportResult = Get-Result $dResults 'file.exportMedia'
    $check = Join-Path $outDir "${baseName}_check.png"
    $checkProject = Join-Path $work 'check.fcproj'
    $checkImp = Invoke-Run $exe $checkProject $work 'check_import' @((New-Command 'file.import' @{ paths = @($exportPath.Replace('\', '/')) })) -NewProject
    $checkItem = (Get-Result $checkImp 'file.import').items[0]
    $null = Invoke-Run $exe $checkProject $work 'check_seq' @((New-Command 'file.newSequenceFromClip' @{ items = @($checkItem) }))
    $frames = @()
    # 장면당 폭 약 300px — 미리보기는 절반 크기로 구우므로 실제 내보낸 폭 기준
    $exportWidth = if ($exportParams.width) { [double]$exportParams.width } else { [double]$profile.video.width }
    $scale = [math]::Round(300.0 / $exportWidth, 4)
    if ($introFile) {
        # 인트로 제목이 다 보이는 시점 (실측: 1~1.5초 뒤)
        $png = Join-Path $work 'check_intro.png'
        $null = Invoke-Craft $exe @('--project', $checkProject.Replace('\', '/'), '--compact', 'render', '--seconds', "$([math]::Round($introSeconds * 0.7, 2))", '--scale', "$scale", '--out', $png.Replace('\', '/'))
        $frames += $png
    }
    foreach ($entry in $timelineItems) {
        $png = Join-Path $work ("check_$($frames.Count).png")
        $null = Invoke-Craft $exe @('--project', $checkProject.Replace('\', '/'), '--compact', 'render', '--seconds', "$($entry.start + $entry.duration / 2)", '--scale', "$scale", '--out', $png.Replace('\', '/'))
        $frames += $png
    }
    if ($frames.Count) {
        Add-Type -AssemblyName System.Drawing
        $images = @($frames | ForEach-Object { [System.Drawing.Image]::FromFile($_) })
        $checkWidth = [int](($images | Measure-Object Width -Sum).Sum)
        $checkHeight = [int](($images | Measure-Object Height -Maximum).Maximum)
        $checkBitmap = New-Object System.Drawing.Bitmap($checkWidth, $checkHeight)
        $graphics = [System.Drawing.Graphics]::FromImage($checkBitmap)
        $x = 0
        foreach ($image in $images) { $graphics.DrawImage($image, $x, 0); $x += $image.Width; $image.Dispose() }
        $checkBitmap.Save($check, [System.Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose(); $checkBitmap.Dispose()
    }
    # AI 가 장면·문장 맞춤을 확인하도록 장면 시각과 문장 시각을 함께 낸다 (타임라인 기준 초)
    $sceneRows = @()
    for ($i = 0; $i -lt $timelineItems.Count; $i++) { $sceneRows += [ordered]@{ n = $i + 1; start = [math]::Round($timelineItems[$i].start, 2); seconds = [math]::Round($timelineItems[$i].duration, 2) } }
    $sentenceRows = @()
    for ($i = 0; $i -lt $sentences.Count; $i++) { $sentenceRows += [ordered]@{ k = $i + 1; at = [math]::Round($sentences[$i].start, 1); text = $sentences[$i].text } }
    $summary = [ordered]@{ output = $exportPath; seconds_total = [math]::Round($start, 2); check = $check; scenes = $sceneRows; sentences = $sentenceRows; warnings = @($script:Warnings) }
    Write-Output (ConvertTo-Json -InputObject $summary -Compress -Depth 6)
}

function Invoke-Auto {
    param([string]$Folder)
    $outDir = if ($Out) { $Out } else { Join-Path $Folder '완성' }
    Invoke-Sheet @($Folder) $outDir $Template -SkipTranscribe:$NoTranscribe
    $exe = Get-CraftPath 'filmcraft'
    $profile = Get-Profile $Template ([pscustomobject]@{})
    # sheet 가 쓴 media.json 을 그대로 쓴다 (받아쓴 글이 들어 있다)
    # PS 5.1 의 ConvertFrom-Json 은 배열을 한 덩이로 내보내므로 변수에 먼저 받아야 항목별로 나뉜다
    $mediaRaw = Get-Content -LiteralPath (Join-Path $outDir 'media.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $media = @($mediaRaw | ForEach-Object { $_ })
    $visuals = @($media | Where-Object kind -in 'video', 'photo')
    $audio = @($media | Where-Object kind -eq 'audio')
    $narration = $null
    $narrationSeconds = 0.0
    $voices = @($audio | Where-Object { [IO.Path]::GetFileName($_.file) -notmatch 'bgm|music|음악' })
    $candidate = $voices | Where-Object { [IO.Path]::GetFileName($_.file) -match '소감|memo|녹음|voice|narration' } | Select-Object -First 1
    if (-not $candidate -and $voices.Count -eq 1) { $candidate = $voices[0] }
    if ($candidate) {
        # at 을 비워 두면 build 가 인트로 뒤에 놓는다
        $narration = @{ mode = 'own'; file = $candidate.file }
        $narrationSeconds = [double]$candidate.seconds
    }
    $sentences = if ($candidate -and $candidate.srt) { Get-SentenceSpans ([string]$candidate.srt) } else { @() }
    # media.json 의 taken 은 「yyyy-MM-dd HH:mm:ss」 — 지역 설정에 기대지 않고 고정 형식으로 읽는다
    $takenTimes = @($visuals | ForEach-Object { if ($_.taken -is [datetime]) { $_.taken } else { [datetime]::ParseExact([string]$_.taken, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture) } })
    $firstDate = $takenTimes[0]
    $timeline = @()
    $flip = $false
    foreach ($item in $visuals) {
        if ($item.kind -eq 'photo') {
            $z = [double]$profile.video.photo_zoom[1]
            $zoom = if ($flip) { @($z, 1.0) } else { @(1.0, $z) }
            $flip = -not $flip
            $timeline += @{ media = $item.file; seconds = [double]$profile.video.photo_seconds; zoom = $zoom }
        } else {
            $d = [math]::Min([double]$item.seconds - 0.5, [double]$profile.video.clip_seconds)
            $inside = [math]::Max(0, ([double]$item.seconds - $d) / 2)
            # 영상 소리는 끄지 않는다 — 내레이션 때 현장음 줄이기(audio.clip_duck_db)가 맡는다
            $timeline += @{ media = $item.file; in = $inside; out = ($inside + $d) }
        }
    }
    # 길이 맞추기: 영상이 내레이션보다 짧으면 내레이션이 잘린다 → 사진을 늘린다 (한 장 최대 6초, 모자라면 마지막 사진)
    $sceneLength = { param($s) if ($null -ne $s.seconds) { [double]$s.seconds } else { [double]$s.out - [double]$s.in } }
    $introSeconds = 0.0
    if ($profile.intro -and $profile.intro.template -and (Test-Path -LiteralPath (Join-Path $script:TemplateDir ([string]$profile.intro.template)))) { $introSeconds = [double]$profile.intro.seconds }
    $photos = @($timeline | Where-Object { $null -ne $_.seconds })
    $align = $null
    if ($sentences.Count) {
        # 받아쓴 문장이 있으면 장면 길이는 build 가 문장 시각으로 정한다 (align). 기본 묶음 = 찍은 시각 간격이 가장 짧은 곳부터
        # 같은 문장으로 묶어 문장 수에 맞춘다. 말한 순서 = 찍은 순서로 보지만 틀릴 수 있어 AI 가 장면 모음과 문장을 보고 고친다
        $sceneTotal = $visuals.Count
        $sentenceTotal = $sentences.Count
        $align = @()
        if ($sceneTotal -ge $sentenceTotal) {
            $gaps = @(for ($i = 0; $i -lt $sceneTotal - 1; $i++) { [pscustomobject]@{ i = $i; gap = ($takenTimes[$i + 1] - $takenTimes[$i]).TotalSeconds } })
            $joined = @($gaps | Sort-Object gap, i | Select-Object -First ($sceneTotal - $sentenceTotal) | ForEach-Object i)
            $number = 1
            for ($i = 0; $i -lt $sceneTotal; $i++) { if ($i -gt 0 -and $joined -notcontains ($i - 1)) { $number++ }; $align += $number }
        } else {
            for ($i = 0; $i -lt $sceneTotal; $i++) { $align += [int][math]::Floor($i * $sentenceTotal / $sceneTotal) + 1 }
        }
        foreach ($s in $timeline) { $s.Remove('seconds'); $s.Remove('out') }
    } elseif ($narrationSeconds -gt 0) {
        $targetSeconds = $introSeconds + $narrationSeconds + 1.0
        $sum = $introSeconds + (($timeline | ForEach-Object { & $sceneLength $_ }) | Measure-Object -Sum).Sum
        if ($sum -lt $targetSeconds -and $photos.Count) {
            $extra = ($targetSeconds - $sum) / $photos.Count
            foreach ($ph in $photos) { $ph.seconds = [math]::Round([math]::Min(6.0, $ph.seconds + $extra), 2) }
            $sum = $introSeconds + (($timeline | ForEach-Object { & $sceneLength $_ }) | Measure-Object -Sum).Sum
            if ($sum -lt $targetSeconds) { $photos[-1].seconds = [math]::Round($photos[-1].seconds + ($targetSeconds - $sum), 2) }
        }
    }
    # 최대 길이: 넘으면 모든 장면을 같은 비율로 줄인다 (장면당 최소 1.5초). align 이면 길이는 내레이션이 정한다
    $sum = if ($align) { 0.0 } else { (($timeline | ForEach-Object { & $sceneLength $_ }) | Measure-Object -Sum).Sum }
    $room = [double]$profile.video.max_seconds - $introSeconds
    if ($sum -gt $room) {
        $factor = $room / $sum
        foreach ($s in $timeline) {
            if ($null -ne $s.seconds) { $s.seconds = [math]::Round([math]::Max(1.5, $s.seconds * $factor), 2) }
            else { $s.out = [math]::Round($s.in + [math]::Max(1.5, ($s.out - $s.in) * $factor), 2) }
        }
    }
    $bgmFile = $Bgm
    if (-not $bgmFile) { $music = $audio | Where-Object { [IO.Path]::GetFileName($_.file) -match 'bgm|music|음악' } | Select-Object -First 1; if ($music) { $bgmFile = $music.file } }
    if (-not $bgmFile -and $profile.audio.bgm) {
        $candidateBgm = Join-Path $script:TemplateDir ([string]$profile.audio.bgm)
        if (Test-Path -LiteralPath $candidateBgm) { $bgmFile = $candidateBgm }
    }
    $titleText = if ($Title) { $Title } else { [IO.Path]::GetFileName($Folder.TrimEnd('\')) }
    $fileName = ($titleText -replace '[\\/:*?"<>|]', '_').Trim()
    if (-not $fileName) { $fileName = 'video' }
    $plan = [ordered]@{
        template = if ($Template) { $Template } else { 'default' }
        title = $titleText
        date = $firstDate.ToString('yyyy. M. d')
        output = Join-Path $outDir "$fileName.mp4"
        timeline = $timeline
        narration = $narration
        bgm = if ($bgmFile) { @{ file = $bgmFile } } else { $null }
    }
    if ($align) { $plan.align = $align; $plan.tail_seconds = 1.0 }
    $planPath = Join-Path $outDir 'plan.json'
    [IO.File]::WriteAllText($planPath, (ConvertTo-Json -InputObject $plan -Depth 20), $script:Utf8NoBom)
    # build 의 요약(미리보기 경로·장면 실제 길이·문장 시각·경고)을 받아 AI 용 한 줄로 합친다
    $built = @(Invoke-Build $planPath -Preview:$(-not $Final) -Final:$Final)[-1] | ConvertFrom-Json
    $builtScenes = @($built.scenes)
    $scenes = @()
    for ($i = 0; $i -lt $timeline.Count; $i++) {
        $scenes += [ordered]@{ n = $i + 1; file = [IO.Path]::GetFileName($timeline[$i].media); kind = $visuals[$i].kind; taken = $takenTimes[$i].ToString('HH:mm'); sentence = if ($align) { $align[$i] } else { $null }; seconds = $builtScenes[$i].seconds }
    }
    $summary = [ordered]@{ plan = $planPath; output = $built.output; check = $built.check; seconds_total = $built.seconds_total; intro_seconds = $introSeconds; narration_seconds = $narrationSeconds; scenes = $scenes; sentences = @($built.sentences); warnings = @($built.warnings) }
    Write-Output (ConvertTo-Json -InputObject $summary -Compress -Depth 8)
}

function Invoke-Stills {
    # 블로그용 영상 한 컷: 계획서면 영상에 실제로 쓰인 구간의 가운데, 폴더면 영상 가운데를 원본 화질 JPG 로
    param([string]$Source, [string]$OutputDir)
    $ffmpeg = Get-ToolPath 'ffmpeg'
    $exe = Get-CraftPath 'filmcraft'
    if (-not $ffmpeg -or -not $exe) { Write-Host 'ffmpeg 또는 FilmCraft 가 없어요 — vc.cmd setup 으로 설치하세요'; exit 1 }
    $picks = @()
    if ($Source -match '\.json$') {
        $plan = Get-Content -LiteralPath $Source -Raw -Encoding UTF8 | ConvertFrom-Json
        $planOutput = [IO.Path]::GetFullPath([string]$plan.output)
        if (-not $OutputDir) { $OutputDir = Join-Path (Split-Path $planOutput -Parent) 'stills' }
        # build 가 남긴 실제 구간이 있으면 그것 (align 이면 in·길이가 build 에서 정해진다)
        $usedFile = Join-Path (Split-Path $planOutput -Parent) ("_vc_work\{0}\scenes.json" -f [IO.Path]::GetFileNameWithoutExtension($planOutput))
        $used = if (Test-Path -LiteralPath $usedFile) { Get-Content -LiteralPath $usedFile -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
        $timelineRows = if ($used) { @($used | ForEach-Object { [pscustomobject]@{ media = $_.media; in = $_.in; out = [double]$_.in + [double]$_.seconds } }) } else { @($plan.timeline) }
        foreach ($entry in $timelineRows) {
            if ([string]$entry.media -notmatch '\.(mp4|mov|m4v|mkv)$') { continue }
            $inPoint = if ($null -ne $entry.in) { [double]$entry.in } else { 0.0 }
            $length = if ($null -ne $entry.out) { [double]$entry.out - $inPoint } else { [math]::Min([double](Get-Probe $exe $entry.media).duration / $script:TicksPerSecond - $inPoint, 4.0) }
            $picks += [pscustomobject]@{ file = [string]$entry.media; at = $inPoint + $length / 2 }
        }
    } else {
        if (-not $OutputDir) { $OutputDir = Join-Path $Source '완성\stills' }
        foreach ($file in @(Get-MediaFiles @($Source) | Where-Object { $_ -match '\.(mp4|mov|m4v|mkv)$' })) {
            $picks += [pscustomobject]@{ file = $file; at = [double](Get-Probe $exe $file).duration / $script:TicksPerSecond / 2 }
        }
    }
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $rows = @()
    foreach ($pick in $picks) {
        $at = [math]::Round($pick.at, 1)
        $image = Join-Path $OutputDir ('{0}_{1}s.jpg' -f [IO.Path]::GetFileNameWithoutExtension($pick.file), $at.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture))
        $null = Invoke-Craft $ffmpeg @('-hide_banner', '-loglevel', 'error', '-y', '-ss', $at.ToString([Globalization.CultureInfo]::InvariantCulture), '-i', $pick.file, '-frames:v', '1', '-q:v', '2', $image)
        if (Test-Path -LiteralPath $image) { $rows += [ordered]@{ video = [IO.Path]::GetFileName($pick.file); seconds = $at; image = $image } }
        else { $script:Warnings.Add("한 컷을 못 뽑았어요: $($pick.file)") }
    }
    Write-Output (ConvertTo-Json -InputObject ([ordered]@{ folder = $OutputDir; stills = $rows; warnings = @($script:Warnings) }) -Compress -Depth 5)
}

function Invoke-Doctor {
    $rows = @()
    foreach ($name in @('filmcraft', 'photocraft', 'lightcraft', 'soundcraft', 'effectcraft')) {
        $path = Get-CraftPath $name
        $version = '없음'
        if ($path) { $v = & $path --version 2>$null; if ($v) { $version = ($v -join ' ') } }
        $rows += [pscustomobject]@{ 도구 = $name; 경로 = if ($path) { $path } else { '없음' }; 버전 = $version }
    }
    $film = Get-CraftPath 'filmcraft'
    # FilmCraft 명령줄판은 받아쓰기 기능 없이 빌드되어 있어(실측) whisper.cpp 모델만 본다
    $models = '없음'
    $whisper = Get-ToolPath 'whisper-cli'
    if ($whisper) {
        $bins = @(Get-ChildItem (Join-Path (Split-Path $whisper -Parent) 'models') -Filter '*.bin' -File -ErrorAction SilentlyContinue | ForEach-Object Name)
        if ($bins.Count) { $models = $bins -join ', ' }
    }
    $templateFiles = @(Get-ChildItem (Get-TemplatesDir) -Filter 'template.json' -File -Recurse -ErrorAction SilentlyContinue)
    $fontNames = Get-InstalledFontNames
    $fontRows = @()
    foreach ($f in @(Get-ChildItem (Join-Path $PSScriptRoot 'profiles') -Filter '*.json' -File -Recurse -ErrorAction SilentlyContinue) + $templateFiles) {
        $p = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($font in @($p.subtitles.font, $p.title.font) | Where-Object { $_ } | Select-Object -Unique) {
            $fontRows += [pscustomobject]@{ 파일 = $f.FullName.Replace($PSScriptRoot + '\', ''); 글꼴 = $font; 설치 = ($fontNames -contains $font) }
        }
    }
    $speech = '없음'
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    if (@($synth.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -eq 'ko-KR' }).Count) { $speech = '있음' }
    $synth.Dispose()
    $extra = @()
    foreach ($name in @('ffmpeg', 'whisper-cli', 'deface', 'yt-dlp')) {
        $path = Get-ToolPath $name
        $extra += [pscustomobject]@{ 도구 = $name; 경로 = if ($path) { $path } else { '없음' } }
    }
    $gpu = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object Name)
    if (-not $gpu.Count) { $gpu = @('없음') }
    $rows | Format-Table -AutoSize
    [pscustomobject]@{ 템플릿 = (@($templateFiles | ForEach-Object { $_.Directory.Name }) -join ', '); 받아쓰기모델 = $models; 한국어음성 = $speech; GPU = ($gpu -join ', ') } | Format-List
    $fontRows | Format-Table -AutoSize
    $extra | Format-Table -AutoSize
    if (-not $film) { Write-Host 'FilmCraft 가 없어요 — vc.cmd setup 으로 설치하세요'; exit 1 }
}

switch ($Command) {
    'doctor' { Invoke-Doctor }
    'sheet' {
        if (-not $Out -or -not $Arguments.Count) { Write-Host 'sheet <파일 또는 폴더>... -Out <폴더> 형식이 필요합니다'; exit 1 }
        Invoke-Sheet $Arguments $Out $Template -SkipTranscribe:$NoTranscribe
    }
    'transcribe' {
        if (-not $Arguments.Count) { Write-Host 'transcribe <소리·영상 파일> 형식이 필요합니다'; exit 1 }
        $profile = Get-Profile $(if ($Template) { $Template } else { 'default' }) ([pscustomobject]@{})
        $target = if ($Out) { $Out } else { Split-Path -Parent ([IO.Path]::GetFullPath($Arguments[0])) }
        Invoke-Transcribe $Arguments[0] $target $profile
    }
    'build' {
        if (-not $Arguments.Count) { Write-Host 'build <plan.json> 형식이 필요합니다'; exit 1 }
        Invoke-Build $Arguments[0] -Preview:$Preview -Final:$Final
    }
    'auto' {
        if (-not $Arguments.Count) { Write-Host 'auto <폴더> 형식이 필요합니다'; exit 1 }
        Invoke-Auto $Arguments[0]
    }
    'stills' {
        if (-not $Arguments.Count) { Write-Host 'stills <plan.json 또는 폴더> [-Out <폴더>] 형식이 필요합니다'; exit 1 }
        Invoke-Stills $Arguments[0] $Out
    }
}