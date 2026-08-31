#!/usr/bin/env bash
# Regenerate the web-sized images that the site actually serves.
#
# Masters live in _originals/ (the leading underscore keeps Jekyll from
# publishing them), so this script is safe to re-run at any time:
#
#   _originals/images/nasif-photo.png -> images/nasif-photo.{webp,jpg}  (640px)
#   _originals/tn/images/<name>.<ext> -> tn/images/<name>.{webp,<ext>}  (480px)
#
# Targets are ~2x the widest slot each image occupies in the 800px layout, so
# hi-dpi screens still get a sharp image without multi-megabyte downloads.
# Every image ships as WebP plus a same-format fallback for <picture>.

set -euo pipefail

AVATAR_PX=640
THUMB_PX=480
WEBP_Q=82
JPEG_Q=85

# Resizing an image that is already about the right size gains nothing and can
# cost a lot: resampling a small palette PNG turns 19 flat colours into
# thousands of interpolated ones, which inflated compiler.png from 15K to 66K.
# So leave anything within this much of the target untouched.
SLACK=115  # percent

# best_webp <src> <dest> — writes whichever of lossy/lossless WebP is smaller.
# Screenshots and line art usually win on lossless, photos on lossy.
best_webp() {
    local src=$1 dest=$2
    # The .webp suffixes matter: ImageMagick picks the encoder by extension.
    magick "$src" -define webp:method=6 -quality $WEBP_Q "$dest.lossy.webp"
    magick "$src" -define webp:method=6 -define webp:lossless=true "$dest.lossless.webp"
    if [ "$(stat -c%s "$dest.lossy.webp")" -le "$(stat -c%s "$dest.lossless.webp")" ]; then
        mv "$dest.lossy.webp" "$dest"; rm "$dest.lossless.webp"
    else
        mv "$dest.lossless.webp" "$dest"; rm "$dest.lossy.webp"
    fi
}

# keep_smaller <candidate> <master> <dest> — the fallback only has to serve
# browsers without WebP, so never ship something bigger than the master.
keep_smaller() {
    local candidate=$1 master=$2 dest=$3
    if [ "$(stat -c%s "$candidate")" -le "$(stat -c%s "$master")" ]; then
        mv "$candidate" "$dest"
    else
        rm "$candidate"; cp "$master" "$dest"
    fi
}

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

echo "profile photo"
avatar=_originals/images/nasif-photo.png
magick "$avatar" -strip -alpha background -resize ${AVATAR_PX}x${AVATAR_PX} "$work/avatar.png"
best_webp "$work/avatar.png" images/nasif-photo.webp
magick "$work/avatar.png" -interlace JPEG -quality $JPEG_Q images/nasif-photo.jpg
printf '  %-34s %7s -> webp %6s / jpg %6s\n' nasif-photo \
    "$(stat -c%s "$avatar")" "$(stat -c%s images/nasif-photo.webp)" \
    "$(stat -c%s images/nasif-photo.jpg)"

echo "thumbnails"
for src in _originals/tn/images/*; do
    name=$(basename "$src")
    stem=${name%.*}
    ext=${name##*.}

    longest=$(magick identify -format '%[fx:max(w,h)]' "$src[0]")
    prepared=$work/$name
    if [ "$longest" -gt $(( THUMB_PX * SLACK / 100 )) ]; then
        # -coalesce keeps animated GIFs animating through the resize.
        magick "$src" -strip -coalesce -alpha background \
            -resize ${THUMB_PX}x${THUMB_PX} "$prepared"
    else
        magick "$src" -strip "$prepared"
    fi

    best_webp "$prepared" "tn/images/$stem.webp"

    case "$ext" in
        gif)      magick "$prepared" -layers optimize "$work/fb.$ext" ;;
        jpg|jpeg) magick "$prepared" -interlace JPEG -quality $JPEG_Q "$work/fb.$ext" ;;
        *)        magick "$prepared" -define png:compression-level=9 "$work/fb.$ext" ;;
    esac
    keep_smaller "$work/fb.$ext" "$src" "tn/images/$name"

    printf '  %-34s %7s -> webp %6s / %-4s %6s\n' "$stem" \
        "$(stat -c%s "$src")" "$(stat -c%s "tn/images/$stem.webp")" \
        "$ext" "$(stat -c%s "tn/images/$name")"
done
