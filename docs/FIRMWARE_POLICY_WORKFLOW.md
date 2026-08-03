# Firmware policy workflow

`repack-firmware-policy.yml` creates a new signed KFW policy revision without
recompiling or decrypting the firmware payload.

The workflow:

1. Finds the source package by its manifest ID.
2. Verifies the manifest size and SHA-256.
3. Verifies the source KFW2 payload hash and ECDSA signature.
4. Copies the encrypted payload byte for byte.
5. Reconstructs the requested KFW2 signed text from the source payload and the
   requested VIN/MAC rules.
6. Verifies the administrator-phone signature with the committed public key.
7. Creates a new header containing that verified signature.
8. Writes a new immutable KFW path under `policy-N`.
9. Prepends the new package to the manifest.
10. Optionally marks the source package as `disabled`.
11. Commits the package and manifest together.

## Signing key placement

The private ECDSA P-256 firmware key is not stored in this repository and is
not stored in GitHub Actions. It is imported manually into an authorized KOMA
administrator phone from a `KOMA_ADMIN_KEY_V1` (`.kadm`) file. Android stores
the imported key with `flutter_secure_storage`, backed by Android Keystore.

The key remains available across ordinary APK updates because the production
application has a stable application ID and signing certificate. It must be
imported again after application uninstall, application-data removal, or a
move to another phone. The source `.kadm` file should be removed from the phone
after import and retained in an offline backup.

GitHub stores only the public `ECS1` key in
`keys/srp1_ota_p256_public_blob.b64`. The `signature_hex` workflow input is a
64-byte IEEE P1363 ECDSA signature encoded as 128 hexadecimal characters. It
is not a private secret and is valid only for the exact product, target,
version, VIN/MAC policy, payload size, payload hash, and encryption metadata
included in the signed KFW2 text.

## Policy rules

- `update` requires at least one VIN rule. MAC restrictions are optional.
- `emergency` ignores VIN and writes `*`; it requires at least one exact MAC.
- VIN rules cannot contain `|` because that separator is added by the signer.
- MAC values are normalized to uppercase colon notation.
- A request ID is an idempotency key. Repeating it does not create another
  package.

For a normal `update`, the source package defines the immutable technical
compatibility profile:

1. processor model,
2. memory variant,
3. measurement-module compatibility,
4. console compatibility,
5. SD compatibility,
6. RTC compatibility,
7. RES compatibility,
8. base hardware generation.

The administrator may change only the serial-number and production-date
segments of a VIN rule. The workflow derives every source technical profile
from the signed KFW header and rejects any requested VIN rule that changes a
technical segment. This server-side check is required even though the Android
editor also displays technical compatibility as read-only.

The signed VIN policy uses the same selector grammar in the Android app,
workflow and controller:

- `56` - one exact serial number,
- `56-650` - an inclusive serial range,
- `!78` - one excluded serial number,
- `!80-90` - an excluded inclusive range,
- `2607-2712` - an inclusive production-month range in `RRMM` form.

Selectors inside one VIN segment are separated with `;`. Positive selectors
are combined with OR. A matching exclusion always wins. A segment without a
positive selector means "all except exclusions". Production-date range bounds
and the device VIN must use the same `RRMM` or `RRRRMM` width.

The first controller firmware that understands ranges and exclusions is
`2.3.22`. The workflow rejects advanced selectors when repacking an older
controller payload. Version `2.3.22` itself is published with the legacy exact
VIN rule so controllers on `2.3.21` can install it first.

The package description and the operation audit note are separate values. The
description is displayed in the manifest. The audit note records why the
administrator changed the policy.

## Package deletion

`delete-firmware-package.yml` performs an explicit administrative deletion:

1. validates the exact manifest package ID,
2. removes the package entry,
3. deletes the KFW file when no other entry references it,
4. appends an audit entry to the manifest,
5. commits both changes together.

The Android app requires a GitHub administrator session, a confirmation dialog
and local device authentication. Git history remains the recovery and audit
trail even though the package disappears from the current publication.

The administrator app will trigger this workflow through a GitHub App user
token with only `Actions: write` permission.

## Administrator app

The Android administrator flow uses GitHub Device Flow. The public GitHub App
client ID is compiled into the standard application build:

```powershell
flutter build apk --release `
  --dart-define=KOMA_GITHUB_CLIENT_ID=Iv23li5Gv1vZGTitDXfT
```

The current application also uses this ID as its safe default. The
`KOMA_GITHUB_CLIENT_ID` define remains available as an explicit override for a
separate development or service GitHub App. A Client ID is public configuration,
not a signing secret.

The GitHub App must:

1. Enable Device Flow.
2. Have repository `Actions: read and write` permission.
3. Be installed only on `serwiskoma321-lgtm/srp1-updates`.

The registered application is `KOMA Firmware Admin` with slug
`koma-firmware-admin`. Webhooks are disabled. Its only repository permissions
are `Actions: read and write` and the automatically required
`Metadata: read-only`.

The phone stores the short-lived GitHub user access token and the separately
imported firmware signing key in protected Android storage. Before dispatching,
the app validates the policy, verifies the source KFW package, shows the full
change, asks Android to authenticate the local user with biometrics or the
device credential, and signs only the resulting KFW2 policy text. The private
key is never sent to GitHub.

The workflow run name includes the application-generated request ID, allowing
the phone to find and monitor exactly the run it dispatched.

## Environment protection

The workflow still uses the `firmware-signing` environment as an audit and
optional approval boundary, but it no longer needs a private-key secret. A
required reviewer may be enabled later as an additional organizational control.
It is not part of the cryptographic trust path: the workflow must always reject
an absent, malformed, or invalid administrator signature.
