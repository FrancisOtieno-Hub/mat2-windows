#!/usr/bin/env python3
"""A small window for mat2 (unofficial Windows build).

Drop files on the window (or use "Add files..."), look at the metadata they
contain, press "Clean", and compare with what is left in the cleaned copy.

Safety rules built into this program:
  * The original file is only ever READ. mat2 works on a temporary copy.
  * The cleaned copy is saved under a NEW name (NAME.cleaned.EXT, or
    NAME.cleaned (2).EXT ...). The name is reserved with O_EXCL, so an
    existing file can never be replaced.
  * Nothing is sent over the network and no log file is written.

mat2 removes the metadata it knows about. It cannot promise anonymity.
"""
import os
import queue
import shutil
import stat
import subprocess
import sys
import tempfile
import threading

APP = os.path.dirname(os.path.abspath(__file__))
MAT2 = os.path.join(APP, "mat2.py")
CHECK_OFFICE = os.path.join(APP, "check_office.py")
OFFICE_EXT = (".docx", ".xlsx", ".pptx")
RUN_TIMEOUT = 600  # seconds for one mat2 run


# --------------------------------------------------------------------------
# core (no window code in here)
# --------------------------------------------------------------------------
def _python_exe():
    """python.exe, even when this program was started with pythonw.exe
    (pythonw has no stdout, so it cannot be used to capture mat2's output)."""
    folder, name = os.path.split(sys.executable)
    if name.lower() == "pythonw.exe":
        candidate = os.path.join(folder, "python.exe")
        if os.path.exists(candidate):
            return candidate
    return sys.executable


def _run(args, timeout=RUN_TIMEOUT):
    env = dict(os.environ)
    env["PYTHONUTF8"] = "1"
    kwargs = {}
    if os.name == "nt":
        kwargs["creationflags"] = 0x08000000  # CREATE_NO_WINDOW: no black box
    try:
        done = subprocess.run([_python_exe()] + list(args), capture_output=True,
                              stdin=subprocess.DEVNULL, timeout=timeout,
                              env=env, **kwargs)
    except subprocess.TimeoutExpired:
        return 1, "Timed out after %d seconds." % timeout
    except OSError as exc:
        return 1, "Could not start mat2: %s" % exc
    return done.returncode, (done.stdout + done.stderr).decode("utf-8", "replace")


def _tidy(text, path):
    """show the file name instead of the full (possibly temporary) path"""
    return text.replace(path, os.path.basename(path)).strip()


def show_metadata(path):
    """metadata mat2 finds in a file (read-only), as text"""
    _, out = _run([MAT2, "--show", path])
    return _tidy(out, path)


def _is_neutral(line):
    """lines mat2 leaves in a cleaned PDF that carry no information about you:
    empty dates (-1) and the PDF version"""
    return line in ("creation-date: -1", "mod-date: -1") or line.startswith("format: PDF-")


def count_items(text, ignore_neutral=False):
    """number of metadata lines in `mat2 --show` output"""
    count = 0
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("[") or s.startswith("No metadata"):
            continue
        if ignore_neutral and _is_neutral(s):
            continue
        if ": " in s or s.endswith(":"):
            count += 1
    return count


def is_unsupported(text):
    return "not supported" in text and "[-]" in text


def _reserve_name(folder, stem, ext):
    """create an empty, brand-new file NAME.cleaned.EXT (or ' (2)', ...).
    O_EXCL means this fails instead of ever touching an existing file."""
    n = 1
    while True:
        tag = ".cleaned" if n == 1 else ".cleaned (%d)" % n
        path = os.path.join(folder, stem + tag + ext)
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o666)
        except FileExistsError:
            n += 1
            continue
        os.close(fd)
        return path


def _rmtree_force(path):
    def fix(func, p, _exc):
        os.chmod(p, stat.S_IWRITE)
        func(p)
    try:
        shutil.rmtree(path, onexc=fix)
    except TypeError:  # Python < 3.12
        shutil.rmtree(path, onerror=fix)


def clean_file(src, dest_dir=None, lightweight=False):
    """Clean a COPY of src and save the result as a new file.
    Returns a dict: ok, output, message, after, check."""
    res = {"ok": False, "output": None, "message": "", "after": "", "check": ""}
    src = os.path.abspath(src)
    if not os.path.isfile(src):
        res["message"] = "File not found."
        return res
    folder = os.path.abspath(dest_dir) if dest_dir else os.path.dirname(src)
    if not os.path.isdir(folder):
        res["message"] = "Output folder not found."
        return res
    tmp = tempfile.mkdtemp(prefix="mat2-window-")
    reserved = None
    try:
        work = os.path.join(tmp, os.path.basename(src))
        shutil.copyfile(src, work)  # the original is only opened for reading
        args = [MAT2] + (["-L"] if lightweight else []) + [work]
        rc, out = _run(args)
        stem, ext = os.path.splitext(work)
        cleaned = stem + ".cleaned" + ext
        if rc != 0 or not os.path.exists(cleaned):
            lines = [x for x in _tidy(out, work).splitlines() if x.strip()]
            res["message"] = (lines[-1] if lines else "mat2 could not clean this file.")[:300]
            return res
        res["after"] = show_metadata(cleaned)
        if ext.lower() in OFFICE_EXT:
            _, chk = _run([CHECK_OFFICE, cleaned])
            res["check"] = _tidy(chk, cleaned)
        base_stem = os.path.splitext(os.path.basename(src))[0]
        reserved = _reserve_name(folder, base_stem, ext)
        if os.path.normcase(os.path.abspath(reserved)) == os.path.normcase(src):
            raise RuntimeError("refusing to write over the original")  # cannot happen
        shutil.copyfile(cleaned, reserved)
        res["ok"] = True
        res["output"] = reserved
        reserved = None
    except PermissionError:
        res["message"] = "Cannot write to the output folder (permission denied)."
    except OSError as exc:
        res["message"] = "Could not save the cleaned copy: %s" % exc
    finally:
        if reserved and os.path.exists(reserved):
            try:
                os.remove(reserved)  # our own empty placeholder, never the original
            except OSError:
                pass
        _rmtree_force(tmp)
    return res


# --------------------------------------------------------------------------
# file drop on Windows (Tk has no built-in support for dropping files)
# --------------------------------------------------------------------------
def enable_file_drop(root, sink):
    """Let Explorer drop files on the window. Returns True if hooked.
    Windows only; any failure just returns False (buttons still work).

    The Windows message handler runs while Tk's main loop has Python's lock
    released, so it must NOT call any Tk function (that aborts Python).
    It only puts the dropped paths into `sink`, a queue.Queue; the window's
    timer reads that queue."""
    if os.name != "nt":
        return False

    def dbg(message):  # only prints when started with MAT2_GUI_DEBUG=1 (console mode)
        if os.environ.get("MAT2_GUI_DEBUG"):
            print("[drop] " + message, flush=True)

    try:
        import ctypes
        import traceback
        from ctypes import wintypes
        root.update_idletasks()
        user32, shell32 = ctypes.windll.user32, ctypes.windll.shell32
        LRESULT = ctypes.c_ssize_t
        WNDPROC = ctypes.WINFUNCTYPE(LRESULT, wintypes.HWND, wintypes.UINT,
                                     wintypes.WPARAM, wintypes.LPARAM)
        user32.SetWindowLongPtrW.restype = ctypes.c_void_p
        user32.SetWindowLongPtrW.argtypes = [wintypes.HWND, ctypes.c_int, ctypes.c_void_p]
        user32.CallWindowProcW.restype = LRESULT
        user32.CallWindowProcW.argtypes = [ctypes.c_void_p, wintypes.HWND, wintypes.UINT,
                                           wintypes.WPARAM, wintypes.LPARAM]
        shell32.DragQueryFileW.restype = wintypes.UINT
        shell32.DragQueryFileW.argtypes = [ctypes.c_void_p, wintypes.UINT, wintypes.LPWSTR, wintypes.UINT]
        shell32.DragFinish.argtypes = [ctypes.c_void_p]
        shell32.DragAcceptFiles.argtypes = [wintypes.HWND, wintypes.BOOL]
        keep = []

        def hook(hwnd):
            previous = [None]

            def proc(h, msg, wparam, lparam):
                if msg == 0x0233:  # WM_DROPFILES
                    dbg("WM_DROPFILES arrived on window %s" % hex(h or 0))
                    paths = []
                    try:
                        n = shell32.DragQueryFileW(wparam, 0xFFFFFFFF, None, 0)
                        dbg("%d item(s) in the drop" % n)
                        for i in range(n):
                            size = shell32.DragQueryFileW(wparam, i, None, 0)
                            buf = ctypes.create_unicode_buffer(size + 1)
                            shell32.DragQueryFileW(wparam, i, buf, size + 1)
                            paths.append(buf.value)
                    except Exception:
                        dbg(traceback.format_exc())
                    finally:
                        shell32.DragFinish(wparam)
                    dbg("drop read ok, queued %d path(s)" % len(paths))
                    sink.put(paths)
                    return 0
                return user32.CallWindowProcW(previous[0], h, msg, wparam, lparam)

            callback_ref = WNDPROC(proc)
            old = user32.SetWindowLongPtrW(hwnd, -4, ctypes.cast(callback_ref, ctypes.c_void_p))
            if not old:
                return False
            previous[0] = old
            keep.append((callback_ref, previous))
            shell32.DragAcceptFiles(hwnd, True)
            dbg("hooked window %s" % hex(hwnd))
            return True

        hooked = False
        for text in (root.wm_frame(), hex(root.winfo_id())):
            try:
                hooked = hook(int(text, 16)) or hooked
            except Exception:
                dbg("hook failed: " + traceback.format_exc())
        root._drop_keepalive = keep  # stop Python from freeing the callbacks
        return hooked
    except Exception:
        return False


# --------------------------------------------------------------------------
# the window
# --------------------------------------------------------------------------
import tkinter as tk  # noqa: E402
from tkinter import filedialog, messagebox, ttk  # noqa: E402


class App:
    def __init__(self, root):
        self.root = root
        root.title("mat2 window (unofficial Windows build)")
        root.geometry("960x700")
        root.minsize(780, 540)
        self.items = {}      # row id -> dict(path, state, before, after, output)
        self.keys = set()
        self.jobs = queue.Queue()
        self.results = queue.Queue()
        self.pending = 0
        self.drop_queue = queue.Queue()  # filled by the Windows drop handler
        self.light = tk.BooleanVar(value=False)
        self.dest_mode = tk.StringVar(value="next")
        self.dest_dir = tk.StringVar(value="")
        self._build()
        threading.Thread(target=self._worker, daemon=True).start()
        root.after(100, self._poll)
        self.drop_ok = enable_file_drop(root, self.drop_queue)
        if not self.drop_ok:
            self._say("Drag and drop is not available here. Use \u201cAdd files\u2026\u201d.")

    # ---- layout
    def _build(self):
        pad = {"padx": 10, "pady": 4}
        zone = ttk.Label(self.root, anchor="center", relief="groove", padding=16,
                         text="Drag files here, or click to choose files\n"
                              "Your originals are never changed. A cleaned copy is saved next to them.")
        zone.pack(fill="x", **pad)
        zone.bind("<Button-1>", lambda e: self.pick_files())

        bar = ttk.Frame(self.root)
        bar.pack(fill="x", **pad)
        ttk.Button(bar, text="Add files\u2026", command=self.pick_files).pack(side="left")
        ttk.Button(bar, text="Remove selected", command=self.remove_selected).pack(side="left", padx=6)
        ttk.Button(bar, text="Clear list", command=self.clear).pack(side="left")
        self.clean_btn = ttk.Button(bar, text="Clean files", command=self.clean_all)
        self.clean_btn.pack(side="right")

        opts = ttk.LabelFrame(self.root, text="Options")
        opts.pack(fill="x", **pad)
        ttk.Checkbutton(opts, variable=self.light,
                        text="Lightweight cleaning: removes only some metadata but keeps the file's "
                             "content intact (PDF text stays selectable)").pack(anchor="w", padx=8, pady=2)
        row = ttk.Frame(opts)
        row.pack(fill="x", padx=8, pady=2)
        ttk.Radiobutton(row, text="Save next to each original", value="next",
                        variable=self.dest_mode).pack(side="left")
        ttk.Radiobutton(row, text="Save in this folder:", value="folder",
                        variable=self.dest_mode).pack(side="left", padx=(16, 4))
        ttk.Entry(row, textvariable=self.dest_dir, width=40).pack(side="left")
        ttk.Button(row, text="Browse\u2026", command=self.pick_folder).pack(side="left", padx=4)

        self.tree = ttk.Treeview(self.root, columns=("status", "before", "after"),
                                 height=6, selectmode="browse")
        self.tree.heading("#0", text="File")
        self.tree.heading("status", text="Status")
        self.tree.heading("before", text="Before")
        self.tree.heading("after", text="After")
        self.tree.column("#0", width=330)
        self.tree.column("status", width=240)
        self.tree.column("before", width=110, anchor="e")
        self.tree.column("after", width=110, anchor="e")
        self.tree.pack(fill="x", **pad)
        self.tree.bind("<<TreeviewSelect>>", lambda e: self._show_selected())

        panes = ttk.PanedWindow(self.root, orient="horizontal")
        panes.pack(fill="both", expand=True, **pad)
        self.before_txt = self._text_pane(panes, "Before: metadata in the original")
        self.after_txt = self._text_pane(panes, "After: what is left in the cleaned copy")

        self.status = ttk.Label(self.root, anchor="w", wraplength=900, justify="left",
                                text="")
        self.status.pack(fill="x", padx=10, pady=(0, 2))
        ttk.Label(self.root, anchor="w", wraplength=900, justify="left", foreground="#555555",
                  text="mat2 removes the metadata it knows about; it cannot guarantee anonymity. "
                       "Read the \u201cAfter\u201d text before sharing a file."
                  ).pack(fill="x", padx=10, pady=(0, 8))

    def _text_pane(self, parent, title):
        frame = ttk.LabelFrame(parent, text=title)
        text = tk.Text(frame, wrap="none", height=12, width=40, state="disabled",
                       font="TkFixedFont")
        ys = ttk.Scrollbar(frame, orient="vertical", command=text.yview)
        xs = ttk.Scrollbar(frame, orient="horizontal", command=text.xview)
        text.configure(yscrollcommand=ys.set, xscrollcommand=xs.set)
        ys.pack(side="right", fill="y")
        xs.pack(side="bottom", fill="x")
        text.pack(fill="both", expand=True)
        parent.add(frame, weight=1)
        return text

    # ---- small helpers
    def _say(self, message):
        self.status.config(text=message)

    @staticmethod
    def _set_text(widget, content):
        widget.config(state="normal")
        widget.delete("1.0", "end")
        widget.insert("1.0", content)
        widget.config(state="disabled")

    def _set_row(self, iid, status=None, before=None, after=None):
        if status is not None:
            self.tree.set(iid, "status", status)
        if before is not None:
            self.tree.set(iid, "before", before)
        if after is not None:
            self.tree.set(iid, "after", after)

    def _show_selected(self):
        sel = self.tree.selection()
        if not sel:
            self._set_text(self.before_txt, "")
            self._set_text(self.after_txt, "")
            return
        it = self.items[sel[0]]
        self._set_text(self.before_txt, it["before"])
        self._set_text(self.after_txt, it["after"])

    # ---- adding / removing files
    def pick_files(self):
        paths = filedialog.askopenfilenames(title="Choose files to clean")
        if paths:
            self.add_files(list(paths))

    def pick_folder(self):
        folder = filedialog.askdirectory(title="Save cleaned copies in")
        if folder:
            self.dest_dir.set(folder)
            self.dest_mode.set("folder")

    def add_files(self, paths):
        skipped = added = 0
        first = None
        for p in paths:
            p = os.path.abspath(p)
            if not os.path.isfile(p):
                skipped += 1  # folders are not processed
                continue
            key = os.path.normcase(p)
            if key in self.keys:
                continue
            self.keys.add(key)
            iid = self.tree.insert("", "end", text=os.path.basename(p),
                                   values=("Reading\u2026", "", ""))
            self.items[iid] = {"path": p, "state": "reading", "before": "",
                               "after": "Not cleaned yet.", "output": None}
            first = first or iid
            added += 1
            self._enqueue(("inspect", iid, p))
        if first and not self.tree.selection():
            self.tree.selection_set(first)
        msg = "%d file(s) added." % added if added else ""
        if skipped:
            msg += " %d folder(s) or missing file(s) skipped (drop files, not folders)." % skipped
        if msg:
            self._say(msg.strip())

    def remove_selected(self):
        for iid in self.tree.selection():
            self.keys.discard(os.path.normcase(self.items[iid]["path"]))
            del self.items[iid]
            self.tree.delete(iid)
        self._show_selected()

    def clear(self):
        for iid in list(self.items):
            self.tree.delete(iid)
        self.items.clear()
        self.keys.clear()
        self._show_selected()

    # ---- background work
    def _enqueue(self, job):
        self.pending += 1
        self.clean_btn.state(["disabled"])
        self.jobs.put(job)

    def _worker(self):
        while True:
            job = self.jobs.get()
            iid = job[1]
            try:
                if job[0] == "inspect":
                    self.results.put(("inspected", iid, show_metadata(job[2])))
                else:
                    self.results.put(("cleaned", iid, clean_file(job[2], job[3], job[4])))
            except Exception as exc:  # never let the worker die silently
                self.results.put(("error", iid, str(exc)))

    def _poll(self):
        try:
            while True:
                self.add_files(self.drop_queue.get_nowait())
        except queue.Empty:
            pass
        try:
            while True:
                kind, iid, data = self.results.get_nowait()
                self.pending -= 1
                if iid in self.items:
                    getattr(self, "_on_" + kind)(iid, data)
        except queue.Empty:
            pass
        if self.pending <= 0:
            self.pending = 0
            self.clean_btn.state(["!disabled"])
        self.root.after(100, self._poll)

    def _on_inspected(self, iid, text):
        it = self.items[iid]
        it["before"] = text
        if is_unsupported(text):
            it["state"] = "unsupported"
            self._set_row(iid, "Not supported by mat2", "-")
        else:
            n = count_items(text)
            it["state"] = "ready"
            self._set_row(iid, "Ready" if n else "No metadata found", "%d items" % n)
        if self.tree.selection() == (iid,):
            self._show_selected()

    def _on_error(self, iid, message):
        self.items[iid]["state"] = "failed"
        self.items[iid]["after"] = "Error: " + message
        self._set_row(iid, "Failed")
        self._show_selected()

    def _on_cleaned(self, iid, res):
        it = self.items[iid]
        if not res["ok"]:
            it["state"] = "failed"
            it["after"] = "Not cleaned: " + res["message"]
            self._set_row(iid, "Failed: " + res["message"][:60], after="-")
        else:
            it["state"] = "cleaned"
            it["output"] = res["output"]
            n = count_items(res["after"], ignore_neutral=True)
            text = res["after"] or "(mat2 printed nothing)"
            if res["check"]:
                text += "\n\nStructure check (Office files):\n" + res["check"]
            text += "\n\nSaved as:\n" + res["output"]
            it["after"] = text
            self._set_row(iid, "Cleaned" if n == 0 else "Cleaned; %d items remain" % n,
                          after="%d items" % n)
        if self.tree.selection() == (iid,):
            self._show_selected()
        if self.pending <= 0:
            done = sum(1 for x in self.items.values() if x["state"] == "cleaned")
            self._say("Finished. %d cleaned copy(ies) saved; originals untouched." % done)

    def clean_all(self):
        folder = None
        if self.dest_mode.get() == "folder":
            folder = self.dest_dir.get().strip()
            if not folder or not os.path.isdir(folder):
                messagebox.showwarning("Output folder", "Choose an existing folder first.")
                return
        todo = [i for i, it in self.items.items() if it["state"] == "ready"]
        if not todo:
            self._say("Nothing to clean: add files that mat2 supports.")
            return
        self._say("Cleaning %d file(s)\u2026" % len(todo))
        for iid in todo:
            self.items[iid]["state"] = "cleaning"
            self._set_row(iid, "Cleaning\u2026")
            self._enqueue(("clean", iid, self.items[iid]["path"], folder, self.light.get()))


def main():
    if "--check" in sys.argv:  # used by the build: loads Tcl/Tk, shows nothing
        # importing tkinter already proved that _tkinter and its DLLs load;
        # starting a bare Tcl proves that the Tcl script library is found
        print("Tcl %s ok" % tk.Tcl().eval("info patchlevel"))
        try:
            root = tk.Tk()
        except tk.TclError as exc:
            # e.g. a build machine without a desktop; the window cannot be tested there
            print("Tk window could not be created here (%s); not treated as an error" % exc)
            return 0
        root.withdraw()
        root.update()
        print("Tk %s ok" % root.tk.call("info", "patchlevel"))
        root.destroy()
        return 0
    if os.name == "nt":
        try:
            import ctypes
            ctypes.windll.shcore.SetProcessDpiAwareness(1)  # sharp text
        except Exception:
            pass
    root = tk.Tk()
    try:
        ttk.Style().theme_use("vista" if os.name == "nt" else "clam")
    except tk.TclError:
        pass
    app = App(root)
    files = [a for a in sys.argv[1:] if not a.startswith("--")]
    if files:
        app.add_files(files)
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
