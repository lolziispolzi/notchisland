# Releasing

Releases are built by `.github/workflows/release.yml` when you push a tag that starts with `v`.

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow runs the tests, builds a universal app, and publishes `NotchIsland-<version>.dmg` and `.zip` on the GitHub Releases page.

## Unsigned releases (default)

With no secrets configured, the app is ad-hoc signed. Users must allow it once under **System Settings → Privacy & Security → Open Anyway**.

## Signed and notarized releases

You need a paid Apple Developer account and a **Developer ID Application** certificate.

Add these repository secrets under **Settings → Secrets and variables → Actions**:

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE` | The Developer ID Application certificate exported as `.p12`, base64-encoded: `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | Password you set when exporting the `.p12` |
| `SIGN_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_TEAM_ID` | 10-character team ID |
| `APPLE_APP_PASSWORD` | App-specific password from appleid.apple.com |

With these set, the workflow signs with the hardened runtime, notarizes the DMG, and staples the ticket.

## Building a signed release locally

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
APPLE_ID="you@example.com" APPLE_TEAM_ID="TEAMID" APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
VERSION=0.1.0 ./scripts/build-app.sh
```

## Checklist

1. Move the `[Unreleased]` entries in `CHANGELOG.md` under the new version.
2. Commit, tag and push the tag.
3. Check the release page and download the DMG once to confirm it opens.
