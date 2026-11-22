<#
build-index.ps1 - builds the gallery site that livewall downloads from.

  powershell tools\build-index.ps1 -Checked out [-Staged staged] [-Site site]

Uses check.ps1's results (-Checked: results.json and the <id>.png
previews). Only wallpapers that passed are published. Media files come from
-Staged (the copies rebuilt by ffmpeg), shaders from wallpapers\<id>.

site\index.json lists every wallpaper with the SHA-256 of its file and of
its preview; livewall refuses a download that doesn't match.
site\w\<id>\wallpaper.<ext> and site\w\<id>\preview.png are the files.
#>
param(
    [Parameter(Mandatory = $true)][string]$Checked,
    [string]$Staged,
    [string]$Site = "$PSScriptRoot\..\site"
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path "$PSScriptRoot\..").Path

function Get-Sha256([string]$path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower() }

Remove-Item -Recurse -Force $Site -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$Site\w" | Out-Null
$results = Get-Content -Raw (Join-Path $Checked 'results.json') | ConvertFrom-Json
$list = @()
foreach ($r in @($results) | Where-Object { $_.ok -and $_.kind } | Sort-Object id) {
    $id = $r.id
    $dir = Join-Path "$Root\wallpapers" $id
    $info = Get-Content -LiteralPath (Join-Path $dir 'info.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $src = Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -cmatch '^wallpaper\.(hlsl|mp4|gif|png|jpg)$' } | Select-Object -First 1
    if ($src.Extension -ne '.hlsl' -and $Staged) {
        $src = Get-ChildItem -LiteralPath (Join-Path $Staged $id) -File | Where-Object { $_.Name -like 'wallpaper.*' } | Select-Object -First 1
    }
    $out = New-Item -ItemType Directory -Force (Join-Path "$Site\w" $id)
    $file = Join-Path $out.FullName $src.Name
    $preview = Join-Path $out.FullName 'preview.png'
    Copy-Item -LiteralPath $src.FullName $file
    Copy-Item -LiteralPath (Join-Path $Checked "$id.png") $preview
    $list += [ordered]@{
        id             = $id
        name           = $info.name
        author         = $info.author
        description    = if ($info.description) { $info.description } else { '' }
        tags           = @($info.tags | Where-Object { $_ })
        license        = $info.license
        kind           = $r.kind
        file           = "w/$id/$($src.Name)"
        size           = (Get-Item -LiteralPath $file).Length
        sha256         = Get-Sha256 $file
        preview        = "w/$id/preview.png"
        preview_sha256 = Get-Sha256 $preview
    }
}
$index = [ordered]@{
    format     = 1
    updated    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    wallpapers = $list
}
# UTF-8 without a BOM, so any JSON reader takes it.
[IO.File]::WriteAllText((Join-Path $Site 'index.json'), ($index | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "index.json: $($list.Count) wallpapers"
