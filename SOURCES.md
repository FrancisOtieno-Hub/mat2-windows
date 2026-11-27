# Corresponding source and licenses

This Windows bundle combines several open-source programs, each under its own
license. This file explains where the complete corresponding source code is.

## Where to get the source

Every release is published together with a file named
`mat2-windows-<version>-sources.zip`. It is on the same release page and the
same website page as the program download, and stays available for as long as the
program is offered. It contains:

- `msys2/`: the source package of **every MSYS2 package whose files are in the
  download** (Python, GLib, GdkPixbuf, librsvg, cairo, Poppler, fontconfig, the
  GCC runtime libraries and more). Each one holds the packaging recipe, the
  upstream source and any patches. The exact list is in `PACKAGES-SHIPPED.txt`.
- `other/`: mat2 (the exact commit that was built), mutagen, ExifTool, and the
  build recipe (`mat2-windows-recipe.tar.gz`: the workflow and scripts that
  assemble the download, including the small Windows fixes applied to mat2).

The release build fails if the source of any shipped package cannot be
collected, so a release is never published without its source.

## Components

| Component | License (summary) | Upstream |
|---|---|---|
| mat2 | LGPL-3.0-or-later | https://github.com/jvoisin/mat2 |
| Python, GLib/GObject, GdkPixbuf, librsvg, cairo, fontconfig, PyGObject, PyCairo | mostly LGPL / MIT / PSF | via MSYS2 packages |
| Poppler (and poppler-data) | GPL-2.0 / GPL-3.0 | https://poppler.freedesktop.org/ |
| GCC runtime libraries | GPL-3.0 with the GCC Runtime Library Exception | https://gcc.gnu.org/ |
| mutagen | GPL-2.0-or-later | https://github.com/quodlibet/mutagen |
| ExifTool | Perl Artistic License or GPL | https://exiftool.org/ |

Full license texts for the MSYS2 packages are in `THIRD-PARTY/licenses`. The
exact package versions are in `THIRD-PARTY/packages.txt`, and the mat2 commit
and ExifTool version are in `THIRD-PARTY/BUILD-INFO.txt`.

## Questions

If you cannot find the source of any component, open an issue in the repository
this download came from and it will be provided.
