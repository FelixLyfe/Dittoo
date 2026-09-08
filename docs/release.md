# GitHub release

Dittoo ships as a self-signed `.app` inside a ZIP. It is not notarized or distributed through the
App Store. Releases currently target Apple Silicon Macs running macOS 26 or later.

## Remote signing setup

Configure these repository Actions secrets once:

- `SIGNING_P12_BASE64`: the Base64-encoded, password-protected PKCS#12 export of the
  `Dittoo Self-Signed` certificate and its matching private key.
- `SIGNING_P12_PASSWORD`: the export password.

Use the identity described in [signing](signing.md). The Release workflow imports it into
a temporary runner keychain and removes that keychain after the job. No provisioning profile or
Developer ID identity is required for the current self-signed distribution.

## Publish by pushing a tag

1. Set `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Add release notes under `docs/releases/v<version>.md`.
3. Run `xcodegen generate`, tests, lint, and clean Debug/Release builds, then commit the changes.
4. Push the commit and its version tag. For version `0.2.0`:

```sh
git tag -a v0.2.0 -m "Dittoo 0.2.0"
git push origin main v0.2.0
```

The [Release workflow](../.github/workflows/release.yml) starts on pushed `v*` tags and accepts
stable `vMAJOR.MINOR.PATCH` versions matching `project.yml`. It checks out the tagged commit,
regenerates the project, runs tests and lint, performs clean Debug and signed Release builds on
macOS 26, verifies the signature and checksum, then publishes the arm64 ZIP and SHA-256 file to
GitHub Releases. A failed check prevents publication. Pushing `main` alone does not publish.

The workflow includes the requirements and self-signing limitations in every release. After a
failed run has been repaired, rerun it from Actions; do not move an already published version tag.

## Local packaging

The same packaging script remains available for local verification:

```sh
./Scripts/package-release.sh
```

Build products stay under DerivedData during `clean build`, then the verified app is copied into
the distribution directory. The script writes:

- `dist/Dittoo.app`
- `dist/Dittoo-<version>-macOS-arm64.zip`
- `dist/Dittoo-<version>-macOS-arm64.zip.sha256`

`dist/` and the DerivedData under `build/` are ignored by Git. `DITTOO_DERIVED_DATA_PATH` and
`DITTOO_CODE_SIGN_IDENTITY` override local defaults.
