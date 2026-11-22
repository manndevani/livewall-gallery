<#
likes.ps1 - adds likes to the gallery list (site\index.json).

  pwsh tools/likes.ps1 -Site site

Each wallpaper has one post in the repository's Discussions, in the
"Wallpapers" category, titled "<name> (<id>)". People like a wallpaper by
upvoting its post. This script:
  1. creates the post for any wallpaper that doesn't have one yet,
  2. writes each post's upvote count ("likes") and address ("discussion")
     into index.json.

It runs in the publish job with the workflow's own token (GITHUB_TOKEN,
discussions: write); pull requests never run it. If Discussions or the
category aren't set up, it says so and leaves index.json as it is, so
publishing still works.
#>
param([string]$Site = "$PSScriptRoot\..\site")
$ErrorActionPreference = 'Stop'

$token = $env:GITHUB_TOKEN
$repo = $env:GITHUB_REPOSITORY        # owner/name
if (-not $token -or -not $repo) { Write-Host 'likes: no token or repository; skipped.'; exit 0 }
$owner, $name = $repo.Split('/')
$headers = @{ Authorization = "Bearer $token"; 'User-Agent' = 'livewall-gallery' }

function Invoke-Graph([string]$query, [hashtable]$vars) {
    $body = @{ query = $query; variables = $vars } | ConvertTo-Json -Depth 10 -Compress
    $r = Invoke-RestMethod -Method Post -Uri 'https://api.github.com/graphql' -Headers $headers -Body $body -ContentType 'application/json'
    if ($r.errors) { throw ($r.errors | ForEach-Object { $_.message }) -join '; ' }
    $r.data
}

$indexPath = (Resolve-Path (Join-Path $Site 'index.json')).Path
$index = Get-Content -Raw -Encoding UTF8 $indexPath | ConvertFrom-Json

$d = Invoke-Graph 'query($o:String!,$n:String!){repository(owner:$o,name:$n){id hasDiscussionsEnabled discussionCategories(first:50){nodes{id name}}}}' @{ o = $owner; n = $name }
$cat = $d.repository.discussionCategories.nodes | Where-Object { $_.name -eq 'Wallpapers' } | Select-Object -First 1
if (-not $d.repository.hasDiscussionsEnabled -or -not $cat) {
    Write-Host "::warning::likes: turn on Discussions and add a category named 'Wallpapers' to count likes. Published without likes."
    exit 0
}

# Every post in the category, by the wallpaper id at the end of its title.
$posts = @{}
$after = $null
do {
    $q = 'query($o:String!,$n:String!,$c:ID!,$a:String){repository(owner:$o,name:$n){discussions(first:100,after:$a,categoryId:$c){pageInfo{hasNextPage endCursor} nodes{title url upvoteCount author{login}}}}}'
    $page = (Invoke-Graph $q @{ o = $owner; n = $name; c = $cat.id; a = $after }).repository.discussions
    foreach ($p in $page.nodes) {
        # Only posts made by this workflow count, so nobody can make a look-alike post.
        if ($p.author.login -ne 'github-actions') { continue }
        if ($p.title -match '\(([a-z0-9][a-z0-9-]{1,38}[a-z0-9])\)$' -and -not $posts.ContainsKey($Matches[1])) { $posts[$Matches[1]] = $p }
    }
    $after = $page.pageInfo.endCursor
} while ($page.pageInfo.hasNextPage)

$pages = "https://$owner.github.io/$name"
foreach ($w in $index.wallpapers) {
    $p = $posts[$w.id]
    if (-not $p) {
        $body = @"
![$($w.name)]($pages/$($w.preview))

**$($w.name)** by $($w.author)

$($w.description)

Like this wallpaper? Upvote this post (the arrow at the top left). Comments and ideas are welcome too.

Get it in livewall: **Settings → Community**, or see it on the [gallery page]($pages/#w/$($w.id)).
"@
        $m = 'mutation($r:ID!,$c:ID!,$t:String!,$b:String!){createDiscussion(input:{repositoryId:$r,categoryId:$c,title:$t,body:$b}){discussion{title url upvoteCount}}}'
        $p = (Invoke-Graph $m @{ r = $d.repository.id; c = $cat.id; t = "$($w.name) ($($w.id))"; b = $body }).createDiscussion.discussion
        Write-Host "likes: made a post for $($w.id): $($p.url)"
    }
    $w | Add-Member -NotePropertyName likes -NotePropertyValue ([int]$p.upvoteCount) -Force
    $w | Add-Member -NotePropertyName discussion -NotePropertyValue $p.url -Force
}

[IO.File]::WriteAllText($indexPath, ($index | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
Write-Host "likes: counted for $(@($index.wallpapers).Count) wallpapers"
