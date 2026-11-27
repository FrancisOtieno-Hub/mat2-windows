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

# 6. os.rename() refuses to overwrite an existing file on Windows (it does on
#    Linux). mat2 uses it to put cleaned images back inside docx/xlsx/pptx
#    files, so those crashed. os.replace() overwrites on every platform.
patch("archive.py", "os.rename(member_parser.output_filename, full_path)",
      "os.replace(member_parser.output_filename, full_path)")
patch("../mat2.py", "os.rename(p.output_filename, filename)",
      "os.replace(p.output_filename, filename)")

# 7. mat2 deletes the theme parts (theme1.xml). A PowerPoint slide master
#    REQUIRES a theme and Excel styles refer to theme colours, so cleaned
#    .pptx/.xlsx files made Office show "found a problem with content".
#    Keep the theme (and its relationships; theme images are still cleaned).
patch("office.py", "            r'^(?:word|ppt|xl)/theme',\n", "")
patch("office.py",
      "            r'^ppt/handoutMasters/_rels/handoutMaster[0-9]+\\.xml\\.rels',\n",
      "            r'^ppt/handoutMasters/_rels/handoutMaster[0-9]+\\.xml\\.rels',\n"
      "            r'^(?:word|ppt|xl)/theme/theme[0-9]+\\.xml$',\n"
      "            r'^(?:word|ppt|xl)/theme/_rels/theme[0-9]+\\.xml\\.rels$',\n")

# 8. PowerPoint: mat2 sets every slide-master id to random(0 .. 2**32), but
#    PowerPoint only accepts ids from 2**31 to 2**32-1. Half of the random
#    values are invalid and PowerPoint answers "found a problem with content".
patch("office.py", "item.set('id', '%s' % random.randint(0, 2**32))",
      "item.set('id', '%s' % random.randint(2**31, 2**32 - 1))")
patch("office.py", "item.set('val', '%s' % random.randint(0, 2**32))",
      "item.set('val', '%s' % random.randint(0, 2**32 - 1))")
#    The replacement tableStyles.xml pointed at a random, undefined style id.
#    Use PowerPoint's own built-in default table style id instead.
patch("office.py", "uid = str(uuid.uuid4()).encode('utf-8')",
      "uid = b'5C22544A-7EE6-4342-B048-85BDC9FD1C3A'")

# 9. Excel: workbook.xml has <mc:Choice Requires="x15">. ElementTree drops the
#    unused xmlns:x15 declaration, leaving Requires="x15" pointing at nothing,
#    and Excel says "found a problem with some content". The same block also
#    holds x15ac:absPath, the full local folder path of the file (a privacy
#    leak that mat2 leaves in place). Remove that block, and re-declare any
#    prefix that is still named in a Requires="..." attribute.
HELPERS = r'''def _read_ns_decls(path):
    """ prefix -> uri declarations found in the raw text of an XML file """
    try:
        with open(path, 'rb') as f:
            raw = f.read()
    except OSError:  # pragma: no cover
        return {}
    return {k.decode(): v.decode()
            for k, v in re.findall(rb'xmlns:([A-Za-z_][\w.-]*)="([^"]*)"', raw)}


def _fix_office_xml(raw, orig_decls):
    """ Fixes for XML that ElementTree has just written for Microsoft Office """
    raw = re.sub(rb'<mc:AlternateContent\b[^>]*>(?:(?!</mc:AlternateContent>).)*?absPath'
                 rb'(?:(?!</mc:AlternateContent>).)*</mc:AlternateContent>',
                 b'', raw, flags=re.DOTALL)
    need = set()
    for m in re.finditer(rb'\bRequires="([^"]*)"', raw):
        need.update(m.group(1).decode().split())
    if need:
        present = {k.decode() for k in re.findall(rb'xmlns:([A-Za-z_][\w.-]*)=', raw)}
        missing = [p for p in sorted(need) if p not in present and p in orig_decls]
        if missing:
            start = raw.find(b'?>') + 2 if raw.lstrip().startswith(b'<?xml') else 0
            m = re.compile(rb'<([A-Za-z_][^\s/>]*)').search(raw, start)
            if m:
                extra = b''.join(b' xmlns:%s="%s"' % (p.encode(), orig_decls[p].encode())
                                 for p in missing)
                raw = raw[:m.end()] + extra + raw[m.end():]
    return raw


'''
PARSE = "def _parse_xml(full_path: str) -> tuple[ET.ElementTree, dict[str, str]]:"
patch("office.py", PARSE, HELPERS + PARSE)
START = "        if self.__randomize_creationId(full_path) is False:\n            return False\n"
patch("office.py", START, "        _orig_ns = _read_ns_decls(full_path)\n" + START)
IGN = "            out = re.sub(b'mc:Ignorable=\"[^\"]*\"', b'', text, count=1)\n"
patch("office.py", IGN, IGN + "            out = _fix_office_xml(out, _orig_ns)\n")
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
