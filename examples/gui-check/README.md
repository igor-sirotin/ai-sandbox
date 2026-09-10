# GUI check

A throwaway app for answering "can this sandbox VM show me a window?" — and for
telling the three ways of doing that apart when one of them misbehaves.

The VMs are Ubuntu *server* cloud images with no graphical stack and no GPU
device passed through, so every route below renders in software. That is fine
for widgets, browsers and Electron; it is not fine for 3D.

```sh
cd examples/gui-check
./gui-check.sh deps       # xvfb, xauth, x11-apps, python3-tk, scrot
./gui-check.sh            # what's available, and what each route still needs
```

## Route 1 — headless (Xvfb)

Nothing is needed on the Mac. This is the route that matters for agents: GUI test
suites, Electron, Playwright/Puppeteer, screenshot capture.

```sh
./gui-check.sh headless           # writes gui-check.png
./gui-check.sh headless /tmp/x.png
```

It starts an `Xvfb` on the first free display, runs the demo against it, and
screenshots the result. For your own commands, `xvfb-run` is usually enough:

```sh
xvfb-run -a npm test
xvfb-run -a --server-args="-screen 0 1920x1080x24" ./some-gui-app
```

## Route 2 — SSH X11 forwarding to XQuartz

Individual windows on the Mac's desktop. The guest half is ready out of the box
(`X11Forwarding yes`, `xauth` installed); the Mac needs XQuartz, and you have to
connect with `ssh` directly, since `limactl shell` won't pass `-Y`:

```sh
# on the Mac, once
brew install --cask xquartz        # then log out and back in

ssh -Y -F ~/.lima/claude-<project>/ssh.config lima-claude-<project>
```

Then, in that session:

```sh
./gui-check.sh run     # the demo
./gui-check.sh apps    # xeyes, xclock, xlogo — the classic smoke test
```

If the bouncing dot stutters, that's the SSH round trip, not the VM.

## Route 3 — a full desktop over VNC

The heaviest and the most solid: a real session you can leave running, with a
window manager, clipboard and multiple apps. Lima forwards the port to the Mac's
loopback by itself, so macOS Screen Sharing reaches it with no extra config.

```sh
sudo apt-get install -y xfce4 xfce4-goodies tigervnc-standalone-server
vncpasswd
vncserver :1 -geometry 1600x1000 -localhost no
```

Then on the Mac: `open vnc://localhost:5901`. Inside the desktop, run
`./gui-check.sh run` in a terminal to confirm the app path works too.

Lima can also open a native window for a `vz` VM (`video.display: vz` in the
instance YAML), but that needs the VM re-created *and* a desktop installed in the
guest anyway — so it buys nothing over VNC here.

## Files

- `gui-check.sh` — the doctor and the runner for each route.
- `gui-demo.py` — the app itself. Tk only, so it runs on a VM where nothing
  graphical is installed yet. It prints which X server it reached, animates (so
  latency is visible) and takes a click (so input is exercised, not just
  drawing). `--seconds N` makes it quit by itself for screenshot runs.
