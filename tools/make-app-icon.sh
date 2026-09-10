#!/usr/bin/env bash
# Cuts every app icon size from one square source.
#
#   tools/make-app-icon.sh branding/logo.png
#
# The icons were cut by hand the first time, which is fine once and a trap the
# second: twenty files across two platforms, and the one nobody notices missing
# is the one a store rejects the upload for.
#
# **Changing an app icon is not a cosmetic change.** A person who has used a
# board for years finds it by the shape on the home screen, not by reading the
# name under it — one parent's whole report of an update was that their son
# "can't find it with visual recognition" any more. Before 1.0 that cost is
# nobody's; after it, it is somebody's, and this script is not the place that
# decision gets made.
set -euo pipefail

SOURCE="${1:-}"
if [ -z "$SOURCE" ] || [ ! -f "$SOURCE" ]; then
  echo "usage: $(basename "$0") <square-png>" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

width=$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth/{print $2}')
height=$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight/{print $2}')
if [ "$width" != "$height" ]; then
  echo "error: $SOURCE is ${width}x${height}; an app icon is square." >&2
  exit 1
fi
if [ "$width" -lt 1024 ]; then
  echo "error: $SOURCE is ${width}px; the App Store wants 1024." >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# **iOS refuses an icon with an alpha channel** — the upload fails validation
# with a message that does not say which of the twenty files is at fault. A
# logo drawn on transparency has to be given a ground, and white is the one
# this logo was drawn against.
#
# Composited rather than merely stripped: dropping the channel leaves whatever
# was under the transparent pixels, which is usually black.
# sips composites onto white when it writes a format that cannot carry alpha,
# so the flatten goes out through JPEG and back. Quality is irrelevant here:
# every result is immediately resampled, and one round trip at maximum quality
# costs less than the resampling that follows. The check at the end is what
# actually holds the guarantee.
flat="$work/flat.png"
sips -s format jpeg -s formatOptions best "$SOURCE" --out "$work/flat.jpg" >/dev/null
sips -s format png "$work/flat.jpg" --out "$flat" >/dev/null

ios=app/ios/Runner/Assets.xcassets/AppIcon.appiconset
android=app/android/app/src/main/res

cut() { # cut <source> <px> <destination>
  sips -Z "$2" "$1" --out "$3" >/dev/null
}

# Every entry in Contents.json, at the pixel size its point size and scale
# come to. 83.5@2x is 167 and is the one that gets forgotten.
for spec in \
  "20:Icon-App-20x20@1x.png" \
  "40:Icon-App-20x20@2x.png" \
  "60:Icon-App-20x20@3x.png" \
  "29:Icon-App-29x29@1x.png" \
  "58:Icon-App-29x29@2x.png" \
  "87:Icon-App-29x29@3x.png" \
  "40:Icon-App-40x40@1x.png" \
  "80:Icon-App-40x40@2x.png" \
  "120:Icon-App-40x40@3x.png" \
  "120:Icon-App-60x60@2x.png" \
  "180:Icon-App-60x60@3x.png" \
  "76:Icon-App-76x76@1x.png" \
  "152:Icon-App-76x76@2x.png" \
  "167:Icon-App-83.5x83.5@2x.png" \
  "1024:Icon-App-1024x1024@1x.png"
do
  cut "$flat" "${spec%%:*}" "$ios/${spec##*:}"
done

# Android keeps the alpha: a launcher icon is masked to the device's own shape,
# and a white square inside a circle is what a flattened one looks like there.
for spec in \
  "48:mdpi" "72:hdpi" "96:xhdpi" "144:xxhdpi" "192:xxxhdpi"
do
  cut "$SOURCE" "${spec%%:*}" "$android/mipmap-${spec##*:}/ic_launcher.png"
done

# What the store listing and the site use, kept beside the icons they were cut
# from so there is one source and not three.
cp "$SOURCE" branding/logo.png

for f in "$ios"/*.png; do
  if [ "$(sips -g hasAlpha "$f" | awk '/hasAlpha/{print $2}')" != "no" ]; then
    echo "error: $f still has an alpha channel; iOS will refuse the upload." >&2
    exit 1
  fi
done

echo "Cut $(ls "$ios"/*.png | wc -l | tr -d ' ') iOS icons and 5 Android ones."
echo "iOS icons carry no alpha channel."
