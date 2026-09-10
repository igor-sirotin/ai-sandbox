#!/usr/bin/env bash
# Check whether this sandbox VM can put a GUI somewhere you can see it.
#
#   ./gui-check.sh              # report what's available, and what each route needs
#   ./gui-check.sh deps         # apt-install the handful of packages the rest uses
#   ./gui-check.sh headless [out.png]   # Xvfb route: no host involvement, saves a PNG
#   ./gui-check.sh run          # draw on $DISPLAY (SSH X11 forwarding, or a VNC desktop)
#   ./gui-check.sh apps         # same, but with xeyes/xclock instead of the demo
#
# The VM has no GPU device, so everything here renders in software. That is fine
# for widgets, browsers and Electron; it is not fine for 3D.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo="$here/gui-demo.py"

have() { command -v "$1" >/dev/null 2>&1; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
no()   { printf '  \033[31m✗\033[0m %s\n' "$*"; }
info() { printf '  \033[2m·\033[0m %s\n' "$*"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }

doctor() {
	head_ "This VM"
	info "host      $(hostname)"
	info "arch      $(uname -m)"
	info "DISPLAY   ${DISPLAY:-(unset)}"
	if [ -d /dev/dri ]; then ok "/dev/dri present — some hardware acceleration"
	else info "/dev/dri absent — software rendering only (expected)"; fi

	head_ "Route 1 — headless (Xvfb), nothing needed on the Mac"
	if have Xvfb; then ok "Xvfb installed"; else no "Xvfb missing — run: $0 deps"; fi
	if python3 -c 'import tkinter' 2>/dev/null; then ok "python3-tk installed (the demo needs it)"
	else no "python3-tk missing — run: $0 deps"; fi
	if have scrot || have xwd; then ok "screenshot tool available"
	else no "no scrot/xwd — run: $0 deps"; fi
	info "try: $0 headless"

	head_ "Route 2 — SSH X11 forwarding to XQuartz on the Mac"
	if have xauth; then ok "xauth installed in the guest"; else no "xauth missing — run: $0 deps"; fi
	if grep -qsE '^[[:space:]]*X11Forwarding[[:space:]]+yes' /etc/ssh/sshd_config; then
		ok "sshd has X11Forwarding yes"
	else
		no "sshd is not forwarding X11 — set X11Forwarding yes in /etc/ssh/sshd_config"
	fi
	if [ -n "${DISPLAY:-}" ] && [ -n "${SSH_CONNECTION:-}" ]; then
		ok "DISPLAY is set on this SSH session — forwarding looks live; try: $0 run"
	else
		info "on the Mac: brew install --cask xquartz (then log out and back in), and connect with"
		info "  ssh -Y -F ~/.lima/claude-<project>/ssh.config lima-claude-<project>"
		info "  ('limactl shell' does not pass -Y, so ssh directly)"
	fi

	head_ "Route 3 — a real desktop over VNC"
	if have vncserver || have Xtigervnc || have x11vnc; then
		ok "a VNC server is installed"
		info "start it, then on the Mac open vnc://localhost:5901 (Lima forwards the port for you)"
	else
		info "not installed. To set it up (~500 MB, persists — the VM is mutable):"
		info "  sudo apt-get install -y xfce4 xfce4-goodies tigervnc-standalone-server"
		info "  vncpasswd && vncserver :1 -geometry 1600x1000 -localhost no"
		info "then on the Mac: open vnc://localhost:5901"
	fi
	echo
}

deps() {
	sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
		xvfb xauth x11-apps python3-tk scrot
}

need_demo_deps() {
	have Xvfb || { echo "Xvfb missing — run: $0 deps" >&2; exit 1; }
	python3 -c 'import tkinter' 2>/dev/null || { echo "python3-tk missing — run: $0 deps" >&2; exit 1; }
}

shot() { # shot <display> <path>
	if have scrot; then DISPLAY="$1" scrot -o "$2"
	elif have xwd && have convert; then DISPLAY="$1" xwd -root | convert xwd:- "$2"
	else echo "no screenshot tool (scrot or xwd+imagemagick)" >&2; return 1; fi
}

headless() {
	need_demo_deps
	local out="${1:-$here/gui-check.png}" dpy=":99"
	# Pick a free display number so parallel runs don't collide.
	while [ -e "/tmp/.X11-unix/X${dpy#:}" ]; do dpy=":$(( ${dpy#:} + 1 ))"; done

	echo "starting Xvfb on $dpy ..."
	Xvfb "$dpy" -screen 0 1280x800x24 >/dev/null 2>&1 &
	# Global, not local: the trap runs after this function has returned.
	XVFB_PID=$!
	trap 'kill "${XVFB_PID:-}" 2>/dev/null || true' EXIT
	for _ in $(seq 40); do [ -e "/tmp/.X11-unix/X${dpy#:}" ] && break; sleep 0.1; done

	DISPLAY="$dpy" python3 "$demo" --seconds 6 &
	local app_pid=$!
	sleep 2
	shot "$dpy" "$out"
	wait "$app_pid" || true
	echo "screenshot: $out"
	have file && file "$out"
}

run_on_display() {
	need_demo_deps
	[ -n "${DISPLAY:-}" ] || { echo "DISPLAY is unset — connect with ssh -Y, or start a VNC session first" >&2; exit 1; }
	exec python3 "$demo"
}

apps() {
	[ -n "${DISPLAY:-}" ] || { echo "DISPLAY is unset — connect with ssh -Y, or start a VNC session first" >&2; exit 1; }
	have xeyes || { echo "x11-apps missing — run: $0 deps" >&2; exit 1; }
	echo "launching xeyes, xclock and xlogo on $DISPLAY — Ctrl-C to stop"
	xeyes & xclock & xlogo &
	wait
}

case "${1:-doctor}" in
	doctor|"")  doctor ;;
	deps)       deps ;;
	headless)   shift; headless "${1:-}" ;;
	run)        run_on_display ;;
	apps)       apps ;;
	*) echo "usage: $0 [doctor|deps|headless [out.png]|run|apps]" >&2; exit 2 ;;
esac
