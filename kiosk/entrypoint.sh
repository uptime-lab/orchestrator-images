#!/bin/sh
# Kiosk entrypoint: a root seatd owns the seat (DRM master, input) and a
# NON-root cage runs one fullscreen chromium as its libseat client — cage
# refuses to start as root, and this split is the canonical no-logind
# arrangement anyway. Input lockdown is done by NOT mounting /dev/input.
set -eu

export XDG_RUNTIME_DIR=/run/kiosk
mkdir -p "$XDG_RUNTIME_DIR"
chown kiosk:kiosk "$XDG_RUNTIME_DIR"
chmod 0700 "$XDG_RUNTIME_DIR"

# The DRM nodes arrive with the HOST's gids; hand them to the compositor's
# user inside the container (this edits the container's /dev tmpfs only).
# Without the render node wlroots' GLES renderer cannot initialise and cage
# sits alive with no output — the exact failure this line was added for.
for dev in /dev/dri/*; do
    [ -c "$dev" ] || continue
    chgrp kiosk "$dev" 2>/dev/null || true
    chmod g+rw "$dev" 2>/dev/null || true
done

# seatd's socket is group-owned by the compositor's user so nothing else in
# the container can take the seat. The container has no /dev/tty*, and a
# VT-bound seat never becomes active without one ("Could not open tty0",
# then wlroots times out waiting for the session) — the host is a server
# with no other compositor to hand the seat back to, so bind to no VT.
export SEATD_VTBOUND=0
seatd -g kiosk &
i=0
while [ ! -S /run/seatd.sock ] && [ "$i" -lt 50 ]; do i=$((i + 1)); sleep 0.1; done

# No input devices are mounted — that IS the kiosk lockdown — and libinput
# must be told so, or wlroots refuses to start over an empty seat.
export WLR_LIBINPUT_NO_DEVICES=1

# Pin wlroots to the DISPLAY card. Pi 5 / CM5 expose v3d (render-only) and
# vc4 (the HDMI CRTCs) as card0/card1 in racey order; picking the wrong one
# is a black screen with a healthy-looking compositor.
DRM_ENV=""
for card in /dev/dri/card*; do
    [ -e "$card" ] || continue
    name=$(basename "$card")
    driver=$(readlink "/sys/class/drm/$name/device/driver" 2>/dev/null || true)
    case "$driver" in *vc4*) DRM_ENV="WLR_DRM_DEVICES=$card"; break ;; esac
done

# WLR_BACKENDS is UNSET for real DRM output; the platform's software-only
# validation (no display attached — lab benches) sets WLR_BACKENDS=headless.
# Unset, not empty: wlroots treats an empty WLR_BACKENDS as an empty LIST of
# backends, never probes DRM, and cage dies at "Failed to create allocator"
# with seatd never seeing a client — the container reads as Up with a black
# HDMI. That is exactly what the image's old `ENV WLR_BACKENDS=""` produced
# on every real display (measured on a Pi 5, 2026-09-09).
BACKEND_ENV=""
if [ -n "${WLR_BACKENDS:-}" ]; then
    BACKEND_ENV="WLR_BACKENDS=${WLR_BACKENDS}"
fi
unset WLR_BACKENDS

# --no-sandbox: chromium's user-namespace sandbox is unavailable under the
# container runtime's default seccomp; the container is the sandbox here.
# --remote-debugging-port binds inside the container's network namespace; the
# health probe reaches it via docker exec, never the LAN.
exec setpriv --reuid kiosk --regid kiosk --init-groups \
    env HOME=/home/kiosk \
        XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
        LIBSEAT_BACKEND=seatd \
        WLR_LIBINPUT_NO_DEVICES=1 \
        $DRM_ENV \
        $BACKEND_ENV \
    cage -d -- chromium \
        --kiosk \
        --no-sandbox \
        --no-first-run \
        --disable-dev-shm-usage \
        --noerrdialogs \
        --disable-infobars \
        --disable-session-crashed-bubble \
        --disable-features=TranslateUI \
        --autoplay-policy=no-user-gesture-required \
        --check-for-update-interval=31536000 \
        --remote-debugging-port=9222 \
        --ozone-platform=wayland \
        $KIOSK_EXTRA_CHROMIUM_ARGS \
        "$KIOSK_URL"
