# Code Signing

TTSim release builds are signed on both Windows and macOS. Signing runs only on tag-triggered
builds (`v*` tags). Pre-release builds from branch pushes are unsigned.

## Architecture

- **Windows**: `sign-windows` job on `windows-latest` — downloads the exported `.exe`, signs it
  via Azure Artifact Signing, re-uploads as `TTSim-Windows-Signed`.
- **macOS**: `sign-macos` job on `macos-latest` — downloads the exported `.app`, signs with
  `codesign`, submits to Apple for notarization, staples the ticket, re-uploads as
  `TTSim-macOS-Signed`.
- **Release job**: uses the signed artifacts on tag builds, unsigned on pre-release builds.

## GitHub Secrets Reference

All secrets are set at: **Repository → Settings → Secrets and variables → Actions**

### macOS (7 secrets)

| Secret | Description | Source |
|---|---|---|
| `MACOS_CERTIFICATE` | Base64-encoded Developer ID Application certificate + private key | See rotation below |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting the `.p12` export | Set during export from Keychain Access |
| `MACOS_CERTIFICATE_NAME` | Full identity string used by `codesign` | Output of `security find-identity -v -p codesigning` on the Mac that holds the certificate |
| `MACOS_NOTARIZATION_API_KEY` | Base64-encoded App Store Connect API private key (`.p8`) | See rotation below |
| `MACOS_NOTARIZATION_API_KEY_ID` | 10-character Key ID | App Store Connect → Users and Access → Integrations → App Store Connect API → Key ID column |
| `MACOS_NOTARIZATION_API_ISSUER` | Issuer ID UUID | App Store Connect → Users and Access → Integrations → App Store Connect API → Issuer ID (shown above the keys table) |
| `MACOS_CI_KEYCHAIN_PASSWORD` | Random password for the temporary CI keychain | Any random string — generate with `openssl rand -base64 20` |

### Windows (6 secrets)

| Secret | Description | Source |
|---|---|---|
| `AZURE_TENANT_ID` | Azure Active Directory tenant (directory) ID | Azure Portal → Microsoft Entra ID → Overview → Directory ID |
| `AZURE_CLIENT_ID` | Application (client) ID of the `TTSim GitHub Actions` service principal | Azure Portal → Microsoft Entra ID → App registrations → TTSim GitHub Actions → Application (client) ID |
| `AZURE_CLIENT_SECRET` | Client secret value (not the secret ID) | Azure Portal → Microsoft Entra ID → App registrations → TTSim GitHub Actions → Certificates & secrets → Value column |
| `ARTIFACT_SIGNING_ENDPOINT` | Artifact Signing account endpoint URL | Azure Portal → Artifact Signing account → Overview → Endpoint |
| `ARTIFACT_SIGNING_ACCOUNT` | Artifact Signing account name | Azure Portal → Artifact Signing account → name shown in breadcrumb |
| `ARTIFACT_SIGNING_CERT_PROFILE` | Certificate profile name | Azure Portal → Artifact Signing account → Certificate Profiles → profile name |

## Rotation Procedures

### Rotate macOS certificate (`MACOS_CERTIFICATE`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_CERTIFICATE_NAME`)

The Developer ID Application certificate is valid for 5 years from creation. Rotate when it
expires or if the private key is compromised.

1. On a Mac, open **Keychain Access → Certificate Assistant → Request a Certificate From a
   Certificate Authority**. Save to disk, Key Size 2048, Algorithm RSA.
2. Go to https://developer.apple.com/account/resources/certificates/add → Developer ID
   Application → G2 Sub-CA. Upload the CSR, download the `.cer`.
3. Double-click the `.cer` to install into the **login** keychain. Verify a private key appears
   nested under it in Keychain Access.
4. Right-click the certificate → Export → `.p12`. Set a strong password.
5. Update secrets:
   - `MACOS_CERTIFICATE`: `base64 -i /path/to/cert.p12 | tr -d '\n'`
   - `MACOS_CERTIFICATE_PASSWORD`: the new password
   - `MACOS_CERTIFICATE_NAME`: output of `security find-identity -v -p codesigning`
6. Revoke the old certificate at https://developer.apple.com/account/resources/certificates/list.

### Rotate notarization API key (`MACOS_NOTARIZATION_API_KEY`, `MACOS_NOTARIZATION_API_KEY_ID`)

App Store Connect API keys do not expire but should be rotated if compromised.

1. Go to https://appstoreconnect.apple.com → Users and Access → Integrations → App Store
   Connect API.
2. Click **+** → name it, set role to **Developer** → Generate.
3. Download the `.p8` file immediately (only available once).
4. Note the new Key ID.
5. Update secrets:
   - `MACOS_NOTARIZATION_API_KEY`: `base64 -i /path/to/AuthKey_NEWKEYID.p8 | tr -d '\n'`
   - `MACOS_NOTARIZATION_API_KEY_ID`: new Key ID
6. Revoke the old key in App Store Connect.

### Rotate Azure client secret (`AZURE_CLIENT_SECRET`)

Client secrets have an expiry date set at creation (typically 12–24 months). Azure will email
a warning before expiry.

1. Go to Azure Portal → Microsoft Entra ID → App registrations → TTSim GitHub Actions →
   Certificates & secrets.
2. Click **+ New client secret** → set description and expiry → Add.
3. **Immediately copy the Value** (only shown once).
4. Update the `AZURE_CLIENT_SECRET` secret in GitHub with the new value.
5. Delete the old secret from the Azure portal.

### Re-enroll Azure identity validation

Artifact Signing identity validations expire periodically. Azure sends reminder emails starting
60 days before expiry.

1. Go to Azure Portal → Artifact Signing account → Identity Validations.
2. Create a new identity validation request and complete the verification process.
3. Once the new validation shows **Completed**, associate it with the certificate profile.

## Entitlements

The macOS entitlements plist is at `build/macos/entitlements.plist`. The current entitlements:

- `com.apple.security.cs.disable-library-validation` — required for Godot to load `.pck` files
  and internal libraries under the hardened runtime.

If GDExtensions are added to the project in future, also add:
- `com.apple.security.cs.allow-dyld-environment-variables`

If C# (Mono) is added:
- `com.apple.security.cs.allow-jit`
- `com.apple.security.cs.allow-unsigned-executable-memory`
- `com.apple.security.cs.allow-dyld-environment-variables`

## Annual Renewals

| Service | Cost | Renewal |
|---|---|---|
| Apple Developer Program | $99/yr | Auto-renews; manage at https://developer.apple.com/account |
| Azure Artifact Signing | $9.99/mo | Azure subscription billing |
