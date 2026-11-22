<#
build-index.ps1 - builds the gallery site that livewall downloads from.

  powershell tools\build-index.ps1 -Checked out [-Staged staged] [-Site site]

Uses check.ps1's results (-Checked: results.json and the <id>.png
previews). Only wallpapers that passed are published. Media files come from
-Staged (the copies rebuilt by ffmpeg), shaders from wallpapers\<id>.

site\index.json lists every wallpaper with the SHA-256 of its file and of
its preview; livewall refuses a download that doesn't match.
site\w\<id>\wallpaper.<ext> and site\w\<id>\preview.png are the files.
The web page in web\ is copied next to them, and so is signed.txt, the
maintainer's signed list (tools\sign.ps1): livewall shows only what is in it.
Likes are added afterwards by likes.ps1 (it needs the GitHub token, so it
runs in the publish job).

The files must stay the same once signed, but ffmpeg and the preview render
may give slightly different bytes each time. So with -Live (the published
gallery), a wallpaper whose source file hasn't changed keeps its published
files: they are downloaded and checked against the published list. If the
published gallery can't be reached, this fails rather than publish new
copies that would no longer match signed.txt.
#>
param(
    [Parameter(Mandatory = $true)][string]$Checked,
    [string]$Staged,
    [string]$Site = "$PSScriptRoot\..\site",
    [string]$Live
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path "$PSScriptRoot\..").Path

function Get-Sha256([string]$path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower() }

Remove-Item -Recurse -Force $Site -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$Site\w" | Out-Null
$Site = (Resolve-Path $Site).Path   # .NET calls below don't know PowerShell's current folder
Copy-Item "$Root\web\*" $Site   # the gallery web page, which reads index.json
$results = Get-Content -Raw (Join-Path $Checked 'results.json') | ConvertFrom-Json
if (Test-Path "$Root\signed.txt") { Copy-Item "$Root\signed.txt" $Site }

# What is published now, by id (empty on the very first publish).
$published = @{}
$web = New-Object Net.WebClient
if ($Live) {
    $Live = $Live.TrimEnd('/') + '/'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $old = [Text.Encoding]::UTF8.GetString($web.DownloadData("${Live}index.json")) | ConvertFrom-Json
        foreach ($w in @($old.wallpapers)) { $published[$w.id] = $w }
    } catch {
        $code = $_.Exception.InnerException.Response.StatusCode
        if ([int]$code -ne 404) { throw "Couldn't read the published gallery ($Live): $($_.Exception.Message)" }
    }
}

$list = @()
foreach ($r in @($results) | Where-Object { $_.ok -and $_.kind } | Sort-Object id) {
    $id = $r.id
    $dir = Join-Path "$Root\wallpapers" $id
    $info = Get-Content -LiteralPath (Join-Path $dir 'info.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $orig = Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -cmatch '^wallpaper\.(hlsl|mp4|gif|png|jpg)$' } | Select-Object -First 1
    $src = $orig
    if ($src.Extension -ne '.hlsl' -and $Staged) {
        $src = Get-ChildItem -LiteralPath (Join-Path $Staged $id) -File | Where-Object { $_.Name -like 'wallpaper.*' } | Select-Object -First 1
    }
    $sourceSha = Get-Sha256 $orig.FullName
    $out = New-Item -ItemType Directory -Force (Join-Path "$Site\w" $id)
    $file = Join-Path $out.FullName $src.Name
    $preview = Join-Path $out.FullName 'preview.png'
    $was = $published[$id]
    if ($was -and $was.source_sha256 -eq $sourceSha -and $was.file -eq "w/$id/$($src.Name)" -and $was.preview -eq "w/$id/preview.png") {
        # Unchanged since it was published: keep exactly the published files.
        $web.DownloadFile("$Live$($was.file)", $file)
        $web.DownloadFile("$Live$($was.preview)", $preview)
        if ((Get-Sha256 $file) -ne $was.sha256 -or (Get-Sha256 $preview) -ne $was.preview_sha256) {
            throw "${id}: the published files don't match the published list."
        }
        Write-Host "$id : kept the published files"
    } else {
        Copy-Item -LiteralPath $src.FullName $file
        Copy-Item -LiteralPath (Join-Path $Checked "$id.png") $preview
        Write-Host "$id : new files (sign them with tools\sign.ps1 once published)"
    }
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
        source_sha256  = $sourceSha
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
