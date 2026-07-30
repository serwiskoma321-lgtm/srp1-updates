# Firmware policy workflow

`repack-firmware-policy.yml` creates a new signed KFW policy revision without
recompiling or decrypting the firmware payload.

The workflow:

1. Finds the source package by its manifest ID.
2. Verifies the manifest size and SHA-256.
3. Verifies the source KFW2 payload hash and ECDSA signature.
4. Copies the encrypted payload byte for byte.
5. Creates a new signed header with the requested VIN and MAC rules.
6. Writes a new immutable KFW path under `policy-N`.
7. Prepends the new package to the manifest.
8. Optionally marks the source package as `disabled`.
9. Commits the package and manifest together.

## Required secret

The `firmware-signing` GitHub environment must contain:

```text
KOMA_OTA_PRIVATE_KEY_B64
```

It is the base64 content of the 104-byte `ECS2` P-256 private-key blob. Never
commit this value or pass it as a workflow input.

## Policy rules

- `update` requires at least one VIN rule. MAC restrictions are optional.
- `emergency` ignores VIN and writes `*`; it requires at least one exact MAC.
- VIN rules cannot contain `|` because that separator is added by the signer.
- MAC values are normalized to uppercase colon notation.
- A request ID is an idempotency key. Repeating it does not create another
  package.

The administrator app will trigger this workflow through a GitHub App user
token with only `Actions: write` permission.

## Administrator app

The Android administrator flow uses GitHub Device Flow. The public GitHub App
client ID is supplied when Flutter is built:

```powershell
flutter build apk --release `
  --dart-define=KOMA_GITHUB_CLIENT_ID=Iv1.REPLACE_WITH_CLIENT_ID
```

The GitHub App must:

1. Enable Device Flow.
2. Have repository `Actions: read and write` permission.
3. Be installed only on `serwiskoma321-lgtm/srp1-updates`.

The phone stores the short-lived user access token in Android Keystore. It
never receives the firmware signing key. Before dispatching, the app validates
the policy, shows the full change, and asks Android to authenticate the local
user with biometrics or the device credential.

The workflow run name includes the application-generated request ID, allowing
the phone to find and monitor exactly the run it dispatched.

## Environment protection

Create an environment named `firmware-signing`. For production, configure a
required reviewer so that a compromised administrator session cannot use the
signing key without a second GitHub approval.
