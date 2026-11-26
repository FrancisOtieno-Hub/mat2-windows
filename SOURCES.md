# Corresponding source and licenses

This Windows bundle combines several open-source programs. This file explains
where the source code for each part can be obtained.

| Component | License (summary) | Source |
|---|---|---|
| mat2 | LGPL-3.0-or-later | https://github.com/jvoisin/mat2 (exact commit in `BUILD-INFO.txt`) |
| Python, GLib/GObject, GdkPixbuf, librsvg, cairo, fontconfig, PyGObject, PyCairo | Mostly LGPL / MIT / PSF | MSYS2 package recipes: https://github.com/msys2/MINGW-packages (exact versions in `packages.txt`) |
| Poppler (and poppler-data) | GPL-2.0 / GPL-3.0 | MSYS2 package recipe above; upstream https://poppler.freedesktop.org/ |
| mutagen | GPL-2.0-or-later | https://github.com/quodlibet/mutagen |
| ExifTool | Perl Artistic License or GPL | https://exiftool.org/ |

Full license texts for the MSYS2 packages are in `THIRD-PARTY/licenses`.

The build scripts that produced this bundle (workflow, `scripts/bundle.sh` and
the launchers) are published in the same repository as this release.

If you received this bundle and want the source of any component listed above
and cannot find it using these links, open an issue in this repository and it
will be provided.

---
**Maintainer checklist before publishing (delete before release):**
- This bundle includes GPL components (Poppler, mutagen). Confirm with a
  qualified person that the way you offer source (links above, or hosting
  copies of the source archives next to the download) satisfies those licenses.
  Hosting the source archives on your own site next to the zip is the safest
  option.
- Check each component's license text in `THIRD-PARTY/licenses` matches this table.
