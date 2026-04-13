# Claude Code Runner — TrueNAS Custom App

A self-hosted GitHub Actions runner that uses Claude Code CLI to automatically triage and fix issues, running on your TrueNAS server using your Claude subscription.

## How it works

1. You or your wife create an issue on GitHub
2. GitHub dispatches the workflow to this runner on TrueNAS
3. Claude reads the codebase, labels the issue, and either opens a fix PR or comments with analysis
4. All Claude usage goes through your existing subscription — no API costs

## Setup

### 1. Build the runner image (one-time)

The image is built automatically by the `Build Runner Image` workflow and pushed to GHCR.
To trigger the first build: go to **Actions > Build Runner Image > Run workflow** on GitHub.

Alternatively, if the repo is private you may need to build locally and push:

```bash
cd .github/runner
docker build -t ghcr.io/william-saxton/voxl-claude-runner:latest .
docker push ghcr.io/william-saxton/voxl-claude-runner:latest
```

### 2. Create a GitHub PAT

Go to https://github.com/settings/tokens and create a **classic** token with these scopes:
- `repo` — runner registration, issue/PR access
- `read:packages` — pull the private container image from GHCR
- `write:packages` — (only needed if building/pushing the image locally)

### 3. Log in to GHCR on TrueNAS (one-time)

Before deploying the app, log in to GHCR on the TrueNAS host so Docker can pull the private image:

```bash
docker login ghcr.io -u william-saxton -p <YOUR_GITHUB_PAT>
```

This stores the credential in Docker's config and persists across pulls.

### 4. Deploy on TrueNAS

1. In TrueNAS, go to **Apps > Discover Apps > Custom App**
2. Paste the contents of `truenas-custom-app.yaml`
3. Under **Environment Variables**, add:
   - `GITHUB_TOKEN` = your PAT from step 2
4. Deploy the app

### 5. Authenticate Claude (one-time)

Once the container is running, open the TrueNAS shell and run:

```bash
docker exec -it voxl-claude-runner claude login
```

Follow the prompts to log in with your Claude account. The auth is stored in a persistent volume and survives container restarts.

### 6. Verify

- Check **GitHub > Settings > Actions > Runners** — you should see `voxl-truenas` as idle
- Create a test issue to verify the full flow

## Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Runner image with Claude CLI, SCons, GCC, Godot 4.6, GitHub runner |
| `entrypoint.sh` | Auto-registers runner, handles clean shutdown |
| `truenas-custom-app.yaml` | TrueNAS Custom App deployment config |

## Updating

When the Dockerfile changes on `main`, the `Build Runner Image` workflow rebuilds and pushes to GHCR. To pick up the new image on TrueNAS:

1. Go to **Apps > voxl-claude-runner**
2. Click **Update** or restart the app (TrueNAS pulls `latest` on restart)

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Runner shows offline | Check container logs in TrueNAS. Verify `GITHUB_TOKEN` has `repo` scope. |
| Claude auth expired | Run `docker exec -it voxl-claude-runner claude login` again. |
| Workflow hangs | Check the Actions run log. Claude has a 30-minute timeout on the triage step. |
| Image pull fails (private repo) | Build and push the image manually, or make the package public in GitHub Packages settings. |
