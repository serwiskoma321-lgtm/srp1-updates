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
