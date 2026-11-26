#!/usr/bin/env bash
# Builds a portable, relocatable folder: Python + GTK-stack libs + mat2.
# Run inside an MSYS2 MINGW64 shell.
# usage: bundle.sh <outdir> <mat2-checkout> <pysite-dir> <exiftool-dir>
set -euo pipefail

OUT="$(realpath -m "${1:?outdir}")"
MAT2="${2:?mat2 checkout}"
PYSITE="${3:?extra pure-python packages dir}"
EXIF="${4:?exiftool dir}"
PREFIX="${MINGW_PREFIX:-/mingw64}"
PYVER="$(python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"

rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/lib" "$OUT/etc" "$OUT/share" "$OUT/app"

echo "== Python $PYVER stdlib"
tar -C "$PREFIX/lib" -cf - \
  --exclude='__pycache__' --exclude="python$PYVER/test" \
  --exclude="python$PYVER/idlelib" --exclude="python$PYVER/tkinter" \
  --exclude="python$PYVER/turtledemo" --exclude="python$PYVER/site-packages" \
  "python$PYVER" | tar -C "$OUT/lib" -xf -
SP="$OUT/lib/python$PYVER/site-packages"
mkdir -p "$SP"
cp -r "$PREFIX/lib/python$PYVER/site-packages/gi"    "$SP/"
cp -r "$PREFIX/lib/python$PYVER/site-packages/cairo" "$SP/"
cp -r "$PYSITE"/* "$SP/"
find "$OUT" -name '__pycache__' -type d -prune -exec rm -rf {} +

echo "== GObject typelibs, pixbuf loaders, fonts config, poppler data"
cp -r "$PREFIX/lib/girepository-1.0" "$OUT/lib/"
cp -r "$PREFIX/lib/gdk-pixbuf-2.0" "$OUT/lib/"
rm -f "$OUT"/lib/gdk-pixbuf-2.0/*/loaders.cache
cp -r "$PREFIX/etc/fonts" "$OUT/etc/"
if [ -d "$PREFIX/share/poppler" ]; then cp -r "$PREFIX/share/poppler" "$OUT/share/"; fi

echo "== mat2 itself"
cp -r "$MAT2/libmat2" "$OUT/app/"
cp "$MAT2/mat2" "$OUT/app/mat2.py"

echo "== Windows fixes for mat2 (each fails the build loudly if upstream code changed)"
python - "$OUT/app/libmat2" <<'PY'
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(fname, old, new, count=1):
    f = root / fname
    s = f.read_text(encoding="utf-8")
    if s.count(old) != count:
        sys.exit(f"PATCH FAILED: expected {count} match(es) in {fname}, found {s.count(old)}: {old!r}")
    f.write_text(s.replace(old, new), encoding="utf-8")
    print(f"patched {fname}")

# 1. PDFs: hand-built file:// URIs are invalid for Windows paths (C:\...).
#    GLib builds a correct URI on every platform. (3 places in pdf.py)
patch("pdf.py",
      "self.uri = 'file://' + GLib.Uri.escape_string(os.path.abspath(self.filename), '/', True)",
      "self.uri = GLib.filename_to_uri(os.path.abspath(self.filename), None)")
patch("pdf.py",
      "Poppler.Document.new_from_file('file://' + GLib.Uri.escape_string(in_file, '/', True))",
      "Poppler.Document.new_from_file(GLib.filename_to_uri(os.path.abspath(in_file), None))")
patch("pdf.py",
      "document.save('file://' + GLib.Uri.escape_string(os.path.abspath(out_file), '/', True))",
      "document.save(GLib.filename_to_uri(os.path.abspath(out_file), None))")

# 2. Office files: Word on Windows stores thumbnail.emf (mat2 only knew .wmf).
patch("office.py",
      "r'^docProps/thumbnail.wmf$',",
      "r'^docProps/thumbnail\\.(?:wmf|emf)$',")

# 3. Archives (docx, odt, zip...): Windows can't delete read-only temp files.
HELPER = (
    "def _rmtree_force(path):\n"
    "    \"\"\" rmtree that also deletes read-only files (needed on Windows). \"\"\"\n"
    "    def _fix(func, p, _exc):\n"
    "        os.chmod(p, stat.S_IWRITE)\n"
    "        func(p)\n"
    "    try:\n"
    "        shutil.rmtree(path, onexc=_fix)\n"
    "    except TypeError:  # Python < 3.12\n"
    "        shutil.rmtree(path, onerror=_fix)\n"
    "\n\n"
)
CLS = "class ArchiveBasedAbstractParser(abstract.AbstractParser):"
patch("archive.py", CLS, HELPER + CLS)
patch("archive.py", "shutil.rmtree(temp_folder)", "_rmtree_force(temp_folder)", count=2)

# 4. PRIVACY FIX. mat2 decides how to clean files with checks such as
#    full_path.endswith('/docProps/core.xml'). Windows paths use backslashes,
#    so those checks never matched and Word's author, last-modified-by and
#    other properties were left in cleaned .docx/.pptx/.xlsx/.epub files.
#    Windows accepts forward slashes, so normalise the extracted paths.
patch("archive.py",
      "full_path = os.path.join(temp_folder, member_name)",
      "full_path = os.path.join(temp_folder, member_name).replace('\\\\', '/')",
      count=2)

# 5. PDFs and audio: mkstemp() leaves the file handle open, and Windows won't
#    delete an open file. Close the handle, and never fail a clean because a
#    temp file could not be deleted.
patch("pdf.py", "tmp_path = tempfile.mkstemp()[1]",
      "_fd, tmp_path = tempfile.mkstemp(); os.close(_fd)")
patch("pdf.py", "_, tmp_path = tempfile.mkstemp()",
      "_fd, tmp_path = tempfile.mkstemp(); os.close(_fd)")
patch("audio.py", "_, fname = tempfile.mkstemp()",
      "_fd, fname = tempfile.mkstemp(); os.close(_fd)")
PDF_HELPER = (
    "def _remove_temp(path):\n"
    "    \"\"\" Delete a temp file; Windows may briefly keep it locked. \"\"\"\n"
    "    import gc\n"
    "    import time\n"
    "    for _ in range(10):\n"
    "        try:\n"
    "            os.remove(path)\n"
    "            return\n"
    "        except PermissionError:\n"
    "            gc.collect()\n"
    "            time.sleep(0.2)\n"
    "    logging.warning(\"Could not delete temporary file %s\", path)\n"
    "\n\n"
)
PCLS = "class PDFParser(abstract.AbstractParser):"
patch("pdf.py", PCLS, PDF_HELPER + PCLS)
patch("pdf.py", "os.remove(tmp_path)", "_remove_temp(tmp_path)", count=2)
PY
cp "$MAT2/LICENSE" "$OUT/LICENSE-mat2.txt"

echo "== ExifTool"
cp -r "$EXIF" "$OUT/exiftool"

echo "== DLL closure (everything the above needs from $PREFIX/bin)"
cp "$PREFIX/bin/python.exe" "$OUT/bin/"
cp "$PREFIX"/bin/libpython*.dll "$OUT/bin/"
cp "$PREFIX/bin/gdk-pixbuf-query-loaders.exe" "$OUT/bin/"

declare -A SEEN=()
queue=()
while IFS= read -r f; do queue+=("$f"); done < <(
  { find "$OUT/bin" "$OUT/lib" -type f \( -name '*.dll' -o -name '*.pyd' -o -name '*.exe' \)
    ls "$PREFIX"/bin/libpoppler-glib*.dll "$PREFIX"/bin/librsvg-2*.dll \
       "$PREFIX"/bin/libgdk_pixbuf-2.0-0.dll "$PREFIX"/bin/libgirepository*.dll \
       "$PREFIX"/bin/libgio-2.0-0.dll "$PREFIX"/bin/libgmodule-2.0-0.dll \
       "$PREFIX"/bin/libcairo-gobject-2.dll 2>/dev/null || true; } | sort -u)

while ((${#queue[@]})); do
  f="${queue[0]}"; queue=("${queue[@]:1}")
  base="$(basename "$f")"
  if [[ "$f" == "$PREFIX/bin/"* && -z "${SEEN[$base]:-}" ]]; then
    SEEN[$base]=1; cp -n "$f" "$OUT/bin/"
  fi
  while read -r dep; do
    [[ -z "$dep" ]] && continue
    b="$(basename "$dep")"
    [[ -n "${SEEN[$b]:-}" ]] && continue
    SEEN[$b]=1; cp -n "$dep" "$OUT/bin/"; queue+=("$dep")
  done < <(ldd "$f" 2>/dev/null | awk '{print $3}' | grep -i "^$PREFIX/bin/" || true)
done

echo "== licenses of bundled MSYS2 packages"
mkdir -p "$OUT/THIRD-PARTY"
if [ -d "$PREFIX/share/licenses" ]; then cp -r "$PREFIX/share/licenses" "$OUT/THIRD-PARTY/licenses"; fi

du -sh "$OUT"
