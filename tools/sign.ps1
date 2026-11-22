<#
sign.ps1 - the maintainer's signature on the gallery.

livewall only shows gallery wallpapers that are in signed.txt, a list of
each wallpaper's id and the fingerprints (SHA-256) of its file and preview,
signed with a key that stays on the maintainer's PC. Someone who got into
the GitHub account could change the files and index.json, but not sign
them, so livewall wouldn't show their changes.

  powershell tools\sign.ps1 -NewKey
      Once: makes the signing key in Windows' key store on this PC. It can't
      be copied out, and Windows asks for a password to protect it (and
      again each time it signs). Prints the public key to put into livewall
      (src/gallery.c, gallery_keys) and saves it as signing-key.txt.

  powershell tools\sign.ps1
      After a wallpaper is published: downloads the published list, shows
      each new or changed wallpaper (its files are saved for you to look
      at), asks whether to sign it, and writes signed.txt. Then commit and
      push signed.txt; the next publish puts it online.

  powershell tools\sign.ps1 -Remove some-id
      Takes a wallpaper off the signed list (for example if it turns out to
      be a problem). livewall stops showing it after the next publish.

Other options: -Site (where the gallery is published), -KeyName, and for
tests only -NoPassword (a key without the password prompt) and -Yes (sign
every new or changed wallpaper without asking). -StartOver begins a new list
when signed.txt's signature doesn't check out (see below).
#>
param(
    [switch]$NewKey,
    [string[]]$Remove = @(),
    [string]$Site = 'https://manndevani.github.io/livewall-gallery/',
    [string]$KeyName = 'livewall-gallery',
    [switch]$NoPassword,
    [switch]$Yes,
    [switch]$StartOver
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path "$PSScriptRoot\..").Path
$SignedPath = Join-Path $Root 'signed.txt'
$Head = "livewall gallery 1`n"
$Cng = 'System.Security.Cryptography'
$Site = $Site.TrimEnd('/') + '/'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Hex([byte[]]$b) { -join ($b | ForEach-Object { $_.ToString('x2') }) }
function Unhex([string]$s) { [byte[]]($(for ($i = 0; $i -lt $s.Length; $i += 2) { [Convert]::ToByte($s.Substring($i, 2), 16) })) }
function Get-Sha256([string]$path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLower() }

function Open-Key {
    if (-not [Security.Cryptography.CngKey]::Exists($KeyName)) {
        throw "There is no signing key named '$KeyName' on this PC. Make one with: tools\sign.ps1 -NewKey"
    }
    [Security.Cryptography.CngKey]::Open($KeyName)
}

function New-Signer($key) {
    $ec = New-Object "$Cng.ECDsaCng" -ArgumentList (, $key)
    $ec.HashAlgorithm = [Security.Cryptography.CngAlgorithm]::Sha256
    $ec
}

# ---- make the key ------------------------------------------------------
if ($NewKey) {
    if ([Security.Cryptography.CngKey]::Exists($KeyName)) {
        throw "A key named '$KeyName' already exists on this PC. Its public key is in signing-key.txt."
    }
    $p = New-Object "$Cng.CngKeyCreationParameters"
    $p.ExportPolicy = [Security.Cryptography.CngExportPolicies]::None
    $p.KeyUsage = [Security.Cryptography.CngKeyUsages]::Signing
    if (-not $NoPassword) {
        $p.UIPolicy = New-Object "$Cng.CngUIPolicy" -ArgumentList ([Security.Cryptography.CngUIProtectionLevels]::ProtectKey), 'livewall gallery signing key'
    }
    $key = [Security.Cryptography.CngKey]::Create([Security.Cryptography.CngAlgorithm]::ECDsaP256, $KeyName, $p)
    $blob = $key.Export([Security.Cryptography.CngKeyBlobFormat]::EccPublicBlob)   # 8-byte header, then X and Y
    $pub = Hex $blob[8..71]
    [IO.File]::WriteAllText((Join-Path $Root 'signing-key.txt'), "$pub`n")
    Write-Host "Made the signing key '$KeyName'. Its public key (also saved as signing-key.txt):"
    Write-Host ""
    Write-Host "    `"$pub`","
    Write-Host ""
    Write-Host "Put that line into livewall's src/gallery.c, in gallery_keys, then run tools\sign.ps1."
    return
}

# ---- read the current signed list ---------------------------------------
$key = Open-Key
$ec = New-Signer $key
$signed = [ordered]@{}   # id -> "sha psha"
$seq = 0
if (Test-Path -LiteralPath $SignedPath) {
    $bytes = [IO.File]::ReadAllBytes($SignedPath)
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    $at = $text.LastIndexOf("`nsig ")
    $good = $text.StartsWith($Head) -and $at -gt 0 -and $text.EndsWith("`n")
    if ($good) {
        $sig = $text.Substring($at + 5).Trim()
        $good = $sig -match '^[0-9a-f]{128}$' -and $ec.VerifyData($bytes[0..$at], (Unhex $sig))
    }
    $m = [regex]::Match($text, "^livewall gallery 1`nseq (\d{1,9})`n")
    if ($m.Success) { $seq = [int]$m.Groups[1].Value }
    if (-not $good) {
        if (-not $StartOver) {
            throw "signed.txt doesn't carry this key's signature: something changed it without the key. Look at its history (git log -p signed.txt). To begin a new list and approve every wallpaper again, run with -StartOver."
        }
        Write-Warning "signed.txt doesn't carry this key's signature; starting a new list."
    } else {
        foreach ($line in $text.Substring(0, $at).Split("`n") | Select-Object -Skip 2) {
            if ($line -match '^([a-z0-9-]{3,40}) ([0-9a-f]{64}) ([0-9a-f]{64})$') { $signed[$Matches[1]] = "$($Matches[2]) $($Matches[3])" }
        }
    }
}

# ---- compare with what is published ------------------------------------
$web = New-Object Net.WebClient
$index = [Text.Encoding]::UTF8.GetString($web.DownloadData("${Site}index.json")) | ConvertFrom-Json
$review = Join-Path $env:TEMP 'livewall-review'
$next = [ordered]@{}
$changed = $false
foreach ($w in @($index.wallpapers)) {
    $id = $w.id
    if ($id -notmatch '^[a-z0-9-]{3,40}$' -or $w.sha256 -notmatch '^[0-9a-f]{64}$' -or $w.preview_sha256 -notmatch '^[0-9a-f]{64}$') {
        Write-Warning "Skipping a broken entry in the published list: $id"
        continue
    }
    $pair = "$($w.sha256) $($w.preview_sha256)"
    if ($Remove -contains $id) { continue }
    if ($signed[$id] -eq $pair) { $next[$id] = $pair; continue }

    # New or changed: fetch both files and check them against the list.
    $dir = Join-Path $review $id
    New-Item -ItemType Directory -Force $dir | Out-Null
    $file = Join-Path $dir (Split-Path -Leaf $w.file)
    $prev = Join-Path $dir 'preview.png'
    $web.DownloadFile("$Site$($w.file)", $file)
    $web.DownloadFile("$Site$($w.preview)", $prev)
    if ((Get-Sha256 $file) -ne $w.sha256 -or (Get-Sha256 $prev) -ne $w.preview_sha256) {
        Write-Warning "$id : the published files don't match the published list. Not signed."
        continue
    }
    $what = if ($signed.Contains($id)) { 'CHANGED' } else { 'NEW' }
    Write-Host ""
    Write-Host "$what  $id  '$($w.name)' by $($w.author)  ($($w.kind), $([math]::Round($w.size / 1KB)) KB, $($w.license))"
    Write-Host "      files to look at: $dir"
    $ok = $Yes
    if (-not $ok) { $ok = (Read-Host "      Sign it? (y/n)") -eq 'y' }
    if ($ok) { $next[$id] = $pair; $changed = $true }
}
foreach ($id in $signed.Keys) {
    if (-not $next.Contains($id)) { Write-Host "Off the list: $id"; $changed = $true }
}
if (-not $changed -and -not $StartOver) {
    Write-Host "Nothing new to sign; signed.txt is up to date ($($next.Count) wallpapers)."
    return
}

# ---- sign and write -----------------------------------------------------
$body = $Head + "seq $($seq + 1)`n"
foreach ($id in $next.Keys | Sort-Object) { $body += "$id $($next[$id])`n" }
$data = [Text.Encoding]::ASCII.GetBytes($body)
$sig = $ec.SignData($data)                       # r and s, 32 bytes each
if (-not $ec.VerifyData($data, $sig)) { throw "The new signature didn't check out." }
[IO.File]::WriteAllBytes($SignedPath, [Text.Encoding]::ASCII.GetBytes($body + "sig $(Hex $sig)`n"))
Write-Host ""
Write-Host "signed.txt: $($next.Count) wallpapers, seq $($seq + 1). Commit and push it; the next publish puts it online."
