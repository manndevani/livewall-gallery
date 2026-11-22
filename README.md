# livewall gallery

Free wallpapers for [livewall](https://github.com/manndevani/LiveWallpaper), shared by the people who use it.

Everything here is free to download and free to share. There are no accounts, no ads and no tracking: livewall only downloads the gallery list and the wallpapers you pick.

**Browse it:** https://manndevani.github.io/livewall-gallery/

## Getting a wallpaper

Open livewall's settings, choose the **Community** tab and click a wallpaper. livewall downloads it, checks its fingerprint and puts it on your desktop (or on the Lock screen tab, if that tab is open). This needs a livewall version newer than 0.2.1.

You can also download it from the [gallery page](https://manndevani.github.io/livewall-gallery/) and add it with **Settings → Add wallpaper**.

## Liking a wallpaper

Each wallpaper has a post under [Discussions](../../discussions/categories/wallpapers). Upvote the post to like the wallpaper (you need a free GitHub account). Likes are counted a few times a day; the most liked wallpapers come first on the gallery page and in livewall.

## Sharing your own

Anyone with a free GitHub account can share a wallpaper: a shader you wrote, or a video, GIF or picture you made. See [SHARING.md](SHARING.md) for the steps and the rules.

## How the gallery stays safe

Every wallpaper is checked by a computer and then by a person before anyone can download it:

1. **Only wallpaper files are allowed.** Shader code (`.hlsl`), videos (`.mp4`), GIFs and pictures (`.png`, `.jpg`). Never programs, scripts, zip files or anything else.
2. **Shaders can't reach your files.** A shader runs on the graphics card and can only work out pixel colours. livewall gives it no way to open files, use the internet or talk to other programs, and it refuses `#include` (the one way a shader could ask for a file).
3. **Every file is tested.** The checks open each wallpaper with livewall itself, draw it, and measure how much work it takes. A shader that doesn't compile, draws nothing, or is too heavy for an everyday wallpaper is turned down.
4. **Every file is scanned for viruses** with ClamAV.
5. **Videos, GIFs and pictures are rebuilt.** The gallery doesn't hand out the uploaded file: it makes a fresh copy with ffmpeg, which also drops hidden extra data (such as location in photos). What you download is that copy.
6. **A person approves every wallpaper** before it is added.
7. **livewall checks every download.** The gallery list holds a fingerprint (SHA-256) of each file, and livewall refuses a file that doesn't match.

Found something wrong with a wallpaper? [Open an issue](../../issues) and it will be looked at quickly.

## For maintainers

- `tools/check.ps1` runs the checks on your own PC: `powershell tools\check.ps1 -Livewall <path to livewall.exe>`.
- `.github/workflows/gallery.yml` runs them on every pull request. On `main`, and every 6 hours, it builds the gallery site (`index.json`, the files and previews, and the web page from `web/`), counts likes with `tools/likes.ps1`, and publishes it with GitHub Pages.
- Likes need **Discussions** turned on and a category named **Wallpapers** (Settings → General → Features → Discussions; then add the category). `likes.ps1` makes one post per wallpaper, as `github-actions`, and only counts posts made that way. Without the category the site is published without likes.
- GitHub pauses scheduled runs after 60 days without any change to the repository; a push or a manual run starts them again.
- Pull requests from other people may only change files under `wallpapers/`, and never run the publish job.
- To try the web page on your own PC: build the site with `build-index.ps1`, then serve the `site` folder with any local web server.

The tools in this repository are under the MIT license. Each wallpaper has its own license, given in its `info.json`.
