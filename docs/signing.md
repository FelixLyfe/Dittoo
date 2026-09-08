# Local signing

The project expects a persistent self-signed code-signing identity named `Dittoo Self-Signed`.
Keeping the same identity and stable bundle ID prevents needless Accessibility-grant churn.
Install a certificate with this exact name before packaging. Update the repository signing secrets
with its matching certificate and private key before publishing through GitHub Actions.

Check available identities:

```sh
security find-identity -v -p codesigning
```

For compilation-only checks, pass `CODE_SIGNING_ALLOWED=NO`. For a runnable Release artifact, create
or install the named identity in the login keychain, then build without that override. This identity
is for local distribution only and does not provide notarization.
