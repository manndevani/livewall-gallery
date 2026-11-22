#!/usr/bin/env bash
# prepare.sh - the Linux half of the gallery checks (see gallery.yml).
#
#   tools/prepare.sh <base-ref or ""> <outside-ok 0|1> <staged-dir>
#
# 1. Works out which wallpaper folders to check: the ones a pull request
#    changes, or all of them. Writes their names to <staged-dir>/ids.txt.
#    Folder names are only ever used after they pass the name rule, so a
#    strange folder name can't sneak into a command.
# 2. Refuses changes outside wallpapers/ unless <outside-ok> is 1.
# 3. Scans the wallpaper files for viruses with ClamAV.
# 4. Rebuilds videos, GIFs and pictures with ffmpeg into <staged-dir>/<id>/,
#    dropping hidden extra data. Those copies are what gets checked and
#    published. A file ffmpeg can't read gets no copy, and fails the check.
set -euo pipefail
base="$1"
outside_ok="$2"
staged="$3"
mkdir -p "$staged"
: > "$staged/ids.txt"
name_rule='^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$'
failed=0

if [ -n "$base" ]; then
    mapfile -d '' changed < <(git diff -z --name-only "$base"...HEAD)
else
    mapfile -d '' changed < <(git ls-files -z wallpapers)
fi

declare -A ids=()
for path in "${changed[@]}"; do
    case "$path" in
        wallpapers/*/*)
            id="${path#wallpapers/}"
            id="${id%%/*}"
            if [[ "$id" =~ $name_rule ]]; then
                ids["$id"]=1
            else
                echo "::error::A wallpaper folder name must be 3 to 40 lowercase letters, numbers and dashes."
                failed=1
            fi
            ;;
        *)
            if [ "$outside_ok" != 1 ]; then
                echo "::error::Pull requests may only change files under wallpapers/ (this one changes $(printf '%q' "$path"))."
                failed=1
            fi
            ;;
    esac
done
for id in "${!ids[@]}"; do echo "$id" >> "$staged/ids.txt"; done
sort -o "$staged/ids.txt" "$staged/ids.txt"
echo "Wallpapers to check: $(wc -l < "$staged/ids.txt")"
[ "$failed" = 0 ] || exit 1

# Virus scan of every file in the folders being checked.
while read -r id; do
    [ -d "wallpapers/$id" ] || continue
    if ! clamscan --recursive --infected --no-summary "wallpapers/$id"; then
        echo "::error::ClamAV flagged a file in wallpapers/$id."
        failed=1
    fi
done < "$staged/ids.txt"
[ "$failed" = 0 ] || exit 1

# Fresh copies of media, made by ffmpeg.
while read -r id; do
    dir="wallpapers/$id"
    out="$staged/$id"
    mkdir -p "$out"
    for src in "$dir"/wallpaper.mp4 "$dir"/wallpaper.gif "$dir"/wallpaper.png "$dir"/wallpaper.jpg; do
        [ -f "$src" ] || continue
        ff=(ffmpeg -nostdin -hide_banner -loglevel error -i "$src" -map_metadata -1)
        case "$src" in
            *.mp4) "${ff[@]}" -t 120 -an -vf "scale='min(1920,iw)':-2" -c:v libx264 -preset medium -crf 22 \
                       -pix_fmt yuv420p -movflags +faststart -y "$out/wallpaper.mp4" ;;
            *.gif) "${ff[@]}" -vf "scale='min(1280,iw)':-2:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse" \
                       -y "$out/wallpaper.gif" ;;
            *.png) "${ff[@]}" -vf "scale='min(3840,iw)':-2" -frames:v 1 -y "$out/wallpaper.png" ;;
            *.jpg) "${ff[@]}" -vf "scale='min(3840,iw)':-2" -frames:v 1 -q:v 2 -y "$out/wallpaper.jpg" ;;
        esac || { echo "::error::ffmpeg could not read $src."; rm -f "$out"/wallpaper.*; }
    done
done < "$staged/ids.txt"
exit 0
