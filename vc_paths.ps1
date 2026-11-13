# 도구 위치 찾기 — vc.ps1 · vc_setup.ps1 이 점 소싱(. "$PSScriptRoot\vc_paths.ps1")으로 함께 쓴다

function Get-ToolsRoots {
    # 설치·검색 자리: 환경변수 → 작업공간 관례(<작업공간>\2.Common\tools) → 사용자 폴더
    $roots = @()
    if ($env:VC_TOOLS_DIR) { $roots += $env:VC_TOOLS_DIR }
    $ws = Join-Path $PSScriptRoot '..\..\..\2.Common\tools'
    if (Test-Path -LiteralPath $ws) { $roots += (Resolve-Path -LiteralPath $ws).Path }
    $roots += (Join-Path $env:LOCALAPPDATA 'editnado\tools')
    return $roots
}

# @() 필수: 자리가 하나뿐이면(일반 사용자 PC) 함수 결과가 글자열로 풀려 [0] 이 첫 글자 「C」가 된다 (11-14 실측)
function Get-InstallRoot { return @(Get-ToolsRoots)[0] }

function Get-CraftPath {
    param([string]$Name)
    $exe = "$Name-cli.exe"
    $dirs = @()
    if ($env:VC_CRAFT_DIR) { $dirs += $env:VC_CRAFT_DIR }
    $dirs += @(Get-ToolsRoots | ForEach-Object { Join-Path $_ 'craft' })
    foreach ($d in $dirs) {
        foreach ($p in @((Join-Path $d "$Name\$exe"), (Join-Path $d $exe))) {
            if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
        }
    }
    $found = Get-Command "$Name-cli" -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    return $null
}

function Get-ToolPath {
    param([string]$Name)
    foreach ($root in Get-ToolsRoots) {
        foreach ($c in @("$Name\$Name.exe", "$Name\bin\$Name.exe", "$Name\$Name.cmd")) {
            $p = Join-Path $root $c
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    $found = Get-Command $Name -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    return $null
}

function Get-TemplatesDir { return (Join-Path $PSScriptRoot 'templates') }
