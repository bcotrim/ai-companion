# Release Checklist

This project currently ships unsigned/ad-hoc signed builds. That avoids Apple Developer Program signup, but users may see Gatekeeper friction on first launch.

Before tagging a release:

1. Run `make test`.
2. Run `make app`.
3. Verify `dist/AICompanion.zip` exists.
4. Verify `dist/AICompanion.zip.sha256` exists and matches the zip.
5. Open the built app locally.
6. Use **Setup Guide...** or **Install/Repair Hooks**.
7. Drive synthetic events from the README.
8. Confirm **Agent Dashboard...** shows sessions and recent events.
9. Upload both zip and checksum to the GitHub release.

When ready for a lower-friction public install, switch to Developer ID signing and notarization using the existing `make notarized-app` target.
