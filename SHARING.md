# Sharing a wallpaper

## Steps

1. Make a free GitHub account if you don't have one.
2. Click **Fork** at the top of this page to get your own copy of the gallery.
3. In your copy, add a folder under `wallpapers/` named after your wallpaper, in lowercase letters, numbers and dashes, for example `wallpapers/rainy-window`.
4. Put two files in it:
   - your wallpaper, named `wallpaper.hlsl`, `wallpaper.mp4`, `wallpaper.gif`, `wallpaper.png` or `wallpaper.jpg`;
   - an `info.json` describing it (see below).
5. Open a **pull request**. The checks run by themselves within a few minutes and show their result, with a picture of your wallpaper, on the pull request.
6. A maintainer looks at it and adds it, or tells you what to change. Once added, it appears in livewall after the maintainer has signed it (usually the same day).

## info.json

```json
{
  "name": "Rainy Window",
  "author": "your-github-name",
  "description": "Slow drops running down a dark window.",
  "tags": ["calm", "dark"],
  "license": "MIT"
}
```

| Field | Rules |
|---|---|
| `name` | 3 to 40 characters. |
| `author` | Your GitHub name. |
| `description` | Up to 200 characters. |
| `tags` | Up to 5, each lowercase, up to 20 characters. |
| `license` | `MIT`, `CC0-1.0` or `CC-BY-4.0`. Everyone may use and share your wallpaper under it (for fan art: your own work in it; see the rules). |

## Rules

- **Only your own work.** You made it, or you have the right to share it under the license you chose. No art, logos or footage taken from games, films, brands or other people: no screenshots, game clips, official artwork or rips.
- **Fan art is welcome** if you drew, painted, animated or modelled it yourself: a character or place from a game or film, in your own work. Rules for fan art:
  - nothing copied or traced from the game or film, and no official logos;
  - add the tag `fan-art`, and name the game or film in the description;
  - your license covers only your own work; the characters still belong to their makers;
  - if the makers ask for it to be taken down, it will be.
- **Fine for everyone.** Nothing sexual, violent, hateful or shocking, and no flashing that could harm people with photosensitive epilepsy.
- **Only the two files.** No other files, folders or changes elsewhere in the gallery.
- **Size limits:** shader 64 KB, picture 10 MB, GIF 15 MB, video 50 MB and at most 2 minutes. Videos lose their sound.

## Shaders

Write a Shadertoy-style `mainImage()` as described in livewall's [shader guide](https://github.com/manndevani/LiveWallpaper/blob/main/docs/CUSTOM_SHADERS.md), and try it in livewall first (**Settings → Add wallpaper**).

The checks turn a shader down if it:

- doesn't compile, or uses `#include`;
- draws a single flat colour;
- takes more than 15 times the work of the reference shader ([`tools/reference.hlsl`](tools/reference.hlsl)). It runs behind people's work all day, so keep loops short.

Please also keep it calm and fairly dark, so desktop icons stay easy to read.
