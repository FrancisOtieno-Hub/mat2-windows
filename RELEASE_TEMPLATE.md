## mat2 for Windows (unofficial build)

A portable Windows build of [mat2](https://github.com/jvoisin/mat2), the metadata cleaner: it removes hidden data (location, author names, camera details, edit history) from your files. Unzip it and run it, no installation needed.

**This is an experimental, unofficial build. It is not made or endorsed by the mat2 project.**

### Downloads

| File | What it is | SHA-256 |
|---|---|---|
| `__ZIP__` | the program (Windows) | `__SHA256__` |
| `__SOURCES_ZIP__` | corresponding source code of everything inside (GPL/LGPL) | `__SOURCES_SHA256__` |

### Tested on Windows

Cleaning and re-checking worked for: **JPG, DOCX, PDF, XLSX, PPTX.**

Not tested yet: EPUB, ODT/ODS/ODP, ZIP, MP3 and other audio, PNG/GIF/TIFF/WebP, HTML/SVG, text files.
Not supported: video (FFmpeg is not included).

Always check a cleaned file with `mat2.cmd --show FILE` before you share it.

### Built from

- mat2 commit `__MAT2_COMMIT__` plus small Windows fixes, published in `scripts/bundle.sh` (Windows file paths, temporary files, Office theme parts, PowerPoint slide-master IDs, Excel namespaces and a leftover local folder path)
- ExifTool __EXIFTOOL__

### Verify your download (PowerShell)

```
Get-FileHash .\__ZIP__ -Algorithm SHA256
```
The result must match the SHA-256 in the table above.

### Windows warnings

The files are not code-signed, so Windows SmartScreen may show a warning. Click **More info**, then **Run anyway**, after checking the SHA-256 above.

### License and source

mat2 is licensed under LGPL-3.0-or-later. The download also contains other open-source components (Python, GLib, GdkPixbuf, librsvg, cairo, Poppler, mutagen, ExifTool and more) under their own licenses. License texts are in the `THIRD-PARTY` folder. The complete corresponding source is in the sources file above.
