#!/usr/bin/env bash
# Collects the corresponding source code for everything shipped in the bundle,
# so it can be published next to the binary download (GPL/LGPL compliance).
# Run inside an MSYS2 MINGW64 shell, after scripts/bundle.sh.
#
# usage: collect_sources.sh <bundle-dir> <out-dir> <mat2-checkout> <pysite-dir> <exiftool-version>
#
# Exits with an error (and lists what is missing in <out-dir>/MISSING.txt) if the
# source for any shipped package could not be downloaded, so a release is never
# published without its source.
set -uo pipefail

BUNDLE="$(realpath "${1:?bundle dir}")"
OUT="$(realpath -m "${2:?output dir}")"
MAT2="$(realpath "${3:?mat2 checkout}")"
PYSITE="$(realpath "${4:?pysite dir}")"
EXIFVER="${5:?exiftool version}"
PREFIX="${MINGW_PREFIX:-/mingw64}"
PACMAN_DB="${PACMAN_DB:-/var/lib/pacman/local}"
RECIPE_REPO="$(pwd)"

mkdir -p "$OUT/msys2" "$OUT/other"
MISSING="$OUT/MISSING.txt"
SHIPPED="$OUT/PACKAGES-SHIPPED.txt"
: > "$MISSING"
: > "$SHIPPED"

echo "== 1. MSYS2 packages that supplied files to the bundle"
# Everything copied from $PREFIX keeps its relative path inside the bundle,
# so bundle/bin/x.dll came from $PREFIX/bin/x.dll, and so on.
( cd "$BUNDLE" && find bin lib etc share -type f ) | sed "s#^#$PREFIX/#" \
  | xargs -n 200 pacman -Qoq 2>/dev/null | sort -u > "$OUT/owners.txt" || true
echo "   $(wc -l < "$OUT/owners.txt") packages"

echo "== 2. Download each package's source tarball from the MSYS2 mirror"
while read -r pkg; do
  [ -z "$pkg" ] && continue
  d="$(ls -d "$PACMAN_DB/$pkg"-[0-9]* 2>/dev/null | head -n1)"
  if [ -z "$d" ]; then echo "$pkg (not found in package database)" >> "$MISSING"; continue; fi
  ver="$(awk '/^%VERSION%/{getline; print; exit}' "$d/desc")"
  base="$(awk '/^%BASE%/{getline; print; exit}' "$d/desc")"
  [ -z "$base" ] && base="mingw-w64-${pkg#mingw-w64-x86_64-}"
  file="$base-$ver.src.tar.zst"
  echo "$pkg $ver  ->  $file" >> "$SHIPPED"
  if [ ! -s "$OUT/msys2/$file" ]; then
    if ! curl -fsSL --retry 3 --globoff -o "$OUT/msys2/$file" \
         "https://mirror.msys2.org/mingw/sources/$file"; then
      rm -f "$OUT/msys2/$file"
      echo "$pkg  (wanted $file)" >> "$MISSING"
    fi
  fi
done < "$OUT/owners.txt"

echo "== 3. mat2 source (exact commit that was built)"
MAT2_SHORT="$(git -C "$MAT2" rev-parse --short HEAD)"
git -C "$MAT2" archive --format=tar.gz --prefix="mat2-$MAT2_SHORT/" HEAD \
  -o "$OUT/other/mat2-$MAT2_SHORT.tar.gz" || echo "mat2 source archive" >> "$MISSING"

echo "== 4. mutagen source (installed from PyPI, so not an MSYS2 package)"
MUT_VER="$(ls "$PYSITE" | sed -n 's/^mutagen-\(.*\)\.dist-info$/\1/p' | head -n1)"
if [ -n "$MUT_VER" ]; then
  python - "$MUT_VER" "$OUT/other" <<'PY' || echo "mutagen $MUT_VER sdist" >> "$MISSING"
import json, sys, urllib.request, os
ver, out = sys.argv[1], sys.argv[2]
meta = json.load(urllib.request.urlopen(f"https://pypi.org/pypi/mutagen/{ver}/json"))
sdist = [u for u in meta["urls"] if u["packagetype"] == "sdist"][0]
urllib.request.urlretrieve(sdist["url"], os.path.join(out, sdist["filename"]))
print("downloaded", sdist["filename"])
PY
else
  echo "mutagen (version not found in $PYSITE)" >> "$MISSING"
fi

echo "== 5. ExifTool source (the Windows exe bundles the Perl script plus a Perl runtime)"
curl -fsSL --retry 3 -o "$OUT/other/Image-ExifTool-$EXIFVER.tar.gz" \
  "https://sourceforge.net/projects/exiftool/files/Image-ExifTool-$EXIFVER.tar.gz/download" \
  || { rm -f "$OUT/other/Image-ExifTool-$EXIFVER.tar.gz"; echo "ExifTool $EXIFVER source" >> "$MISSING"; }

echo "== 6. The build recipe (scripts, workflow, Windows patches for mat2)"
git -C "$RECIPE_REPO" archive --format=tar.gz --prefix="mat2-windows-recipe/" HEAD \
  -o "$OUT/other/mat2-windows-recipe.tar.gz" || echo "build recipe archive" >> "$MISSING"

cat > "$OUT/README-SOURCES.txt" <<EOF
Corresponding source code for "mat2 for Windows (unofficial build)"
====================================================================

This archive contains the source code for the programs shipped in the Windows
download, so you can study, rebuild and modify them (GPL / LGPL requirement).

msys2/   Source packages (PKGBUILD recipe + upstream source + patches) for every
         MSYS2 package whose files are in the download: Python, GLib, GdkPixbuf,
         librsvg, cairo, Poppler, fontconfig, the GCC runtime libraries and more.
         The list is in PACKAGES-SHIPPED.txt. Unpack with: tar --zstd -xf FILE
other/   mat2 (the exact commit built), mutagen, ExifTool, and the build recipe
         (the scripts and workflow that assemble the download, including the
         small Windows fixes applied to mat2).

mat2:      https://github.com/jvoisin/mat2
MSYS2:     https://www.msys2.org/  (package sources: https://mirror.msys2.org/mingw/sources/)
ExifTool:  https://exiftool.org/
EOF

echo
if [ -s "$MISSING" ]; then
  echo "ERROR: source could not be collected for:"
  cat "$MISSING"
  exit 1
fi
rm -f "$MISSING" "$OUT/owners.txt"
echo "All sources collected: $(ls "$OUT/msys2" | wc -l) MSYS2 source packages, $(ls "$OUT/other" | wc -l) other archives."
du -sh "$OUT"
