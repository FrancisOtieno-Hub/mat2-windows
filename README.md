# mat2 for Windows (unofficial build)

An unofficial, portable Windows build of [mat2](https://github.com/jvoisin/mat2),
the metadata anonymisation toolkit by Julien (jvoisin) Voisin. mat2 removes
hidden metadata (author names, GPS location, camera details, edit history) from
images, PDFs, Office documents, audio, archives and more.

This build is **not made or endorsed by the mat2 project**. All credit for the
tool goes to its author and contributors. Report problems with *this Windows
packaging* in this repository, and problems with mat2 itself upstream.

## Using it

1. Unzip the folder anywhere (no installation, no admin rights).
2. **Drag files onto `Clean-files-with-mat2.cmd`.** A cleaned copy is saved next
   to each original as `NAME.cleaned.EXT`. Originals are never changed.
3. Command line: `mat2.cmd --help`, `mat2.cmd --show photo.jpg` (list the
   metadata without removing it).

Notes from upstream: mat2 may slightly alter files to remove as much metadata as
possible (for example, text in a cleaned PDF may no longer be selectable). Use
`--lightweight` (`-L`) to remove only some metadata and leave file content intact.
Video support needs FFmpeg, which is not included in this build.

## Verify your download

Compare the SHA-256 of the zip with the `.sha256` file published next to it.
The zip is built by the public GitHub Actions workflow in this repository from
upstream mat2 source, so you can inspect exactly how it was made.

Windows may show a SmartScreen warning because the files are not code-signed.

## License and source

- mat2 is licensed under the **GNU LGPL v3 or later** (see `LICENSE-mat2.txt`).
  Upstream source: https://github.com/jvoisin/mat2
- The bundle also contains other open-source components (Python, GLib, GTK
  libraries, Poppler, librsvg, ExifTool and more) under their own licenses.
  See the `THIRD-PARTY` folder for license texts, exact package versions and
  where to get the corresponding source. The build scripts in this repository
  are the exact recipe used.

## Building it yourself

Push this repository to GitHub and run the **Build mat2 for Windows** workflow
(Actions tab), or run `scripts/bundle.sh` in an MSYS2 MINGW64 shell.
