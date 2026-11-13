. (Join-Path $PSScriptRoot 'vc_paths.ps1')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# 스킬 새 판을 받는 저장소 (다른 곳에서 퍼 간 판은 환경변수 VC_SKILL_REPO 로)
$script:SkillRepo = 'bluebabo/editnado'

function Get-ApiJson {
    param([string]$Uri)
    return Invoke-RestMethod -Uri $Uri -Headers @{ 'User-Agent' = 'editnado-setup' } -UseBasicParsing
}

function Get-DownloadedFile {
    param([string]$Uri, [string]$Path, [hashtable]$Headers = @{})
    Invoke-WebRequest -Uri $Uri -OutFile $Path -UseBasicParsing -Headers $Headers
}

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-GitHubAsset {
    param([string]$Repo, [string]$AssetPattern, [switch]$Latest)
    if ($Latest) {
        $releases = @(Get-ApiJson "https://api.github.com/repos/$Repo/releases/latest")
    }
    else {
        $releases = @(Get-ApiJson "https://api.github.com/repos/$Repo/releases?per_page=10")
    }
    foreach ($release in $releases) {
        $asset = @($release.assets | Where-Object { $_.name -like $AssetPattern } | Select-Object -First 1)
        if ($asset.Count -gt 0) {
            return [pscustomobject]@{ Release = $release; Asset = $asset[0] }
        }
    }
    return $null
}

function Get-SizeMb {
    param([Nullable[long]]$Bytes)
    if ($null -eq $Bytes -or $Bytes -le 0) { return '미확인' }
    return [math]::Ceiling($Bytes / 1MB)
}

function Get-InstalledFontNames {
    Add-Type -AssemblyName System.Drawing
    $collection = New-Object System.Drawing.Text.InstalledFontCollection
    try {
        return @($collection.Families | ForEach-Object { $_.Name })
    }
    finally {
        $collection.Dispose()
    }
}

function Get-TemplateIndex {
    param([string]$Index)
    $source = $Index
    if (-not $source) { $source = $env:VC_TEMPLATE_INDEX }
    if (-not $source) { $source = Join-Path (Get-TemplatesDir) 'index.json' }

    if ($source -match '^https://') {
        $response = Invoke-WebRequest -Uri $source -UseBasicParsing -Headers @{ 'User-Agent' = 'editnado-setup' }
        $json = $response.Content | ConvertFrom-Json
    }
    else {
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "목록 파일을 찾을 수 없습니다: $source"
        }
        $json = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $source).Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
    }

    if ($json.format -ne 1 -or $null -eq $json.templates) {
        throw '목록 파일 형식이 올바르지 않습니다.'
    }
    return $json
}

function Get-InstalledTemplates {
    $result = @()
    $dir = Get-TemplatesDir
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return @() }
    foreach ($folder in @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue)) {
        $file = Join-Path $folder.FullName 'template.json'
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        try {
            $data = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) | ConvertFrom-Json
            $result += [pscustomobject]@{
                id = [string]$data.id
                name_ko = [string]$data.meta.name_ko
                description = [string]$data.meta.description
                price = [string]$data.meta.price
                aspect = [string]$data.meta.aspect
                version = [string]$data.meta.version
            }
        }
        catch {
            Write-Host "템플릿 정보를 읽지 못했습니다: $($folder.Name) — $($_.Exception.Message)"
        }
    }
    return @($result)
}

function Format-TemplatePrice {
    param($Price, [string]$Store)
    if ($null -eq $Price -or $Price -eq 'free') { return '무료' }
    if ($Price -is [string]) { return $Price }
    $amount = $Price.amount
    $currency = $Price.currency
    if ($Store) { return "유료 — 구매: $Store ($amount $currency)" }
    return "유료 ($amount $currency)"
}

function Get-TemplateIdFromArchive {
    param([string]$ZipPath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        $roots = @()
        foreach ($entry in $archive.Entries) {
            # Windows .NET 으로 만든 zip 은 경로를 \ 로 적는다 → / 로 바꿔 같은 규칙으로 검사
            $name = $entry.FullName.Replace('\', '/')
            if ($name -match '^/' -or $name -match '^[A-Za-z]:') {
                throw '압축 파일에 허용되지 않는 경로가 있습니다.'
            }
            $parts = @($name.Split('/'))
            if ($parts.Count -lt 2 -or $parts[0] -in @('', '.', '..')) {
                throw '압축 파일의 최상위 폴더를 확인할 수 없습니다.'
            }
            if (@($parts | Where-Object { $_ -eq '..' -or $_ -eq '.' }).Count -gt 0) {
                throw '압축 파일에 허용되지 않는 경로가 있습니다.'
            }
            $roots += $parts[0]
        }
        $unique = @($roots | Sort-Object -Unique)
        if ($unique.Count -ne 1 -or $unique[0] -notmatch '^[A-Za-z0-9_-]+$') {
            throw '압축 파일의 템플릿 폴더 이름이 올바르지 않습니다.'
        }
        return $unique[0]
    }
    finally {
        $archive.Dispose()
    }
}

function Install-TemplateArchive {
    param([string]$ZipPath, [string]$ExpectedId, [string]$ExpectedSha256)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if ($ExpectedSha256) {
        if ($ExpectedSha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw 'SHA256 형식이 올바르지 않습니다.' }
        if ((Get-FileSha256 $ZipPath) -ne $ExpectedSha256.ToLowerInvariant()) {
            throw 'SHA256 검증에 실패했습니다.'
        }
    }

    $id = Get-TemplateIdFromArchive $ZipPath
    if ($ExpectedId -and $id -ne $ExpectedId) { throw '압축 파일의 템플릿 ID가 요청한 ID와 다릅니다.' }

    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    $totalBytes = [long]0
    $templateEntry = $null
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name -notmatch ('^' + [regex]::Escape($id) + '/')) {
                throw '압축 파일의 모든 항목은 템플릿 ID 폴더 아래에 있어야 합니다.'
            }
            if ($name -match '^/' -or $name -match '^[A-Za-z]:' -or
                @($name.Split('/') | Where-Object { $_ -eq '..' -or $_ -eq '.' }).Count -gt 0) {
                throw '압축 파일에 허용되지 않는 경로가 있습니다.'
            }
            if ($name.EndsWith('/')) { continue }
            $extension = [IO.Path]::GetExtension($name).TrimStart('.').ToLowerInvariant()
            if ($extension -notin @('json','md','txt','png','jpg','webp','mp4','ectemplate','cube','wav','mp3','m4a','ttf','otf')) {
                throw "허용되지 않는 파일 형식입니다: $name"
            }
            $totalBytes += $entry.Length
            if ($totalBytes -gt 200MB) { throw '압축 해제 후 용량이 200MB를 넘습니다.' }
            if ($name -eq "$id/template.json") { $templateEntry = $entry }
        }
        if ($null -eq $templateEntry) { throw 'template.json이 없습니다.' }
        $reader = New-Object IO.StreamReader($templateEntry.Open(), [Text.Encoding]::UTF8)
        try { $templateJson = $reader.ReadToEnd() | ConvertFrom-Json }
        finally { $reader.Dispose() }
        if ([string]$templateJson.id -ne $id) { throw 'template.json의 ID가 폴더 이름과 다릅니다.' }

        $templatesDir = Get-TemplatesDir
        $null = New-Item -ItemType Directory -Force -Path $templatesDir
        $tempDir = Join-Path $templatesDir ('.tmp-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $tempDir
        try {
            $rootPath = [IO.Path]::GetFullPath($tempDir).TrimEnd('\') + '\'
            foreach ($entry in $archive.Entries) {
                $full = $entry.FullName.Replace('\', '/')
                if ($full.EndsWith('/')) { continue }
                $relative = $full.Substring($id.Length + 1).Replace('/', '\')
                $target = [IO.Path]::GetFullPath((Join-Path $tempDir $relative))
                if (-not $target.StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
                    throw '압축 파일 경로가 설치 폴더 밖을 가리킵니다.'
                }
                $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)
                $inputStream = $entry.Open()
                try {
                    $outputStream = [IO.File]::Create($target)
                    try { $inputStream.CopyTo($outputStream) }
                    finally { $outputStream.Dispose() }
                }
                finally { $inputStream.Dispose() }
            }
            $destination = Join-Path $templatesDir $id
            if (Test-Path -LiteralPath $destination) {
                $backup = Join-Path $templatesDir ($id + '-old-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
                Move-Item -LiteralPath $destination -Destination $backup
            }
            Move-Item -LiteralPath $tempDir -Destination $destination
        }
        finally {
            if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Invoke-TemplateCommand {
    param([string[]]$Arguments)
    if ($Arguments.Count -lt 1) { throw 'template list 또는 template install을 지정해 주세요.' }
    $action = $Arguments[0].ToLowerInvariant()
    $indexArg = $null

    if ($action -eq 'list') {
        for ($i = 1; $i -lt $Arguments.Count; $i++) {
            if ($Arguments[$i] -eq '-Index' -and ($i + 1) -lt $Arguments.Count) {
                $indexArg = $Arguments[++$i]
            }
            else { throw "알 수 없는 옵션입니다: $($Arguments[$i])" }
        }
        $index = Get-TemplateIndex $indexArg
        $installed = @(Get-InstalledTemplates)
        $installedIds = @($installed | ForEach-Object { $_.id })
        $available = @($index.templates | Where-Object { $_.id -and $_.id -notin $installedIds })
        $rows = @()
        foreach ($item in $installed) {
            $rows += [pscustomobject]@{ id=$item.id; 상태='설치됨'; 이름=$item.name_ko; 설명=$item.description; 가격=(Format-TemplatePrice $item.price $null); 비율=$item.aspect; 버전=$item.version }
        }
        foreach ($item in $available) {
            $rows += [pscustomobject]@{ id=$item.id; 상태='받을 수 있음'; 이름=$item.name_ko; 설명=$item.description; 가격=(Format-TemplatePrice $item.price $item.store); 비율=$item.aspect; 버전=$item.version }
        }
        if ($rows.Count -gt 0) { $rows | Format-Table -AutoSize | Out-Host }
        Write-Output (@{ installed=@($installedIds); available=@($available | ForEach-Object { $_.id }) } | ConvertTo-Json -Compress -Depth 8)
        return
    }

    if ($action -ne 'install' -or $Arguments.Count -lt 2) { throw 'template install <id | zip 파일 | https 주소>를 지정해 주세요.' }

    $inputValue = $Arguments[1]
    $shaArg = $null
    for ($i = 2; $i -lt $Arguments.Count; $i++) {
        if ($Arguments[$i] -eq '-Index' -and ($i + 1) -lt $Arguments.Count) {
            $indexArg = $Arguments[++$i]
        }
        elseif ($Arguments[$i] -eq '-Sha256' -and ($i + 1) -lt $Arguments.Count) {
            $shaArg = $Arguments[++$i]
        }
        else { throw "알 수 없는 옵션입니다: $($Arguments[$i])" }
    }

    $downloadUri = $null
    $expectedSha = $shaArg
    $expectedId = $null
    $zipPath = $null
    if ($inputValue -match '^https://') {
        $downloadUri = $inputValue
    }
    elseif (Test-Path -LiteralPath $inputValue -PathType Leaf) {
        if ([IO.Path]::GetExtension($inputValue) -ne '.zip') { throw '템플릿 파일은 zip이어야 합니다.' }
        $zipPath = (Resolve-Path -LiteralPath $inputValue).Path
    }
    else {
        if ($inputValue -notmatch '^[A-Za-z0-9_-]+$') { throw '템플릿 ID 형식이 올바르지 않습니다.' }
        $expectedId = $inputValue
        $index = Get-TemplateIndex $indexArg
        $item = @($index.templates | Where-Object { $_.id -eq $expectedId } | Select-Object -First 1)
        if ($item.Count -eq 0) { throw "목록에서 템플릿을 찾을 수 없습니다: $expectedId" }
        if ($null -eq $item[0].download) {
            Write-Host "구매 페이지에서 받은 zip 파일 경로를 주세요: $($item[0].store)"
            return
        }
        $downloadUri = [string]$item[0].download
        if (-not $expectedSha) { $expectedSha = [string]$item[0].sha256 }
    }

    if ($downloadUri) {
        if ($downloadUri -notmatch '^https://') { throw '다운로드 주소는 HTTPS여야 합니다.' }
        $downloadDir = Join-Path (Get-InstallRoot) '_download'
        $null = New-Item -ItemType Directory -Force -Path $downloadDir
        $zipPath = Join-Path $downloadDir ('template-' + [guid]::NewGuid().ToString('N') + '.zip')
        Get-DownloadedFile $downloadUri $zipPath
    }
    try {
        Install-TemplateArchive $zipPath $expectedId $expectedSha
        Write-Host '템플릿을 설치했어요.'
    }
    catch {
        if ($downloadUri -and (Test-Path -LiteralPath $zipPath)) { Remove-Item -LiteralPath $zipPath -Force }
        throw
    }
}

function Get-CraftMetadata {
    param([string]$Name)
    $result = Get-GitHubAsset "storytold/$Name" '*windows-x64-portable.zip' -Latest
    if ($null -eq $result) { throw "$Name Windows 포터블 zip을 찾을 수 없습니다." }
    $sums = @($result.Release.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1)
    if ($sums.Count -eq 0) { throw "$Name SHA256SUMS.txt를 찾을 수 없습니다." }
    if ($result.Asset.browser_download_url -notlike "https://github.com/storytold/$Name/releases/download/*") {
        throw "$Name 다운로드 주소가 허용된 GitHub 주소가 아닙니다."
    }
    return [pscustomobject]@{
        Uri = $result.Asset.browser_download_url
        Bytes = [long]$result.Asset.size
        SumsUri = $sums[0].browser_download_url
        Name = $result.Asset.name
    }
}

function Install-Craft {
    param([string]$Name, $Metadata, [string]$Root)
    $downloadDir = Join-Path $Root '_download'
    $null = New-Item -ItemType Directory -Force -Path $downloadDir
    $zipPath = Join-Path $downloadDir ($Name + '-' + [guid]::NewGuid().ToString('N') + '.zip')
    $sumsPath = Join-Path $downloadDir ($Name + '-SHA256SUMS-' + [guid]::NewGuid().ToString('N') + '.txt')
    $extractDir = Join-Path $downloadDir ($Name + '-extract-' + [guid]::NewGuid().ToString('N'))
    try {
        Get-DownloadedFile $Metadata.Uri $zipPath
        Get-DownloadedFile $Metadata.SumsUri $sumsPath
        $sumsText = [IO.File]::ReadAllText($sumsPath, [Text.Encoding]::UTF8)
        $escapedName = [regex]::Escape($Metadata.Name)
        $match = [regex]::Match($sumsText, '(?m)^\s*([A-Fa-f0-9]{64})\s+\*?' + $escapedName + '\s*$')
        if (-not $match.Success) { throw 'SHA256SUMS.txt에서 zip의 검증값을 찾지 못했습니다.' }
        if ((Get-FileSha256 $zipPath) -ne $match.Groups[1].Value.ToLowerInvariant()) { throw 'SHA256 검증에 실패했습니다.' }

        $null = New-Item -ItemType Directory -Path $extractDir
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force
        $exe = Get-ChildItem -LiteralPath $extractDir -Filter ($Name + '-cli.exe') -File -Recurse | Select-Object -First 1
        if ($null -eq $exe) { throw "$Name-cli.exe가 압축 파일에 없습니다." }
        $signature = Get-AuthenticodeSignature -LiteralPath $exe.FullName
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '^CN=Learning Machines Inc(?:,|$)') {
            throw '실행 파일 서명을 확인할 수 없습니다.'
        }

        $destination = Join-Path (Join-Path $Root 'craft') $Name
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)
        if (Test-Path -LiteralPath $destination) {
            $backup = $destination + '-old-' + (Get-Date -Format 'yyyyMMdd-HHmm')
            if (Test-Path -LiteralPath $backup) { $backup += '-' + (Get-Date -Format 'ss') }
            Move-Item -LiteralPath $destination -Destination $backup
        }
        # zip 안이 <앱>-<판>-windows-x64-portable\ 한 겹이면 그 안을 옮겨 <craft>\<앱>\<앱>-cli.exe 가 되게 한다
        $top = @(Get-ChildItem -LiteralPath $extractDir)
        $source = if ($top.Count -eq 1 -and $top[0].PSIsContainer) { $top[0].FullName } else { $extractDir }
        Move-Item -LiteralPath $source -Destination $destination
    }
    catch {
        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        if (Test-Path -LiteralPath $sumsPath) { Remove-Item -LiteralPath $sumsPath -Force }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force }
    }
}

function Get-WhisperMetadata {
    $result = Get-GitHubAsset 'ggml-org/whisper.cpp' 'whisper-blas-bin-x64.zip'
    if ($null -eq $result) { throw 'whisper-blas-bin-x64.zip을 찾을 수 없습니다.' }
    return [pscustomobject]@{
        Uri = $result.Asset.browser_download_url
        Bytes = [long]$result.Asset.size
        Digest = [string]$result.Asset.digest
        Name = [string]$result.Asset.name
    }
}

function Install-Whisper {
    param($Metadata, [string]$Root)
    $downloadDir = Join-Path $Root '_download'
    $null = New-Item -ItemType Directory -Force -Path $downloadDir
    $zipPath = Join-Path $downloadDir ('whisper-' + [guid]::NewGuid().ToString('N') + '.zip')
    $extractDir = Join-Path $downloadDir ('whisper-extract-' + [guid]::NewGuid().ToString('N'))
    try {
        Get-DownloadedFile $Metadata.Uri $zipPath
        if ($Metadata.Digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { throw 'GitHub에서 유효한 SHA256 검증값을 받지 못했습니다.' }
        if ((Get-FileSha256 $zipPath) -ne $Matches[1].ToLowerInvariant()) { throw 'SHA256 검증에 실패했습니다.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $files = @($archive.Entries | Where-Object {
                $_.FullName -match '^Release/[^/]+\.dll$' -or $_.FullName -eq 'Release/whisper-cli.exe'
            })
            if (@($files | Where-Object { $_.FullName -eq 'Release/whisper-cli.exe' }).Count -eq 0) {
                throw 'Release/whisper-cli.exe가 압축 파일에 없습니다.'
            }
            $null = New-Item -ItemType Directory -Path $extractDir
            foreach ($entry in $files) {
                $name = [IO.Path]::GetFileName($entry.FullName)
                $target = Join-Path $extractDir $name
                $inputStream = $entry.Open()
                try {
                    $outputStream = [IO.File]::Create($target)
                    try { $inputStream.CopyTo($outputStream) }
                    finally { $outputStream.Dispose() }
                }
                finally { $inputStream.Dispose() }
            }
        }
        finally { $archive.Dispose() }

        $destination = Join-Path $Root 'whisper-cli'
        if (Test-Path -LiteralPath $destination) {
            $backup = $destination + '-old-' + (Get-Date -Format 'yyyyMMdd-HHmm')
            if (Test-Path -LiteralPath $backup) { $backup += '-' + (Get-Date -Format 'ss') }
            Move-Item -LiteralPath $destination -Destination $backup
        }
        Move-Item -LiteralPath $extractDir -Destination $destination
    }
    catch {
        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force }
    }
}

function Get-ModelEtag {
    param([string]$Uri)
    # PS 5.1 의 Invoke-WebRequest 는 302 를 막으면 예외로 끝나 헤더를 잃는다 → 리다이렉트를 끈 HEAD 를 직접 보낸다
    $request = [Net.HttpWebRequest]::Create($Uri)
    $request.Method = 'HEAD'
    $request.AllowAutoRedirect = $false
    $request.UserAgent = 'editnado-setup'
    $response = $request.GetResponse()
    try { $etag = [string]$response.Headers['X-Linked-Etag'] } finally { $response.Close() }
    if ($etag -notmatch '^"?([A-Fa-f0-9]{64})"?$') { throw '모델 다운로드 주소의 SHA256 헤더를 확인할 수 없습니다.' }
    return $Matches[1].ToLowerInvariant()
}

function Install-WhisperModel {
    param([string]$Quality, [string]$Root)
    if ($Quality -eq 'high') {
        $fileName = 'ggml-large-v3-turbo-q5_0.bin'
        $size = 547
    }
    else {
        $fileName = 'ggml-small-q5_1.bin'
        $size = 181
    }
    $uri = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$fileName"
    $expected = Get-ModelEtag $uri
    $downloadDir = Join-Path $Root '_download'
    $null = New-Item -ItemType Directory -Force -Path $downloadDir
    $path = Join-Path $downloadDir ($fileName + '.' + [guid]::NewGuid().ToString('N') + '.download')
    try {
        Get-DownloadedFile $uri $path
        if ((Get-FileSha256 $path) -ne $expected) { throw 'SHA256 검증에 실패했습니다.' }
        $modelDir = Join-Path (Join-Path $Root 'whisper-cli') 'models'
        $null = New-Item -ItemType Directory -Force -Path $modelDir
        Move-Item -LiteralPath $path -Destination (Join-Path $modelDir $fileName) -Force
    }
    catch {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        throw
    }
    return $size
}

function Get-FontMetadata {
    $pretendard = Get-GitHubAsset 'orioncactus/pretendard' 'Pretendard-*.zip' -Latest
    if ($null -eq $pretendard -or $pretendard.Asset.name -match '(?i)GOV|JP|Std') { throw 'Pretendard 배포 zip을 찾을 수 없습니다.' }
    $d2 = Get-GitHubAsset 'naver/d2-coding-font' '*.zip' -Latest
    if ($null -eq $d2) { throw 'D2Coding 배포 zip을 찾을 수 없습니다.' }
    return [pscustomobject]@{ Pretendard=$pretendard.Asset; D2=$d2.Asset }
}

function Install-Fonts {
    param([string]$Root)
    $fontDir = Join-Path $Root 'fonts'
    $downloadDir = Join-Path $Root '_download'
    $userFontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $null = New-Item -ItemType Directory -Force -Path $fontDir
    $null = New-Item -ItemType Directory -Force -Path $downloadDir
    $null = New-Item -ItemType Directory -Force -Path $userFontDir
    $metadata = Get-FontMetadata
    $temp = Join-Path $downloadDir ('fonts-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $temp
    $downloaded = @()
    try {
        $nanumDir = Join-Path $temp 'nanum'
        $null = New-Item -ItemType Directory -Path $nanumDir
        foreach ($weight in @('Regular','Bold','ExtraBold')) {
            $file = "NanumGothic-$weight.ttf"
            $path = Join-Path $downloadDir ($file + '.' + [guid]::NewGuid().ToString('N'))
            Get-DownloadedFile "https://github.com/google/fonts/raw/main/ofl/nanumgothic/$file" $path
            $downloaded += $path
            Copy-Item -LiteralPath $path -Destination (Join-Path $nanumDir $file)
        }
        $licensePath = Join-Path $downloadDir ('NanumGothic-OFL-' + [guid]::NewGuid().ToString('N') + '.txt')
        Get-DownloadedFile 'https://github.com/google/fonts/raw/main/ofl/nanumgothic/OFL.txt' $licensePath
        $downloaded += $licensePath
        Copy-Item -LiteralPath $licensePath -Destination (Join-Path $nanumDir 'OFL.txt')

        $pretZip = Join-Path $downloadDir ('Pretendard-' + [guid]::NewGuid().ToString('N') + '.zip')
        Get-DownloadedFile $metadata.Pretendard.browser_download_url $pretZip
        $downloaded += $pretZip
        $pretDir = Join-Path $temp 'pretendard'
        $null = New-Item -ItemType Directory -Path $pretDir
        Expand-Archive -LiteralPath $pretZip -DestinationPath $pretDir -Force

        $d2Zip = Join-Path $downloadDir ('D2Coding-' + [guid]::NewGuid().ToString('N') + '.zip')
        Get-DownloadedFile $metadata.D2.browser_download_url $d2Zip
        $downloaded += $d2Zip
        $d2Dir = Join-Path $temp 'd2'
        $null = New-Item -ItemType Directory -Path $d2Dir
        Expand-Archive -LiteralPath $d2Zip -DestinationPath $d2Dir -Force

        $files = @()
        $files += @(Get-ChildItem -LiteralPath $nanumDir -Filter '*.ttf' -File)
        $files += @(Get-ChildItem -LiteralPath $pretDir -Filter 'Pretendard-Regular.otf' -File -Recurse | Where-Object { $_.FullName -match '[\\/]public[\\/]static[\\/]' })
        $files += @(Get-ChildItem -LiteralPath $pretDir -Filter 'Pretendard-Bold.otf' -File -Recurse | Where-Object { $_.FullName -match '[\\/]public[\\/]static[\\/]' })
        $files += @(Get-ChildItem -LiteralPath $pretDir -Filter 'Pretendard-ExtraBold.otf' -File -Recurse | Where-Object { $_.FullName -match '[\\/]public[\\/]static[\\/]' })
        $files += @(Get-ChildItem -LiteralPath $d2Dir -Filter 'D2Coding*-Ver*.ttf' -File -Recurse | Where-Object { $_.FullName -match '[\\/]D2Coding[\\/]' })
        if ($files.Count -lt 7) { throw '설치할 글꼴 파일을 모두 찾지 못했습니다.' }

        $licenses = @()
        $licenses += @(Get-ChildItem -LiteralPath $nanumDir -File | Where-Object { $_.Name -match '^(LICENSE|OFL)' })
        $licenses += @(Get-ChildItem -LiteralPath $pretDir -File -Recurse | Where-Object { $_.Name -match '^(LICENSE|OFL)' })
        $licenses += @(Get-ChildItem -LiteralPath $d2Dir -File -Recurse | Where-Object { $_.Name -match '^(LICENSE|OFL)' })
        if ($licenses.Count -lt 3) { throw '글꼴 라이선스 파일을 모두 찾지 못했습니다.' }

        foreach ($file in $files) {
            $target = Join-Path $userFontDir $file.Name
            Copy-Item -LiteralPath $file.FullName -Destination $target -Force
            $kind = if ($file.Extension -ieq '.ttf') { 'TrueType' } else { 'OpenType' }
            $valueName = $file.Name + " ($kind)"
            $null = New-Item -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -Force
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -Name $valueName -Value $target
            $null = [EditnadoFontNative]::AddFontResource($target)
        }
        foreach ($license in $licenses) {
            $target = Join-Path $fontDir $license.Name
            if (-not (Test-Path -LiteralPath $target)) { Copy-Item -LiteralPath $license.FullName -Destination $target }
        }

        if (-not ('EditnadoFontNative' -as [type])) {
            $null = Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EditnadoFontNative {
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
    public static extern int AddFontResource(string fileName);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, UIntPtr wParam, IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
}
'@
        }
        foreach ($file in $files) { $null = [EditnadoFontNative]::AddFontResource((Join-Path $userFontDir $file.Name)) }
        $nativeResult = [UIntPtr]::Zero
        $null = [EditnadoFontNative]::SendMessageTimeout([IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 5000, [ref]$nativeResult)
    }
    catch {
        foreach ($path in $downloaded) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
    }
}

function Invoke-SetupCommand {
    param([string[]]$Arguments)
    $yes = $false
    $fonts = $false
    $photo = $false
    # 한국어는 작은 모델(small)이 「해 뜨는→헤드는」처럼 자주 틀려(실측) 기본을 large-v3-turbo 로. 아주 낮은 사양만 -Quality normal
    $quality = 'high'
    $only = $null
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        switch -Regex ($Arguments[$i]) {
            '^-Yes$' { $yes = $true; continue }
            '^-Fonts$' { $fonts = $true; continue }
            '^-Photo$' { $photo = $true; continue }
            '^-Quality$' {
                if (($i + 1) -ge $Arguments.Count) { throw '-Quality 뒤에 normal 또는 high를 지정해 주세요.' }
                $quality = $Arguments[++$i].ToLowerInvariant()
                continue
            }
            '^-Only$' {
                if (($i + 1) -ge $Arguments.Count) { throw '-Only 뒤에 설치 항목을 지정해 주세요.' }
                $only = @($Arguments[++$i].Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
                continue
            }
            default { throw "알 수 없는 옵션입니다: $($Arguments[$i])" }
        }
    }
    if ($quality -notin @('normal','high')) { throw '-Quality는 normal 또는 high여야 합니다.' }

    $root = Get-InstallRoot
    if (-not $root) { throw '설치 경로를 확인할 수 없습니다.' }
    $craftNames = @('filmcraft','effectcraft','lightcraft','photocraft')
    $allNames = @($craftNames + @('ffmpeg','whisper-cli','whisper-model','fonts'))
    # 자동 편집에 꼭 필요한 것만 기본으로 (사진 보정 앱 255MB 는 -Photo, 글꼴은 -Fonts)
    $names = @('filmcraft','effectcraft','ffmpeg','whisper-cli','whisper-model')
    if ($photo) { $names += @('lightcraft','photocraft') }
    if ($fonts) { $names += 'fonts' }
    if ($only) {
        $unknown = @($only | Where-Object { $_ -notin $allNames })
        if ($unknown.Count -gt 0) { throw "알 수 없는 항목입니다: $($unknown -join ', ')" }
        $names = @($only)
    }

    $records = @()
    foreach ($name in $names) {
        $path = $null
        if ($name -in $craftNames) { $path = Get-CraftPath $name }
        elseif ($name -eq 'ffmpeg') { $path = Get-ToolPath ffmpeg }
        elseif ($name -eq 'whisper-cli') { $path = Get-ToolPath whisper-cli }
        elseif ($name -eq 'whisper-model') {
            $modelDir = Join-Path (Join-Path $root 'whisper-cli') 'models'
            if (Test-Path -LiteralPath $modelDir -PathType Container) {
                $path = Get-ChildItem -LiteralPath $modelDir -Filter '*.bin' -File | Select-Object -First 1
            }
        }
        elseif ($name -eq 'fonts') {
            $installedNames = @(Get-InstalledFontNames)
            if (@('NanumGothic','Pretendard','D2Coding' | Where-Object { $_ -notin $installedNames }).Count -eq 0) { $path = 'installed' }
        }
        $records += [pscustomobject]@{ Name=$name; Existing=($null -ne $path); Size='미확인'; Source=''; Destination='' }
    }

    $metadata = @{}
    foreach ($record in $records) {
        try {
            switch ($record.Name) {
                { $_ -in $craftNames } {
                    $metadata[$record.Name] = Get-CraftMetadata $record.Name
                    $record.Size = Get-SizeMb $metadata[$record.Name].Bytes
                    $record.Source = "GitHub storytold/$($record.Name)"
                    $record.Destination = Join-Path (Join-Path $root 'craft') $record.Name
                }
                'ffmpeg' {
                    $uri = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
                    $head = Invoke-WebRequest -Uri $uri -Method Head -UseBasicParsing
                    $record.Size = Get-SizeMb ([long]$head.Headers['Content-Length'])
                    $record.Source = 'gyan.dev'
                    $record.Destination = Join-Path $root 'ffmpeg\bin'
                }
                'whisper-cli' {
                    $metadata[$record.Name] = Get-WhisperMetadata
                    $record.Size = Get-SizeMb $metadata[$record.Name].Bytes
                    $record.Source = 'GitHub ggml-org/whisper.cpp'
                    $record.Destination = Join-Path $root 'whisper-cli'
                }
                'whisper-model' {
                    $record.Size = if ($quality -eq 'high') { 547 } else { 181 }
                    $record.Source = 'Hugging Face ggerganov/whisper.cpp'
                    $record.Destination = Join-Path $root 'whisper-cli\models'
                }
                'fonts' {
                    $metadata[$record.Name] = Get-FontMetadata
                    $record.Source = 'Google Fonts · Pretendard · D2Coding'
                    $record.Destination = Join-Path $root 'fonts'
                }
            }
        }
        catch {
            $record.Source = '출처 확인 실패'
            $record.Size = '미확인'
            $record.Destination = if ($record.Name -in $craftNames) { Join-Path (Join-Path $root 'craft') $record.Name } else { Join-Path $root $record.Name }
            $record | Add-Member -NotePropertyName MetadataError -NotePropertyValue $_.Exception.Message -Force
        }
    }

    $rows = @()
    foreach ($record in $records) {
        $rows += [pscustomobject]@{
            이름 = $record.Name
            상태 = if ($record.Existing) { '있음' } else { '없음' }
            '받을 크기(MB)' = $record.Size
            출처 = $record.Source
            설치위치 = $record.Destination
        }
    }
    if ($rows.Count -gt 0) { $rows | Format-Table -AutoSize | Out-Host }
    $knownSizes = @($records | Where-Object { -not $_.Existing -and $_.Size -ne '미확인' -and $null -ne $_.Size } | ForEach-Object { [double]$_.Size })
    $total = [math]::Round([double](($knownSizes | Measure-Object -Sum).Sum), 0)
    Write-Host "합계 크기: $total MB (크기 미확인 항목 제외)"

    $installed = @()
    $skipped = @($records | Where-Object { $_.Existing } | ForEach-Object { $_.Name })
    $failed = @()
    if (-not $yes) {
        Write-Output (@{ installed=@($installed); skipped=@($skipped); failed=@($failed); root=$root } | ConvertTo-Json -Compress -Depth 8)
        return
    }

    $null = New-Item -ItemType Directory -Force -Path $root
    foreach ($record in $records) {
        if ($record.Existing) { continue }
        try {
            if ($record.MetadataError) { throw $record.MetadataError }
            switch ($record.Name) {
                { $_ -in $craftNames } {
                    Write-Host "$($record.Name) 받는 중 ($($record.Size)MB)…"
                    Install-Craft $record.Name $metadata[$record.Name] $root
                }
                'ffmpeg' {
                    Write-Host "FFmpeg 받는 중 ($($record.Size)MB)…"
                    $downloadDir = Join-Path $root '_download'
                    $null = New-Item -ItemType Directory -Force -Path $downloadDir
                    $zip = Join-Path $downloadDir ('ffmpeg-' + [guid]::NewGuid().ToString('N') + '.zip')
                    $sha = $zip + '.sha256'
                    $temp = Join-Path $downloadDir ('ffmpeg-extract-' + [guid]::NewGuid().ToString('N'))
                    try {
                        Get-DownloadedFile 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' $zip
                        Get-DownloadedFile 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip.sha256' $sha
                        $expected = ([IO.File]::ReadAllText($sha, [Text.Encoding]::UTF8).Trim() -split '\s+')[0]
                        if ($expected -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileSha256 $zip) -ne $expected.ToLowerInvariant()) { throw 'SHA256 검증에 실패했습니다.' }
                        Add-Type -AssemblyName System.IO.Compression.FileSystem
                        $archive = [IO.Compression.ZipFile]::OpenRead($zip)
                        try {
                            $files = @($archive.Entries | Where-Object { $_.FullName -match '^[^/]+/bin/[^/]+\.exe$' })
                            if ($files.Count -eq 0) { throw '압축 파일에서 bin 폴더의 실행 파일을 찾지 못했습니다.' }
                            $bin = Join-Path $temp 'bin'
                            $null = New-Item -ItemType Directory -Force -Path $bin
                            foreach ($entry in $files) {
                                $target = Join-Path $bin ([IO.Path]::GetFileName($entry.FullName))
                                $inputStream = $entry.Open()
                                try {
                                    $outputStream = [IO.File]::Create($target)
                                    try { $inputStream.CopyTo($outputStream) }
                                    finally { $outputStream.Dispose() }
                                }
                                finally { $inputStream.Dispose() }
                            }
                        }
                        finally { $archive.Dispose() }
                        $destination = Join-Path $root 'ffmpeg'
                        if (Test-Path -LiteralPath $destination) {
                            $backup = $destination + '-old-' + (Get-Date -Format 'yyyyMMdd-HHmm')
                            if (Test-Path -LiteralPath $backup) { $backup += '-' + (Get-Date -Format 'ss') }
                            Move-Item -LiteralPath $destination -Destination $backup
                        }
                        Move-Item -LiteralPath $temp -Destination $destination
                    }
                    catch {
                        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
                        if (Test-Path -LiteralPath $sha) { Remove-Item -LiteralPath $sha -Force }
                        throw
                    }
                    finally {
                        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
                    }
                }
                'whisper-cli' {
                    Write-Host "Whisper CLI 받는 중 ($($record.Size)MB)…"
                    Install-Whisper $metadata[$record.Name] $root
                }
                'whisper-model' {
                    $size = if ($quality -eq 'high') { 547 } else { 181 }
                    Write-Host "받아쓰기 모델 받는 중 ($size`MB)…"
                    $null = Install-WhisperModel $quality $root
                }
                'fonts' {
                    Write-Host '글꼴 받는 중…'
                    Install-Fonts $root
                }
            }
            $installed += $record.Name
        }
        catch {
            $failed += [pscustomobject]@{ name=$record.Name; reason=$_.Exception.Message }
            Write-Host "$($record.Name) 설치 실패: $($_.Exception.Message)"
        }
    }
    if ($failed.Count -eq 0) { Write-Host '다 깔았어요.' }
    Write-Output (@{ installed=@($installed); skipped=@($skipped); failed=@($failed); root=$root } | ConvertTo-Json -Compress -Depth 8)
    if ($failed.Count -gt 0) { exit 1 }
}

# 새 판 zip(최상위 editnado/)을 검사해 임시 폴더에 푼 뒤 덮는다 — profiles/local 은 건너뛰고, 바뀌는 파일만 BackupDir 에 남기고, zip 에 없는 파일은 지우지 않는다
function Install-SkillArchive {
    param([string]$ZipPath, [string]$SkillDir, [string]$BackupDir)

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    $stagePath = $null
    try {
        $entries = @($archive.Entries)
        $entryNames = @{}
        $totalLength = [int64]0

        foreach ($entry in $entries) {
            $entryName = $entry.FullName.Replace('\', '/')
            $isDirectory = $entryName.EndsWith('/')
            $checkName = if ($isDirectory) { $entryName.TrimEnd('/') } else { $entryName }

            if ($entryName.StartsWith('/') -or $entryName -match '^[A-Za-z]:' -or
                -not $entryName.StartsWith('editnado/') -or
                @($checkName.Split('/')).Where({ $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
                throw "허용되지 않는 zip 경로: $($entry.FullName)"
            }
            if ($entryNames.ContainsKey($entryName)) {
                throw "중복된 zip 경로: $entryName"
            }
            $entryNames[$entryName] = $true
            if (-not $isDirectory) {
                $totalLength += $entry.Length
            }
        }

        if (-not $entryNames.ContainsKey('editnado/SKILL.md') -or
            -not $entryNames.ContainsKey('editnado/vc.ps1')) {
            throw 'editnado/SKILL.md와 editnado/vc.ps1이 필요합니다.'
        }
        if ($totalLength -gt 50MB) {
            throw '압축 해제 크기가 50MB를 초과합니다.'
        }

        $stagePath = Join-Path $SkillDir ('.update-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($stagePath)
        $stageRoot = [IO.Path]::GetFullPath($stagePath).TrimEnd('\') + '\'

        foreach ($entry in $entries) {
            $entryName = $entry.FullName.Replace('\', '/')
            if ($entryName.EndsWith('/')) { continue }

            $relativePath = $entryName.Substring('editnado/'.Length)
            $destinationPath = [IO.Path]::GetFullPath((Join-Path $stagePath ($relativePath.Replace('/', '\'))))
            if (-not $destinationPath.StartsWith($stageRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "임시 폴더 밖의 경로입니다: $entryName"
            }

            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destinationPath))
            $inputStream = $entry.Open()
            try {
                $outputStream = [IO.File]::Create($destinationPath)
                try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
            } finally {
                $inputStream.Dispose()
            }
        }

        $updated = 0
        $added = 0
        $backupCreated = $false
        $backupResult = $null

        foreach ($stagedFile in @(Get-ChildItem -LiteralPath $stagePath -File -Recurse)) {
            $relativePath = $stagedFile.FullName.Substring($stageRoot.Length).Replace('\', '/')
            if ($relativePath.StartsWith('profiles/local/', [StringComparison]::OrdinalIgnoreCase)) { continue }

            $targetPath = Join-Path $SkillDir ($relativePath.Replace('/', '\'))
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($targetPath))

            if ([IO.File]::Exists($targetPath)) {
                $oldBytes = [IO.File]::ReadAllBytes($targetPath)
                $newBytes = [IO.File]::ReadAllBytes($stagedFile.FullName)
                if ($oldBytes.Length -eq $newBytes.Length -and
                    [Linq.Enumerable]::SequenceEqual([byte[]]$oldBytes, [byte[]]$newBytes)) {
                    continue
                }

                if (-not $backupCreated) {
                    [void][IO.Directory]::CreateDirectory($BackupDir)
                    $backupCreated = $true
                    $backupResult = $BackupDir
                }
                $backupPath = Join-Path $BackupDir ($relativePath.Replace('/', '\'))
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backupPath))
                [IO.File]::Copy($targetPath, $backupPath, $true)
                [IO.File]::Copy($stagedFile.FullName, $targetPath, $true)
                $updated++
            } else {
                [IO.File]::Copy($stagedFile.FullName, $targetPath)
                $added++
            }
        }

        [pscustomobject]@{ updated = $updated; added = $added; backup = $backupResult }
    } finally {
        if ($null -ne $stagePath -and [IO.Directory]::Exists($stagePath)) {
            Remove-Item -LiteralPath $stagePath -Recurse -Force
        }
        $archive.Dispose()
    }
}

function Get-SkillVersion {
    param([string]$Text)
    if ($Text -match '(?m)^\s*version:\s*"?([0-9][0-9.]*)"?') { return [version]$Matches[1] }
    return $null
}

function Invoke-UpdateCommand {
    # 깃으로 받은 폴더 = git pull (고친 파일이 있으면 멈춤) · zip 으로 받은 폴더 = 최신 릴리스 zip 을 SHA256 확인 뒤 덮기 · -Zip = 직접 받은 zip
    # 어느 길이든 profiles/local(개인 취향)과 설치한 템플릿은 그대로 둔다. -Yes 없이는 무엇이 바뀌는지만 보인다
    param([string[]]$Arguments)
    $yes = $false
    $zipFile = $null
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        switch -Regex ($Arguments[$i]) {
            '^-Yes$' { $yes = $true; continue }
            '^-Zip$' {
                if (($i + 1) -ge $Arguments.Count) { throw '-Zip 뒤에 zip 파일 경로를 지정해 주세요.' }
                $zipFile = $Arguments[++$i]
                continue
            }
            default { throw "알 수 없는 옵션입니다: $($Arguments[$i])" }
        }
    }
    $skillDir = $PSScriptRoot
    $skillFile = Join-Path $skillDir 'SKILL.md'
    $current = Get-SkillVersion ([IO.File]::ReadAllText($skillFile, [Text.Encoding]::UTF8))
    $backupDir = Join-Path (Get-InstallRoot) ('backup\editnado-{0}-{1}' -f $current, (Get-Date -Format 'yyyyMMdd-HHmmss'))

    if ($zipFile) {
        $zipFile = [IO.Path]::GetFullPath($zipFile)
        if (-not $yes) { Write-Host "이 zip 으로 바꿉니다 (지금 $current): $zipFile — 하려면 vc.cmd update -Zip <파일> -Yes"; return }
        $result = Install-SkillArchive $zipFile $skillDir $backupDir
        $new = Get-SkillVersion ([IO.File]::ReadAllText($skillFile, [Text.Encoding]::UTF8))
        Write-Host "바꿨어요: $current → $new"
        Write-Output (@{ from = "$current"; to = "$new"; updated = $result.updated; added = $result.added; backup = $result.backup } | ConvertTo-Json -Compress)
        return
    }

    if ((Test-Path -LiteralPath (Join-Path $skillDir '.git')) -and (Get-Command git -ErrorAction SilentlyContinue)) {
        # git 은 진행 문구를 표준오류로 낸다 → 여기서는 멈추지 않고 종료 코드로 판단
        $ErrorActionPreference = 'Continue'
        $null = & git -C $skillDir fetch --quiet 2>&1
        if ($LASTEXITCODE -ne 0) { throw '저장소에 연결하지 못했어요 (인터넷·깃허브 로그인 확인).' }
        $behind = [int](& git -C $skillDir rev-list --count 'HEAD..@{u}' 2>$null)
        if ($behind -eq 0) {
            Write-Host "최신이에요 ($current)"
            Write-Output (@{ current = "$current"; latest = "$current"; behind = 0 } | ConvertTo-Json -Compress)
            return
        }
        $latest = Get-SkillVersion ((& git -C $skillDir show '@{u}:SKILL.md' 2>$null) -join "`n")
        $changes = @(& git -C $skillDir log --format='%s' -n 10 'HEAD..@{u}' 2>$null)
        if (-not $yes) {
            Write-Host "새 판이 있어요: $current → $latest (바뀐 것 $behind 건)"
            foreach ($line in $changes) { Write-Host "  - $line" }
            Write-Host '받으려면: vc.cmd update -Yes (개인 취향 profiles/local 은 그대로)'
            Write-Output (@{ current = "$current"; latest = "$latest"; behind = $behind; changes = $changes } | ConvertTo-Json -Compress)
            return
        }
        $dirty = @(& git -C $skillDir status --porcelain --untracked-files=no 2>$null)
        if ($dirty.Count) { throw "이 폴더에서 고친 파일이 있어 덮어쓰지 않았어요: $(($dirty | ForEach-Object { $_.Substring(3) }) -join ', ')" }
        $null = & git -C $skillDir pull --ff-only --quiet 2>&1
        if ($LASTEXITCODE -ne 0) { throw '새 판을 받지 못했어요 (git pull).' }
        $new = Get-SkillVersion ([IO.File]::ReadAllText($skillFile, [Text.Encoding]::UTF8))
        Write-Host "바꿨어요: $current → $new"
        Write-Output (@{ from = "$current"; to = "$new" } | ConvertTo-Json -Compress)
        return
    }

    $repo = if ($env:VC_SKILL_REPO) { $env:VC_SKILL_REPO } else { $script:SkillRepo }
    try { $release = Get-ApiJson "https://api.github.com/repos/$repo/releases/latest" }
    catch { throw "최신 판 정보를 받지 못했어요 ($repo). 저장소가 비공개이거나 릴리스가 없거나 인터넷 문제입니다 — 비공개 저장소는 git clone 으로 받아 쓰세요." }
    $latest = [version]([string]$release.tag_name).TrimStart('v')
    if ($latest -le $current) {
        Write-Host "최신이에요 ($current)"
        Write-Output (@{ current = "$current"; latest = "$latest"; behind = 0 } | ConvertTo-Json -Compress)
        return
    }
    $asset = @($release.assets | Where-Object { $_.name -like 'editnado-*.zip' }) | Select-Object -First 1
    $sums = @($release.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' }) | Select-Object -First 1
    if (-not $asset -or -not $sums) { throw '릴리스에 zip 또는 SHA256SUMS.txt 가 없어요.' }
    if (-not $yes) {
        Write-Host "새 판이 있어요: $current → $latest ($(Get-SizeMb $asset.size)MB)"
        foreach ($line in @(([string]$release.body) -split "\r?\n" | Where-Object { $_.Trim() } | Select-Object -First 8)) { Write-Host "  $line" }
        Write-Host '받으려면: vc.cmd update -Yes (개인 취향 profiles/local 과 설치한 템플릿은 그대로, 바뀌는 파일은 백업)'
        Write-Output (@{ current = "$current"; latest = "$latest"; size_mb = (Get-SizeMb $asset.size) } | ConvertTo-Json -Compress)
        return
    }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('vc-update-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $temp
    try {
        $zipPath = Join-Path $temp $asset.name
        $sumsPath = Join-Path $temp 'SHA256SUMS.txt'
        Get-DownloadedFile $asset.browser_download_url $zipPath
        Get-DownloadedFile $sums.browser_download_url $sumsPath
        $line = Get-Content -LiteralPath $sumsPath | Where-Object { $_ -match [regex]::Escape($asset.name) } | Select-Object -First 1
        $expected = ([string]$line -split '\s+')[0].ToLowerInvariant()
        if ((Get-FileSha256 $zipPath) -ne $expected) { throw 'SHA256 검증에 실패해 바꾸지 않았어요.' }
        $result = Install-SkillArchive $zipPath $skillDir $backupDir
    }
    finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
    $new = Get-SkillVersion ([IO.File]::ReadAllText($skillFile, [Text.Encoding]::UTF8))
    Write-Host "바꿨어요: $current → $new"
    Write-Output (@{ from = "$current"; to = "$new"; updated = $result.updated; added = $result.added; backup = $result.backup } | ConvertTo-Json -Compress)
}

try {
    $arguments = @($args)
    if ($arguments.Count -eq 0) { throw 'setup · template · update 중 하나를 지정해 주세요.' }
    switch ($arguments[0].ToLowerInvariant()) {
        'setup' { Invoke-SetupCommand @($arguments | Select-Object -Skip 1) }
        'template' { Invoke-TemplateCommand @($arguments | Select-Object -Skip 1) }
        'update' { Invoke-UpdateCommand @($arguments | Select-Object -Skip 1) }
        default { throw "알 수 없는 하위 명령입니다: $($arguments[0])" }
    }
}
catch {
    Write-Host "실패: $($_.Exception.Message)"
    exit 1
}