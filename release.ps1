# 관리자용 (스킬 사용자는 쓰지 않는다): SKILL.md 의 판 번호로 태그 → zip + SHA256SUMS.txt → GitHub 릴리스
# 먼저 SKILL.md metadata.version 을 올리고 커밋·푸시한다. -Publish 없이는 만들 것만 보인다. GitHub 로그인은 git 에 저장된 것을 쓴다
param([switch]$Publish)
$ErrorActionPreference = 'Stop'
$skillDir = $PSScriptRoot
$text = [IO.File]::ReadAllText((Join-Path $skillDir 'SKILL.md'), [Text.Encoding]::UTF8)
if ($text -notmatch '(?m)^\s*version:\s*"?([0-9][0-9.]*)"?') { throw 'SKILL.md 에서 version 을 찾지 못했어요' }
$version = $Matches[1]
$tag = "v$version"
$remote = (& git -C $skillDir remote get-url origin)
if ($remote -notmatch 'github\.com[/:]([^/]+/[^/.]+)') { throw "origin 이 GitHub 저장소가 아니에요: $remote" }
$repo = $Matches[1]
if (@(& git -C $skillDir status --porcelain --untracked-files=no).Count) { throw '커밋하지 않은 변경이 있어요 — 먼저 커밋·푸시' }
$previous = @(& git -C $skillDir tag --list 'v*' --sort=-v:refname) | Where-Object { $_ -ne $tag } | Select-Object -First 1
$range = if ($previous) { "$previous..HEAD" } else { 'HEAD' }
$notes = @(& git -C $skillDir log --format='- %s' $range)
Write-Host "저장소 $repo · 태그 $tag · 이전 $previous · 바뀐 것 $($notes.Count) 건"
$notes | ForEach-Object { Write-Host "  $_" }
if (-not $Publish) { Write-Host '내려면: release.ps1 -Publish'; return }

if (-not (& git -C $skillDir tag --list $tag)) {
    & git -C $skillDir tag -a $tag -m "editnado $version"
    & git -C $skillDir push --quiet origin $tag
}
$out = Join-Path ([IO.Path]::GetTempPath()) "editnado-release-$version"
$null = New-Item -ItemType Directory -Force -Path $out
$zipName = "editnado-$version.zip"
$zip = Join-Path $out $zipName
# 태그 기준으로 묶는다 → 개인 파일(profiles/local, 깃 제외 문서)은 들어가지 않는다. 관리자 파일은 .gitattributes export-ignore
& git -C $skillDir archive --format=zip --prefix=editnado/ -o $zip $tag
$sha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
$sums = Join-Path $out 'SHA256SUMS.txt'
[IO.File]::WriteAllText($sums, "$sha  $zipName`n", (New-Object Text.UTF8Encoding $false))

# git 에 저장된 GitHub 로그인 — PowerShell 파이프·표준입력은 맨 앞에 BOM 을 붙여 git 이 「missing protocol」로 거부한다(실측) → BOM 없는 파일로 넘긴다
$request = Join-Path $out 'credential.txt'
[IO.File]::WriteAllText($request, "protocol=https`nhost=github.com`n`n", (New-Object Text.UTF8Encoding $false))
$answer = Join-Path $out 'credential.out'
Start-Process -FilePath (Get-Command git).Source -ArgumentList 'credential', 'fill' -RedirectStandardInput $request -RedirectStandardOutput $answer -NoNewWindow -Wait
$credential = [IO.File]::ReadAllText($answer)
Remove-Item -LiteralPath $request, $answer
if ($credential -notmatch '(?m)^password=(.+)$') { throw 'git 에 저장된 GitHub 로그인이 없어요' }
$headers = @{ Authorization = "token $($Matches[1].Trim())"; 'User-Agent' = 'editnado-release'; Accept = 'application/vnd.github+json' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$body = @{ tag_name = $tag; name = "editnado $version"; body = ($notes -join "`n") } | ConvertTo-Json
$release = Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$repo/releases" -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json'
foreach ($file in @($zip, $sums)) {
    $name = Split-Path $file -Leaf
    $type = if ($name -like '*.zip') { 'application/zip' } else { 'text/plain' }
    $null = Invoke-RestMethod -Method Post -Uri "https://uploads.github.com/repos/$repo/releases/$($release.id)/assets?name=$name" -Headers $headers -InFile $file -ContentType $type
}
Write-Host "릴리스 냄: $($release.html_url) ($zipName · SHA256 $sha)"
