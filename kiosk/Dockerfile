# Orchestrator kiosk container. Design and the rules it was bought with:
# orchestrator/docs/UTILITIES-PLAN.md §5.2. The agent's `docker run` contract
# (env names, devices, the DevTools probe) is in the orchestrator repo:
# agent/pkg/application/handlers/utility_appliers_linux.go.
#
# The host is Ubuntu SERVER with no graphics stack: graphics on Linux is the
# kernel (DRM/KMS), not userspace packages, so the compositor lives HERE and
# draws straight to the display via /dev/dri. Debian base on purpose — its
# chromium is a real deb on arm64, where Ubuntu's is snap-only (the exact
# auto-refresh problem the container approach exists to kill; the browser
# version is pinned by the image tag).
#
# grim is part of the product, not a debug leftover: cage is wlroots, so
# wlr-screencopy lets the platform capture WHAT IS ACTUALLY ON SCREEN — the
# health probe that catches "green unit, black HDMI".
# trixie, not bookworm (2026-09-09): bookworm's Mesa 22.3 has no v3d 7.1
# support, so on a Pi 5 / CM5 the GBM allocator never comes up and cage dies
# with "Failed to create allocator" while the container reads as Up. Mesa 25
# in trixie drives both the Pi 4 (v3d 4.2) and Pi 5 (v3d 7.1) GPUs.
FROM debian:trixie-slim@sha256:d7e12182ce18b85b93007c1dedf31f2d29e01ccf3182cc4017c709b6259bc132

RUN apt-get update && apt-get install -y --no-install-recommends \
        cage \
        chromium \
        grim \
        seatd \
        xwayland \
        libgl1-mesa-dri \
        fonts-dejavu-core \
        fonts-noto-core \
        fonts-noto-color-emoji \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# cage REFUSES to run as root (it cannot irrevocably drop privileges), so the
# compositor runs as this user while a root seatd hands it the DRM/input
# devices — the canonical libseat split, no logind required.
RUN useradd --create-home --shell /usr/sbin/nologin kiosk

COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh

# KIOSK_URL is the one required knob; the rest have kiosk-sane defaults.
# WLR_BACKENDS is deliberately NOT declared here: an empty value is not
# "unset" to wlroots (see entrypoint.sh), and the platform passes
# WLR_BACKENDS=headless only for its no-display validation mode.
ENV KIOSK_URL="about:blank" \
    KIOSK_EXTRA_CHROMIUM_ARGS=""

# Links the package to this repository on GHCR (and lets a pull answer "where
# is the Dockerfile for this"); the workflow adds the version labels.
LABEL org.opencontainers.image.source="https://github.com/uptime-lab/orchestrator-images" \
      org.opencontainers.image.description="Fullscreen browser kiosk for Orchestrator-managed Raspberry Pi nodes" \
      org.opencontainers.image.licenses="NOASSERTION"

ENTRYPOINT ["/entrypoint.sh"]
