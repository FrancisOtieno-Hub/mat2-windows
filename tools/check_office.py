"""Structure-only checker for .docx/.xlsx/.pptx files.

Prints problems that make Office say "we found a problem with some content":
missing parts, dangling relationships, r:id references with no relationship,
content-type entries for missing parts, malformed XML, duplicate shape ids.

It only prints part NAMES and relationship IDS - never document text.

usage: python check_office.py cleaned.xlsx [original.xlsx]
"""
import posixpath
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from collections import Counter

REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
PKG_REL = "http://schemas.openxmlformats.org/package/2006/relationships"
CT_NS = "http://schemas.openxmlformats.org/package/2006/content-types"


def rels_owner(rels_name):
    """'xl/worksheets/_rels/sheet1.xml.rels' -> ('xl/worksheets', 'xl/worksheets/sheet1.xml')"""
    folder, base = posixpath.split(rels_name)          # .../_rels, sheet1.xml.rels
    root = posixpath.dirname(folder)                    # xl/worksheets
    owner = base[:-len(".rels")]                        # sheet1.xml
    return root, (posixpath.join(root, owner) if owner else "")


def resolve(root, target):
    if target.startswith("/"):
        return target.lstrip("/")
    return posixpath.normpath(posixpath.join(root, target))


def check(path):
    problems = []
    z = zipfile.ZipFile(path)
    names = z.namelist()
    nameset = set(names)

    dupes = [n for n, c in Counter(names).items() if c > 1]
    for n in dupes:
        problems.append(f"duplicate zip entry: {n}")

    if "[Content_Types].xml" not in nameset:
        problems.append("missing [Content_Types].xml")
        return names, problems

    # --- well-formedness
    parsed = {}
    for n in names:
        if n.endswith((".xml", ".rels")):
            try:
                parsed[n] = ET.fromstring(z.read(n))
            except ET.ParseError as e:
                problems.append(f"malformed XML in {n}: {e}")

    # --- content types
    ct = parsed.get("[Content_Types].xml")
    defaults, overrides = set(), set()
    if ct is not None:
        for c in ct:
            tag = c.tag.split("}")[-1]
            if tag == "Default":
                defaults.add(c.attrib.get("Extension", "").lower())
            elif tag == "Override":
                part = c.attrib.get("PartName", "").lstrip("/")
                overrides.add(part)
                if part not in nameset:
                    problems.append(f"[Content_Types] Override for missing part: {part}")
    for n in names:
        if n == "[Content_Types].xml" or n.endswith("/"):
            continue
        ext = n.rsplit(".", 1)[-1].lower() if "." in n else ""
        if n not in overrides and ext not in defaults:
            problems.append(f"part has no content type: {n}")

    # --- relationships
    rel_ids = {}   # owner part -> set of rIds
    for n, root_el in parsed.items():
        if not n.endswith(".rels"):
            continue
        base, owner = rels_owner(n)
        ids = set()
        for r in root_el:
            rid = r.attrib.get("Id")
            ids.add(rid)
            if r.attrib.get("TargetMode") == "External":
                continue
            target = r.attrib.get("Target", "")
            if target.startswith("#") or not target:
                continue
            dest = resolve(base, target)
            if dest not in nameset and not any(x.startswith(dest + "/") for x in nameset):
                problems.append(f"{n}: {rid} points to missing part {dest}")
        if owner:
            rel_ids[owner] = ids
        else:
            rel_ids[""] = ids

    # --- r:id style references inside parts, and duplicate shape ids
    for n, root_el in parsed.items():
        if n.endswith(".rels") or n == "[Content_Types].xml":
            continue
        used = set()
        for el in root_el.iter():
            for k, v in el.attrib.items():
                if k.startswith("{%s}" % REL_NS) and v:
                    used.add(v)
        if used:
            have = rel_ids.get(n, set())
            for u in sorted(used - have):
                problems.append(f"{n}: references relationship {u} which does not exist")
        ids = [el.attrib.get("id") for el in root_el.iter()
               if el.tag.endswith("}cNvPr") and el.attrib.get("id")]
        for i, c in Counter(ids).items():
            if c > 1:
                problems.append(f"{n}: shape id {i} used {c} times")

    # --- theme requirements
    for n in names:
        if re.match(r"^ppt/(slideMasters/slideMaster|notesMasters/notesMaster|handoutMasters/handoutMaster)\d+\.xml$", n):
            relname = posixpath.join(posixpath.dirname(n), "_rels", posixpath.basename(n) + ".rels")
            rel_root = parsed.get(relname)
            has_theme = rel_root is not None and any(
                r.attrib.get("Type", "").endswith("/theme") for r in rel_root)
            if not has_theme:
                problems.append(f"{n}: has no theme relationship (PowerPoint requires one)")
    has_theme_part = any(re.match(r"^xl/theme/", n) for n in names)
    if "xl/styles.xml" in parsed and not has_theme_part:
        uses = sum(1 for el in parsed["xl/styles.xml"].iter() if "theme" in el.attrib)
        if uses:
            problems.append(f"xl/styles.xml uses theme colours {uses} time(s) but the workbook has no theme part")

    return names, problems


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    names, problems = check(sys.argv[1])
    print(f"== {sys.argv[1]}: {len(names)} parts")
    if problems:
        print(f"{len(problems)} problem(s):")
        for p in problems:
            print("  -", p)
    else:
        print("No structural problems found.")
    if len(sys.argv) > 2:
        orig_names, orig_problems = check(sys.argv[2])
        gone = sorted(set(orig_names) - set(names))
        print(f"\n== parts present in original but removed in cleaned ({len(gone)}):")
        for g in gone:
            print("  -", g)
        print(f"\n== original file had {len(orig_problems)} structural problem(s) itself")
        for p in orig_problems[:20]:
            print("  -", p)


if __name__ == "__main__":
    main()
