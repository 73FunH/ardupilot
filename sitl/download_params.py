#!/usr/bin/env python3
"""
Download all parameters from a vehicle via mavproxy's UDP service port (14577).
Scans for heartbeats, shows a GUI to select target SYSID, then downloads and saves.
"""
import datetime
import os
import threading
import time
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

SERVICE_URL  = 'udpout:127.0.0.1:14577'
SCAN_SECONDS = 2
REPO         = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SAVE_DIR = os.path.join(REPO, 'sitl')


def scan_sysids(url, duration):
    from pymavlink import mavutil
    try:
        mav = mavutil.mavlink_connection(url, source_system=255)
        # Send a heartbeat so mavproxy learns our source port and forwards data to us
        mav.mav.heartbeat_send(
            mavutil.mavlink.MAV_TYPE_GCS,
            mavutil.mavlink.MAV_AUTOPILOT_INVALID,
            0, 0, 0)
        time.sleep(0.1)
        deadline = time.time() + duration
        sysids = set()
        while time.time() < deadline:
            msg = mav.recv_match(type='HEARTBEAT', blocking=True, timeout=0.5)
            if msg:
                sid = msg.get_srcSystem()
                if sid != 255:  # skip GCS heartbeats
                    sysids.add(sid)
        mav.close()
        return sorted(sysids)
    except Exception as e:
        print(f"[download_params] scan error: {e}")
        return []


def download_params(url, target_sysid, progress_cb, timeout=60):
    from pymavlink import mavutil
    mav = mavutil.mavlink_connection(url, source_system=255)
    mav.target_system    = target_sysid
    mav.target_component = 1

    # Send a heartbeat so mavproxy learns our source port and forwards data to us
    mav.mav.heartbeat_send(
        mavutil.mavlink.MAV_TYPE_GCS,
        mavutil.mavlink.MAV_AUTOPILOT_INVALID,
        0, 0, 0)
    time.sleep(0.1)

    # Wait for heartbeat
    deadline = time.time() + 10
    while time.time() < deadline:
        msg = mav.recv_match(type='HEARTBEAT', blocking=True, timeout=1)
        if msg and msg.get_srcSystem() == target_sysid:
            break
    else:
        mav.close()
        return None

    mav.mav.param_request_list_send(target_sysid, 1)

    params = {}
    total   = None
    deadline = time.time() + timeout
    while time.time() < deadline:
        msg = mav.recv_match(type='PARAM_VALUE', blocking=True, timeout=2)
        if msg is None:
            if total and len(params) >= total:
                break
            continue
        if msg.get_srcSystem() != target_sysid:
            continue
        total = msg.param_count
        name  = msg.param_id.rstrip('\x00')
        params[name] = msg.param_value
        progress_cb(len(params), total, name)
        if len(params) >= total:
            break

    mav.close()
    return params if (total and len(params) >= total) else None


def save_params(params, path):
    save_dir = os.path.dirname(path)
    if save_dir:
        os.makedirs(save_dir, exist_ok=True)
    with open(path, 'w') as f:
        for name, value in sorted(params.items()):
            if value == int(value):
                f.write(f"{name:<16} {int(value)}\n")
            else:
                f.write(f"{name:<16} {value:.6f}\n")


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("ArduPilot Parameter Downloader")
        self.resizable(False, False)
        self._selected_sysid = None
        self._build_ui()
        self._scan()

    def _build_ui(self):
        pad = dict(padx=10, pady=6)

        # SYSID selection
        frm_top = ttk.LabelFrame(self, text=f"Detected vehicles  (scan {SCAN_SECONDS}s)")
        frm_top.pack(fill='x', **pad)

        self.lb_sysid = tk.Listbox(frm_top, height=5, width=22, exportselection=False)
        self.lb_sysid.pack(side='left', padx=6, pady=6)
        self.lb_sysid.bind('<<ListboxSelect>>', self._on_sysid_select)

        frm_btns = ttk.Frame(frm_top)
        frm_btns.pack(side='left', padx=6)
        ttk.Button(frm_btns, text="Refresh", command=self._scan).pack(pady=4)
        self.lbl_scan = ttk.Label(frm_btns, text="Scanning…")
        self.lbl_scan.pack(pady=4)

        # Save path
        frm_file = ttk.LabelFrame(self, text="Save as")
        frm_file.pack(fill='x', **pad)

        self.var_path = tk.StringVar()
        ttk.Entry(frm_file, textvariable=self.var_path, width=56).pack(side='left', padx=6, pady=6)
        ttk.Button(frm_file, text="Browse…", command=self._browse).pack(side='left', padx=4)

        # Progress
        self.var_progress = tk.StringVar(value="")
        ttk.Label(self, textvariable=self.var_progress).pack(padx=10, pady=(6, 0))
        self.progress = ttk.Progressbar(self, length=440, mode='determinate')
        self.progress.pack(padx=10, pady=4)

        # Download button
        self.btn_dl = ttk.Button(self, text="Download parameters",
                                 command=self._download, state='disabled')
        self.btn_dl.pack(pady=10)

    # --- scanning ---

    def _scan(self):
        self.lbl_scan.config(text="Scanning…")
        self.lb_sysid.delete(0, 'end')
        self.btn_dl.config(state='disabled')
        threading.Thread(target=self._scan_thread, daemon=True).start()

    def _scan_thread(self):
        ids = scan_sysids(SERVICE_URL, SCAN_SECONDS)
        self.after(0, self._scan_done, ids)

    def _scan_done(self, ids):
        self.lb_sysid.delete(0, 'end')
        if ids:
            for sid in ids:
                self.lb_sysid.insert('end', f"SYSID {sid}")
            self.lbl_scan.config(text=f"{len(ids)} vehicle(s) found")
            self.lb_sysid.select_set(0)
            self._on_sysid_select(None)
        else:
            self.lbl_scan.config(text="None found — mavproxy running?")

    # --- sysid selection ---

    def _on_sysid_select(self, _event):
        sel = self.lb_sysid.curselection()
        if not sel:
            return
        sysid = int(self.lb_sysid.get(sel[0]).split()[1])
        self._selected_sysid = sysid
        now   = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
        fname = f"vehicle_{sysid}_{now}.parm"
        self.var_path.set(os.path.join(DEFAULT_SAVE_DIR, fname))
        self.btn_dl.config(state='normal')

    # --- browse ---

    def _browse(self):
        cur = self.var_path.get()
        path = filedialog.asksaveasfilename(
            title="Save parameters as",
            initialdir=os.path.dirname(cur) if cur else DEFAULT_SAVE_DIR,
            initialfile=os.path.basename(cur),
            defaultextension=".parm",
            filetypes=[("Parameter files", "*.parm"), ("All files", "*")],
        )
        if path:
            self.var_path.set(path)

    # --- download ---

    def _download(self):
        if self._selected_sysid is None:
            return
        path = self.var_path.get().strip()
        if not path:
            messagebox.showerror("Error", "Please specify a save path.")
            return

        self.btn_dl.config(state='disabled')
        self.progress['value'] = 0
        self.var_progress.set("Connecting…")

        threading.Thread(
            target=self._download_thread,
            args=(self._selected_sysid, path),
            daemon=True,
        ).start()

    def _download_thread(self, sysid, path):
        def progress_cb(current, total, name):
            self.after(0, self._update_progress, current, total, name)

        params = download_params(SERVICE_URL, sysid, progress_cb)
        self.after(0, self._download_done, params, path)

    def _update_progress(self, current, total, name):
        self.var_progress.set(f"Downloading… {current}/{total}  [{name}]")
        self.progress['maximum'] = total
        self.progress['value']   = current

    def _download_done(self, params, path):
        self.btn_dl.config(state='normal')
        if params is None:
            self.var_progress.set("Failed.")
            messagebox.showerror("Failed",
                "Could not download parameters.\n"
                "Check that mavproxy is running and the vehicle is connected.")
            return
        save_params(params, path)
        self.var_progress.set(f"Saved {len(params)} parameters → {os.path.basename(path)}")
        messagebox.showinfo("Success", f"Saved {len(params)} parameters to:\n{path}")


if __name__ == '__main__':
    App().mainloop()
