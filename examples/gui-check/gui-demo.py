#!/usr/bin/env python3
"""A tiny GUI app for checking that a sandbox VM can display something.

Deliberately dependency-free beyond python3-tk: it has to run on a VM where
nothing graphical is installed yet. It reports which X server it reached,
animates (so forwarding latency is visible), and takes a click (so the input
path is exercised too, not just the drawing one).

    ./gui-demo.py               # run until closed; q or Escape quits
    ./gui-demo.py --seconds 3   # quit by itself, for headless/screenshot runs
"""

import argparse
import getpass
import os
import platform
import sys
import time
import tkinter as tk

BG = "#101418"
FG = "#e6edf3"
DIM = "#8b98a5"
ACCENT = "#4cc2ff"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=0,
                    help="quit automatically after N seconds (0 = run until closed)")
    args = ap.parse_args()

    try:
        root = tk.Tk()
    except tk.TclError as e:
        print(f"cannot open a display: {e}", file=sys.stderr)
        print(f"DISPLAY={os.environ.get('DISPLAY', '(unset)')}", file=sys.stderr)
        return 1

    root.title("sandbox GUI check")
    root.geometry("640x440")
    root.configure(bg=BG)

    facts = [
        ("host", platform.node()),
        ("user", getpass.getuser()),
        ("arch", platform.machine()),
        ("DISPLAY", os.environ.get("DISPLAY", "(unset)")),
        ("X server", root.winfo_server()),
        ("screen", f"{root.winfo_screenwidth()}x{root.winfo_screenheight()} "
                   f"@ {root.winfo_screendepth()}bpp"),
        ("Tk", str(tk.TkVersion)),
    ]

    tk.Label(root, text="GUI is reaching a display", bg=BG, fg=ACCENT,
             font=("TkDefaultFont", 16, "bold")).pack(pady=(16, 10))

    table = tk.Frame(root, bg=BG)
    table.pack(padx=20, fill="x")
    for row, (key, value) in enumerate(facts):
        tk.Label(table, text=key, bg=BG, fg=DIM, anchor="e", width=10,
                 font=("TkFixedFont", 10)).grid(row=row, column=0, sticky="e", padx=(0, 10))
        tk.Label(table, text=value, bg=BG, fg=FG, anchor="w",
                 font=("TkFixedFont", 10)).grid(row=row, column=1, sticky="w")

    # Animation: if this stutters over SSH X11 forwarding, that is the round-trip
    # cost you are feeling, not the VM being slow.
    canvas = tk.Canvas(root, height=60, bg="#161b22", highlightthickness=0)
    canvas.pack(fill="x", padx=20, pady=(16, 10))
    ball = canvas.create_oval(0, 0, 0, 0, fill=ACCENT, outline="")
    clock = tk.Label(root, text="", bg=BG, fg=DIM, font=("TkFixedFont", 10))
    clock.pack()

    state = {"x": 10.0, "dx": 6.0, "clicks": 0}

    def tick():
        width = max(canvas.winfo_width(), 1)
        state["x"] += state["dx"]
        if state["x"] > width - 40 or state["x"] < 10:
            state["dx"] = -state["dx"]
            state["x"] = min(max(state["x"], 10), max(width - 40, 10))
        x = state["x"]
        canvas.coords(ball, x, 15, x + 30, 45)
        clock.configure(text=time.strftime("%H:%M:%S"))
        root.after(33, tick)

    def click():
        state["clicks"] += 1
        button.configure(text=f"clicked {state['clicks']}x — input works")

    button = tk.Button(root, text="click me", command=click,
                       font=("TkDefaultFont", 12), padx=16, pady=6)
    button.pack(pady=14)

    tk.Label(root, text="q or Escape to quit", bg=BG, fg=DIM).pack()

    root.bind("<q>", lambda _: root.destroy())
    root.bind("<Escape>", lambda _: root.destroy())
    if args.seconds:
        root.after(int(args.seconds * 1000), root.destroy)

    tick()
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
