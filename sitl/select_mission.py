#!/usr/bin/env python3
"""
GUI for selecting a SITL vehicle SYSID and mission file.
Prints "<sysid> <mission_path>" to stdout on confirmation, then exits.
Called by upload_mission.sh which pipes the output to upload_mission.py.

Usage:
  python3 select_mission.py          # open GUI
  python3 select_mission.py <sysid>  # GUI pre-filled with sysid
"""
import os
import sys

REPO         = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MISSIONS_DIR = os.path.join(REPO, 'sitl', 'missions')
VEHICLES_DIR = os.path.join(REPO, 'sitl', 'vehicles')


def get_mission_files():
    if not os.path.isdir(MISSIONS_DIR):
        return []
    return sorted(f for f in os.listdir(MISSIONS_DIR) if f.endswith('.waypoints'))


def get_default_mission(vtype):
    prefix = 'plane_' if vtype == 'plane' else 'copter_'
    for f in get_mission_files():
        if f.startswith(prefix):
            return f
    files = get_mission_files()
    return files[0] if files else None


def get_active_vehicles():
    vehicles = []
    if not os.path.isdir(VEHICLES_DIR):
        return vehicles
    for name in sorted(os.listdir(VEHICLES_DIR)):
        dirpath = os.path.join(VEHICLES_DIR, name)
        if not os.path.isdir(dirpath):
            continue
        pid_file  = os.path.join(dirpath, 'sitl.pid')
        type_file = os.path.join(dirpath, 'type')
        if not os.path.isfile(pid_file):
            continue
        try:
            pid = int(open(pid_file).read().strip())
            os.kill(pid, 0)
        except (OSError, ValueError, ProcessLookupError):
            continue
        try:
            sysid = int(name)
        except ValueError:
            continue
        vtype = open(type_file).read().strip() if os.path.isfile(type_file) else 'unknown'
        vehicles.append({'sysid': sysid, 'type': vtype})
    return sorted(vehicles, key=lambda v: v['sysid'])


def run_gui(initial_sysid=None):
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox

    result = {}

    root = tk.Tk()
    root.title('Select Mission')
    root.resizable(False, False)
    pad = {'padx': 10, 'pady': 6}

    # ── Vehicle row ──────────────────────────────────────────────────────────
    frm_v = tk.Frame(root)
    frm_v.pack(fill='x', **pad)
    tk.Label(frm_v, text='Vehicle SYSID:', width=14, anchor='w').pack(side='left')

    vehicle_var   = tk.StringVar()
    vehicle_combo = ttk.Combobox(frm_v, textvariable=vehicle_var, width=24, state='normal')
    vehicle_combo.pack(side='left', padx=(0, 6))

    def refresh_vehicles():
        vehicles = get_active_vehicles()
        entries  = [f"{v['sysid']}  ({v['type']})" for v in vehicles]
        vehicle_combo['values'] = entries
        if entries and not vehicle_var.get():
            vehicle_combo.current(0)
            on_vehicle_changed()

    def on_vehicle_changed(event=None):
        raw = vehicle_var.get().split()[0]
        try:
            sysid = int(raw)
        except ValueError:
            return
        for v in get_active_vehicles():
            if v['sysid'] == sysid:
                dflt = get_default_mission(v['type'])
                if dflt:
                    mission_var.set(dflt)
                break

    vehicle_combo.bind('<<ComboboxSelected>>', on_vehicle_changed)
    tk.Button(frm_v, text='Refresh', command=refresh_vehicles).pack(side='left')

    # ── Mission row ──────────────────────────────────────────────────────────
    frm_m = tk.Frame(root)
    frm_m.pack(fill='x', **pad)
    tk.Label(frm_m, text='Mission file:', width=14, anchor='w').pack(side='left')

    mission_var   = tk.StringVar()
    mission_combo = ttk.Combobox(frm_m, textvariable=mission_var, width=34, state='normal')
    mission_combo['values'] = get_mission_files()
    mission_combo.pack(side='left', padx=(0, 6))

    def browse():
        path = filedialog.askopenfilename(
            title='Select mission file',
            initialdir=MISSIONS_DIR,
            filetypes=[('Waypoint files', '*.waypoints *.txt'), ('All files', '*')])
        if path:
            rel = os.path.relpath(path, MISSIONS_DIR)
            mission_var.set(rel if not rel.startswith('..') else path)

    tk.Button(frm_m, text='Browse', command=browse).pack(side='left')

    # ── Buttons ──────────────────────────────────────────────────────────────
    frm_b = tk.Frame(root)
    frm_b.pack(fill='x', padx=10, pady=(8, 10))
    tk.Button(frm_b, text='Cancel', width=10, command=root.destroy).pack(side='left')

    def confirm():
        raw = vehicle_var.get().split()[0]
        try:
            sysid = int(raw)
        except ValueError:
            messagebox.showerror('Error', 'Please enter or select a valid SYSID.')
            return
        mfile = mission_var.get().strip()
        if not mfile:
            messagebox.showerror('Error', 'Please select a mission file.')
            return
        if not os.path.isabs(mfile):
            mfile = os.path.join(MISSIONS_DIR, mfile)
        if not os.path.isfile(mfile):
            messagebox.showerror('Error', f'Mission file not found:\n{mfile}')
            return
        result['sysid']   = sysid
        result['mission'] = mfile
        root.destroy()

    tk.Button(frm_b, text='OK', width=10, command=confirm).pack(side='right')

    refresh_vehicles()
    if initial_sysid is not None:
        for i, v in enumerate(get_active_vehicles()):
            if v['sysid'] == initial_sysid:
                vehicle_combo.current(i)
                on_vehicle_changed()
                break
        else:
            vehicle_var.set(str(initial_sysid))

    root.mainloop()
    return result


def main():
    args = sys.argv[1:]
    initial_sysid = None

    if len(args) >= 1:
        try:
            initial_sysid = int(args[0])
        except ValueError:
            print('Usage: select_mission.py [sysid]', file=sys.stderr)
            sys.exit(1)

    result = run_gui(initial_sysid=initial_sysid)
    if not result:
        sys.exit(1)  # cancelled — no output

    print(f"{result['sysid']} {result['mission']}")


if __name__ == '__main__':
    main()
