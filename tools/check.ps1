<#
check.ps1 - the gallery's safety checks for one or more wallpaper folders.

  powershell tools\check.ps1 -Livewall C:\path\livewall.exe [-Ids a,b] [-Staged dir] [-Out dir]

For each wallpapers\<id> folder:
  1. The folder holds exactly info.json and one wallpaper.<hlsl|mp4|gif|png|jpg>,
     within the size limits, and info.json follows the rules in SHARING.md.
  2. Shaders are plain UTF-8 text with no #include.
  3. livewall itself opens and draws the wallpaper (livewall.exe -check), the
     same way it does on people's PCs, and measures the work per frame.
     Shaders may not draw one flat colour or take more than $MaxRatio times
     the work of tools\reference.hlsl, measured in the same run.

-Staged: a folder with <id>\wallpaper.* files to test instead of the
uploaded ones (the CI passes the copies rebuilt by ffmpeg).
Writes <Out>\<id>.png previews and <Out>\results.json. Exit code 1 if any
wallpaper failed.
#>
param(
    [Parameter(Mandatory = $true)][string]$Livewall,
    [string[]]$Ids,
    [string]$Staged,
    [string]$Out = "$PSScriptRoot\..\out"
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path "$PSScriptRoot\..").Path
$MaxRatio = 15
$Kinds = @{ '.hlsl' = 64KB; '.png' = 10MB; '.jpg' = 10MB; '.gif' = 15MB; '.mp4' = 50MB }
$Licenses = @('MIT', 'CC0-1.0', 'CC-BY-4.0')

New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$Work = Join-Path ([IO.Path]::GetTempPath()) "livewall-gallery-check"
Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Work | Out-Null

# Runs livewall.exe -check on a file copied to a plain path; returns its findings.
function Invoke-Check([string]$file, [string]$name) {
    $dir = Join-Path $Work $name
    New-Item -ItemType Directory -Force $dir | Out-Null
    $copy = Join-Path $dir ("wallpaper" + [IO.Path]::GetExtension($file).ToLower())
    Copy-Item -LiteralPath $file $copy
    $png = Join-Path $dir "preview.png"
    $p = Start-Process -FilePath $Livewall -ArgumentList "-check `"$copy`" `"$png`"" -Wait -PassThru
    $r = @{ ok = $false; kind = 'unknown'; us = 0; blank = $false; png = $png; exit = $p.ExitCode }
    if (Test-Path "$png.txt") {
        foreach ($line in Get-Content "$png.txt") {
            $k, $v = $line -split '=', 2
            switch ($k) {
                'ok' { $r.ok = $v -eq '1' }
                'kind' { $r.kind = $v }
                'us_per_frame' { $r.us = [int]$v }
                'blank' { $r.blank = $v -eq '1' }
            }
        }
    }
    return $r
}

# Rules for the folder and info.json; returns a list of problems.
function Test-Folder([string]$id, [string]$dir) {
    $bad = New-Object System.Collections.Generic.List[string]
    if ($id -cnotmatch '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$') {
        $bad.Add("The folder name must be 3 to 40 lowercase letters, numbers and dashes.")
    }
    $items = @(Get-ChildItem -LiteralPath $dir -Force)
    foreach ($i in $items) {
        if ($i.PSIsContainer) { $bad.Add("No folders inside a wallpaper folder ($($i.Name)).") }
    }
    $files = @($items | Where-Object { -not $_.PSIsContainer })
    $walls = @($files | Where-Object { $_.Name -match '^wallpaper\.' })
    foreach ($f in $files) {
        if ($f.Name -cne 'info.json' -and ($f.Name -cnotmatch '^wallpaper\.(hlsl|mp4|gif|png|jpg)$')) {
            $bad.Add("Only info.json and one wallpaper file are allowed ($($f.Name)).")
        }
    }
    if ($walls.Count -ne 1) { $bad.Add("There must be exactly one wallpaper.* file.") }
    foreach ($w in $walls) {
        $ext = $w.Extension.ToLower()
        if ($Kinds.ContainsKey($ext) -and $w.Length -gt $Kinds[$ext]) {
            $bad.Add("$($w.Name) is $([math]::Round($w.Length / 1MB, 1)) MB; the limit for $ext is $($Kinds[$ext] / 1MB) MB.")
        }
        if ($ext -eq '.hlsl') {
            $bytes = [IO.File]::ReadAllBytes($w.FullName)
            try {
                $text = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes)
                if ($text -match '(?m)^\s*#\s*include') { $bad.Add("Shaders may not use #include.") }
                if ($text.IndexOf([char]0) -ge 0) { $bad.Add("The shader file contains a null character.") }
            } catch {
                $bad.Add("The shader must be plain UTF-8 text.")
            }
        }
    }
    $infoPath = Join-Path $dir 'info.json'
    if (-not (Test-Path -LiteralPath $infoPath)) {
        $bad.Add("info.json is missing.")
    } else {
        try {
            $info = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $known = @('name', 'author', 'description', 'tags', 'license')
            foreach ($p in $info.PSObject.Properties.Name) {
                if ($known -notcontains $p) { $bad.Add("info.json has an unknown field: $p.") }
            }
            if (-not ($info.name -is [string]) -or $info.name.Length -lt 3 -or $info.name.Length -gt 40) {
                $bad.Add("name must be 3 to 40 characters.")
            }
            if (-not ($info.author -is [string]) -or $info.author -notmatch '^[A-Za-z0-9-]{1,39}$') {
                $bad.Add("author must be a GitHub name.")
            }
            if ($null -ne $info.description -and (-not ($info.description -is [string]) -or $info.description.Length -gt 200)) {
                $bad.Add("description must be up to 200 characters.")
            }
            $tags = @($info.tags | Where-Object { $null -ne $_ })
            if ($tags.Count -gt 5) { $bad.Add("At most 5 tags.") }
            foreach ($t in $tags) {
                if (-not ($t -is [string]) -or $t -cnotmatch '^[a-z0-9-]{1,20}$') { $bad.Add("Tags must be lowercase, up to 20 characters ($t).") }
            }
            if ($Licenses -notcontains $info.license) { $bad.Add("license must be one of: $($Licenses -join ', ').") }
        } catch {
            $bad.Add("info.json is not valid JSON.")
        }
    }
    return , $bad
}

if (-not (Test-Path $Livewall)) { throw "livewall.exe not found: $Livewall" }
$Livewall = (Resolve-Path $Livewall).Path
if (-not $Ids) { $Ids = @(Get-ChildItem "$Root\wallpapers" -Directory | ForEach-Object Name) }

# The reference: the fastest of three runs, so a GPU still warming up (or a
# busy CI machine) doesn't make the yardstick longer and let a heavy shader
# through. It is measured again at the end, and the faster time is used.
function Measure-Reference {
    $best = 0
    foreach ($i in 1..3) {
        $r = Invoke-Check "$Root\tools\reference.hlsl" "_reference$i"
        if (-not $r.ok -or $r.us -le 0) { throw "The reference shader did not run; is livewall.exe working here?" }
        if (-not $best -or $r.us -lt $best) { $best = $r.us }
    }
    return $best
}
$ref = @{ us = (Measure-Reference) }
Write-Host "reference shader: $($ref.us) us per frame"

$results = @()
foreach ($id in $Ids) {
    $dir = Join-Path "$Root\wallpapers" $id
    $res = [ordered]@{ id = $id; ok = $false; kind = ''; us_per_frame = 0; ratio = 0.0; problems = @() }
    if (-not (Test-Path -LiteralPath $dir)) {
        $res.problems = @("The folder was removed.")
        $res.ok = $true # removing a wallpaper is allowed
        $results += [pscustomobject]$res
        continue
    }
    $problems = Test-Folder $id $dir
    $wall = Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -cmatch '^wallpaper\.(hlsl|mp4|gif|png|jpg)$' } | Select-Object -First 1
    if ($wall -and $problems.Count -eq 0) {
        $file = $wall.FullName
        if ($Staged -and $wall.Extension -ne '.hlsl') {
            $file = Get-ChildItem -LiteralPath (Join-Path $Staged $id) -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'wallpaper.*' } | Select-Object -First 1 -ExpandProperty FullName
            if (-not $file) { $problems.Add("The rebuilt copy of the file is missing (ffmpeg could not read it).") }
        }
        if ($file) {
            $r = Invoke-Check $file $id
            $res.kind = $r.kind
            $res.us_per_frame = $r.us
            if (-not $r.ok) {
                $problems.Add("livewall could not open or draw it. For a shader, the compiler error is in livewall's log.")
            } elseif ($r.kind -eq 'shader') {
                $res.ratio = [math]::Round($r.us / $ref.us, 1)
                if ($r.blank) { $problems.Add("It draws a single flat colour.") }
                if ($res.ratio -gt $MaxRatio) { $problems.Add("It takes $($res.ratio) times the work of the reference shader; the limit is $MaxRatio.") }
            }
            if ($r.ok) { Copy-Item $r.png (Join-Path $Out "$id.png") -Force }
        }
    }
    $res.problems = @($problems)
    $res.ok = $problems.Count -eq 0
    $results += [pscustomobject]$res
    $mark = if ($res.ok) { 'PASS' } else { 'FAIL' }
    Write-Host "$mark $id ($($res.kind), $($res.us_per_frame) us, x$($res.ratio))"
    foreach ($p in $res.problems) { Write-Host "     - $p" }
}

# Measure the reference again; if it is faster now, redo the shader limits.
$again = Measure-Reference
if ($again -lt $ref.us) {
    Write-Host "reference shader, measured again: $again us per frame"
    $ref.us = $again
    foreach ($res in $results | Where-Object { $_.kind -eq 'shader' -and $_.us_per_frame -gt 0 }) {
        $res.ratio = [math]::Round($res.us_per_frame / $ref.us, 1)
        if ($res.ratio -gt $MaxRatio -and -not ($res.problems -match 'times the work')) {
            $res.problems = @($res.problems) + "It takes $($res.ratio) times the work of the reference shader; the limit is $MaxRatio."
            $res.ok = $false
            Write-Host "FAIL $($res.id): $($res.ratio) times the reference"
        }
    }
}

$results | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $Out 'results.json')
if (@($results | Where-Object { -not $_.ok }).Count) { exit 1 }
exit 0
