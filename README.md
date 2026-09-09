# orchestrator-images

Container images that the [Orchestrator](https://github.com/uptime-lab/orchestrator)
agent runs on managed Raspberry Pi nodes. One directory per image, one GHCR
package per image, one repository for all of them.

| Directory | Package | What it is |
|---|---|---|
| [`kiosk/`](kiosk/README.md) | `ghcr.io/uptime-lab/orchestrator-kiosk` | Fullscreen Chromium on the node's HDMI output (the platform's `kiosk` utility): cage + seatd drawing straight to `/dev/dri` on a host with no graphics stack. |

## Releasing an image

Tag the commit `<image>-v<semver>` and push the tag:

```bash
git tag kiosk-v0.1.0
git push origin kiosk-v0.1.0
```

The `Images` workflow builds on a GitHub-hosted arm64 runner and publishes
`ghcr.io/uptime-lab/orchestrator-<image>:<semver>` and `:latest`, with an
SBOM and build provenance attached. Pull requests and pushes to `main` build
every image and publish nothing.

**The device pulls anonymously**, so a package must be **public**. Check it
after the first publish of a new image: GitHub → organisation → Packages →
the package → Package settings → Danger zone → Change visibility.

## Rules

- **arm64 only.** These images run on Raspberry Pi nodes; nothing else is
  built and a multi-arch manifest would only invite a wrong pull elsewhere.
- **Base images are pinned by digest** and Dependabot proposes the bumps.
- **GitHub-hosted runners, never the org's self-hosted ones.** The repository
  is public; a self-hosted runner must never execute a stranger's pull request.
- **The agent's `docker run` is the contract.** Environment names, the
  devices passed in, and the DevTools health probe are decided in the
  orchestrator repository (`agent/pkg/application/handlers/utility_appliers_linux.go`);
  an image change that alters them ships together with the agent change.
