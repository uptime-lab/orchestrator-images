# kiosk

Shows one URL fullscreen on the HDMI output of a Raspberry Pi that runs
Ubuntu **Server** — a host with no display server at all. The compositor
lives inside the container and draws straight to the kernel's DRM/KMS device.
This is the image behind the Orchestrator `kiosk` utility.

Package: `ghcr.io/uptime-lab/orchestrator-kiosk`, `linux/arm64` only.

## What is inside

Debian trixie (`debian:trixie-slim`, digest pinned in the Dockerfile) plus:

| Package | Role |
|---|---|
| `cage` | Single-application Wayland compositor (wlroots 0.18). One fullscreen client, nothing else. |
| `seatd` | Hands the DRM device to the compositor without logind or a VT. Runs as root; cage runs as the unprivileged `kiosk` user. |
| `chromium` | Debian's own deb, pinned by the image tag. Not Ubuntu's snap, which self-updates on the device. |
| `xwayland` | Only so Chromium's Ozone/Wayland path has the fallback it links against. |
| `libgl1-mesa-dri` | Mesa 25 — the `vc4` display driver and the `v3d` GPU driver for Pi 4 (v3d 4.2) and Pi 5 (v3d 7.1). |
| `grim` | Screenshot of what is actually on screen via `wlr-screencopy`; the platform's health check for "container up, HDMI black". |
| `fonts-dejavu-core`, `fonts-noto-core`, `fonts-noto-color-emoji` | Enough glyph coverage for dashboards and menus in most scripts. |
| `ca-certificates`, `curl` | HTTPS trust, and the DevTools probe below. |

Nothing is copied into the image except `entrypoint.sh`. No users beyond the
ones the packages create and `kiosk` (no password, no shell).

## How it runs

`entrypoint.sh`, in order:

1. Hands the `/dev/dri/*` nodes to the `kiosk` group (they arrive with the
   host's gids) — without the render node wlroots' GLES renderer cannot start.
2. Starts `seatd` as root with `SEATD_VTBOUND=0`: there is no `/dev/tty*` in
   the container, and a VT-bound seat never becomes active without one.
3. Picks the display card by driver name (`vc4`), because on Pi 5 / CM5 the
   `v3d` render-only node and the `vc4` HDMI node come up as `card0`/`card1`
   in either order, and the wrong one is a black screen with a healthy
   compositor.
4. Drops to `kiosk` and runs `cage` with one Chromium in `--kiosk` mode,
   Ozone/Wayland, no sandbox (the container is the sandbox), remote debugging
   on `127.0.0.1:9222` inside the container's own network namespace.

### The contract with the agent

The Orchestrator agent starts the container like this, and the image is
written against exactly these knobs:

```
docker run -d --name orchestrator-kiosk --restart unless-stopped \
  --device /dev/dri --shm-size 512m --security-opt no-new-privileges=true \
  -e KIOSK_URL=<url> [-e WLR_BACKENDS=headless] <image>
```

| Knob | Meaning |
|---|---|
| `KIOSK_URL` | The page to show. Required in practice; the image default is `about:blank`. |
| `KIOSK_EXTRA_CHROMIUM_ARGS` | Extra Chromium flags, space-separated. Empty by default. |
| `WLR_BACKENDS=headless` | Software-only validation with no display attached. **Unset** for a real display — an empty value is an empty backend list to wlroots and Chromium never starts. |
| `--device /dev/dri` | The display and render nodes. Nothing else from `/dev`. |
| `/dev/input` | Deliberately **not** passed: that is the input lockdown. No keyboard, no mouse, no touch. |
| `127.0.0.1:9222` | Chromium DevTools. The agent asks `GET /json/version` through `docker exec`; the port is never on the LAN. |

Health means two things: the container is running, **and** DevTools answers.
A compositor crash-loop fails the second question immediately instead of
sitting behind a green container.

## What it does not do

- **No input.** Any page that needs a click — a cookie banner, a consent
  screen, a login — sits there forever. Use URLs that render without one.
- **No audio.** `/dev/snd` is not passed and no ALSA client is installed.
- **No hardware video decode.** Debian's Chromium has no V4L2 decoder
  support, and the Pi 5 has no H.264 decoder at all. Video is decoded on the
  CPU: 1080p is fine on a Pi 5, a Pi 4 tops out around 720p.
- **No DRM/Widevine.** Debian's arm64 Chromium does not ship it.
- **No multi-display, no rotation.** One output, as connected.

## Building and trying it by hand

```bash
docker build -t orchestrator-kiosk:dev .            # on an arm64 host
docker run -d --name kiosk --device /dev/dri --shm-size 512m \
  -e KIOSK_URL=https://example.com orchestrator-kiosk:dev
docker exec kiosk curl -s http://127.0.0.1:9222/json/version   # health
docker exec kiosk sh -c 'cd /run/kiosk && XDG_RUNTIME_DIR=/run/kiosk \
  WAYLAND_DISPLAY=$(ls | grep ^wayland- | grep -v lock) grim /tmp/shot.png'
docker cp kiosk:/tmp/shot.png .                               # what is on screen
```

Releases are cut from this repository's root: tag `kiosk-v<semver>` and push
it (see the top-level README).
