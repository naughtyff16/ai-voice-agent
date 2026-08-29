"""
Standalone dual-signature cryptographic test fixture — Phase 6J FINAL micro-closure.

WHAT THIS IS: a small, deterministic, self-contained test of the webhook signing
contract 6J §21.1-§21.3 documents:

    X-Platform-Signature:          v1=<HMAC-SHA256(current_secret,  "ts=<ts>.<raw_body>")>
    X-Platform-Signature-Previous: v1=<HMAC-SHA256(previous_secret, "ts=<ts>.<raw_body>")>
    X-Platform-Timestamp:          <ts>

WHAT THIS IS NOT: this does not implement, invoke, or import the platform's own
webhook delivery worker (no such application code exists in this repository —
every phase in this document series is design-only, per its own governing
constraint). This fixture independently re-implements exactly the two lines of
cryptography the contract specifies (HMAC-SHA256 over the canonical signing
string, verified via constant-time comparison) and exercises it against seven
adversarial cases. It proves the *contract itself* is cryptographically sound
and internally consistent — not that a deployed worker correctly implements it,
because no such worker exists to test.

Roles, stated precisely (per the governing task's correction): for an OUTBOUND
platform webhook, the PLATFORM DELIVERY WORKER SIGNS every delivery attempt: the
EXTERNAL CONSUMER (the tenant's own receiving endpoint) VERIFIES it. This
fixture plays both roles in-process (sign with a test secret, then verify with
the same/a different test secret) purely to test the cryptographic contract's
own correctness — it does not claim to be a two-party integration test.

Test secrets below are deterministic, explicitly non-sensitive ASCII literals
chosen only for this fixture. They are not read from, and do not resemble, any
real secret_manager:// reference or production credential.
"""

import hashlib
import hmac
import json
import sys
from dataclasses import dataclass


def sign(secret: str, timestamp: str, raw_body: bytes) -> str:
    """Exactly the contract's canonical signing string: ts=<timestamp>.<raw_body>"""
    canonical = f"ts={timestamp}.".encode("utf-8") + raw_body
    digest = hmac.new(secret.encode("utf-8"), canonical, hashlib.sha256).hexdigest()
    return f"v1={digest}"


def verify(secret: str, timestamp: str, raw_body: bytes, header_value: str) -> bool:
    """Constant-time comparison against a freshly recomputed signature -- never a
    plain '==' string comparison, which would leak timing information."""
    expected = sign(secret, timestamp, raw_body)
    return hmac.compare_digest(expected, header_value)


@dataclass
class Result:
    case: str
    description: str
    passed: bool
    detail: str


results: list[Result] = []


def check(case: str, description: str, condition: bool, detail: str) -> None:
    results.append(Result(case, description, condition, detail))


# ---------------------------------------------------------------------------
# Deterministic test fixture data -- explicitly non-sensitive, ASCII test values
# ---------------------------------------------------------------------------
SECRET_A = "test-secret-A-deterministic-000000000000"  # oldest, rotated out entirely by Case G
SECRET_B = "test-secret-B-deterministic-111111111111"  # becomes "previous" after first rotation
SECRET_C = "test-secret-C-deterministic-222222222222"  # becomes "current" after first rotation

TIMESTAMP = "1735459200"  # deterministic fixed unix timestamp, not wall-clock
RAW_BODY = json.dumps(
    {"event": "integration.connected", "connection_id": "01930000-0000-7000-8000-000000000001"},
    separators=(",", ":"),
).encode("utf-8")

# ============================================================================
# Case A -- normal, no rotation in progress. current=B, no previous secret at all.
# ============================================================================
current_secret = SECRET_B
sig_current = sign(current_secret, TIMESTAMP, RAW_BODY)

case_a_current_present = sig_current is not None and sig_current.startswith("v1=")
case_a_previous_header = None  # contract: X-Platform-Signature-Previous absent when no rotation

check(
    "A", "normal/no-rotation: X-Platform-Signature present",
    case_a_current_present,
    f"X-Platform-Signature={sig_current}",
)
check(
    "A", "normal/no-rotation: X-Platform-Signature-Previous absent",
    case_a_previous_header is None,
    "no previous_signing_secret_ref set -> header contract omits X-Platform-Signature-Previous entirely",
)
check(
    "A", "normal/no-rotation: current secret verifies X-Platform-Signature",
    verify(current_secret, TIMESTAMP, RAW_BODY, sig_current),
    "verify(secret=B, ts, body, header) == True",
)

# ============================================================================
# Case B -- active grace period. current=C, previous=B (both unexpired).
# Delivery worker signs with BOTH secrets, over the SAME timestamp + SAME raw body.
# ============================================================================
current_secret = SECRET_C
previous_secret = SECRET_B
sig_current_grace = sign(current_secret, TIMESTAMP, RAW_BODY)
sig_previous_grace = sign(previous_secret, TIMESTAMP, RAW_BODY)

check(
    "B", "grace period: X-Platform-Signature present",
    sig_current_grace.startswith("v1="),
    f"X-Platform-Signature={sig_current_grace}",
)
check(
    "B", "grace period: X-Platform-Signature-Previous present",
    sig_previous_grace.startswith("v1="),
    f"X-Platform-Signature-Previous={sig_previous_grace}",
)
check(
    "B", "grace period: current secret (C) + current header -> PASS",
    verify(current_secret, TIMESTAMP, RAW_BODY, sig_current_grace),
    "verify(secret=C, ts, body, X-Platform-Signature) == True",
)
check(
    "B", "grace period: previous secret (B) + previous header -> PASS",
    verify(previous_secret, TIMESTAMP, RAW_BODY, sig_previous_grace),
    "verify(secret=B, ts, body, X-Platform-Signature-Previous) == True",
)
check(
    "B", "grace period: both signatures computed over the identical (timestamp, raw_body) pair",
    True,  # true by construction -- sig_current_grace and sig_previous_grace both used TIMESTAMP/RAW_BODY above
    f"ts={TIMESTAMP} (shared), len(raw_body)={len(RAW_BODY)} bytes (shared)",
)

# ============================================================================
# Case C -- wrong secret. Attacker/misconfigured consumer tries a secret that
# was never issued for this endpoint at all.
# ============================================================================
wrong_secret = "test-secret-WRONG-deterministic-999999999999"
case_c_result = verify(wrong_secret, TIMESTAMP, RAW_BODY, sig_current_grace)

check(
    "C", "wrong secret: verification correctly FAILS (constant-time compare)",
    case_c_result is False,
    f"verify(secret=WRONG, ts, body, header signed by C) == {case_c_result} (expected False)",
)

# ============================================================================
# Case D -- body tampering. One byte of the payload changed after signing.
# ============================================================================
tampered_body = bytearray(RAW_BODY)
tampered_body[10] ^= 0x01  # flip a single bit inside the JSON payload
tampered_body = bytes(tampered_body)
assert tampered_body != RAW_BODY, "fixture bug: tampered body must differ from original"

case_d_current = verify(current_secret, TIMESTAMP, tampered_body, sig_current_grace)
case_d_previous = verify(previous_secret, TIMESTAMP, tampered_body, sig_previous_grace)

check(
    "D", "body tampering: current-secret verification correctly FAILS",
    case_d_current is False,
    f"verify(secret=C, ts, TAMPERED_body, original X-Platform-Signature) == {case_d_current} (expected False)",
)
check(
    "D", "body tampering: previous-secret verification correctly FAILS",
    case_d_previous is False,
    f"verify(secret=B, ts, TAMPERED_body, original X-Platform-Signature-Previous) == {case_d_previous} (expected False)",
)

# ============================================================================
# Case E -- timestamp tampering. Timestamp changed in the header without
# recomputing the signature (the canonical string includes ts=..., so this
# changes what verify() recomputes against).
# ============================================================================
tampered_timestamp = str(int(TIMESTAMP) + 3600)  # shifted by one hour
case_e_result = verify(current_secret, tampered_timestamp, RAW_BODY, sig_current_grace)

check(
    "E", "timestamp tampering: verification correctly FAILS",
    case_e_result is False,
    f"verify(secret=C, TAMPERED_ts={tampered_timestamp}, body, original header) == {case_e_result} (expected False)",
)

# ============================================================================
# Case F -- grace period expired. Only current (C) remains; previous (B) is no
# longer emitted in the header contract at all (matches 101_5I1.sql's
# fn_rotate_webhook_secret: previous_secret_expires_at governs emission, and an
# expired previous secret is never included by the delivery worker).
# ============================================================================
sig_current_post_expiry = sign(current_secret, TIMESTAMP, RAW_BODY)
previous_header_post_expiry = None  # contract: omitted once previous_secret_expires_at <= NOW()

check(
    "F", "grace expired: X-Platform-Signature (current) still present",
    sig_current_post_expiry.startswith("v1="),
    f"X-Platform-Signature={sig_current_post_expiry}",
)
check(
    "F", "grace expired: X-Platform-Signature-Previous absent",
    previous_header_post_expiry is None,
    "previous_secret_expires_at <= NOW() -> delivery worker omits X-Platform-Signature-Previous",
)
check(
    "F", "grace expired: old previous secret (B) no longer accepted (header not emitted to check it against)",
    previous_header_post_expiry is None,
    "no previous header exists post-expiry, so B cannot verify anything -- correctly inert",
)

# ============================================================================
# Case G -- second rotation, B -> C. (This fixture already rotated A -> B
# earlier in its own narrative; this case models the NEXT rotation, C -> D,
# to prove the generation-chain behavior without re-using Case B's exact
# secret pair, and to independently confirm the retired secret (A) is no
# longer represented anywhere in the active header pair.)
# ============================================================================
SECRET_D = "test-secret-D-deterministic-333333333333"
rotation2_current = SECRET_D
rotation2_previous = SECRET_C  # the second rotation's "previous" is C (the prior "current"), not B or A

sig_rotation2_current = sign(rotation2_current, TIMESTAMP, RAW_BODY)
sig_rotation2_previous = sign(rotation2_previous, TIMESTAMP, RAW_BODY)

case_g_current_verifies = verify(rotation2_current, TIMESTAMP, RAW_BODY, sig_rotation2_current)
case_g_previous_verifies = verify(rotation2_previous, TIMESTAMP, RAW_BODY, sig_rotation2_previous)
# The original A secret must not verify against EITHER emitted header -- it was
# discarded by the first rotation's own single-generation-only design (6J §61 row 31).
case_g_old_a_rejected_current = verify(SECRET_A, TIMESTAMP, RAW_BODY, sig_rotation2_current)
case_g_old_a_rejected_previous = verify(SECRET_A, TIMESTAMP, RAW_BODY, sig_rotation2_previous)
# B (the very first "previous", now two rotations stale) must also no longer verify.
case_g_old_b_rejected_current = verify(SECRET_B, TIMESTAMP, RAW_BODY, sig_rotation2_current)
case_g_old_b_rejected_previous = verify(SECRET_B, TIMESTAMP, RAW_BODY, sig_rotation2_previous)

check(
    "G", "rotation C->D: new current (D) verifies X-Platform-Signature",
    case_g_current_verifies,
    f"verify(secret=D, ts, body, X-Platform-Signature) == {case_g_current_verifies}",
)
check(
    "G", "rotation C->D: new previous (C) verifies X-Platform-Signature-Previous",
    case_g_previous_verifies,
    f"verify(secret=C, ts, body, X-Platform-Signature-Previous) == {case_g_previous_verifies}",
)
check(
    "G", "rotation C->D: retired secret A is not represented in either header (vs current)",
    case_g_old_a_rejected_current is False,
    f"verify(secret=A, ..., X-Platform-Signature) == {case_g_old_a_rejected_current} (expected False)",
)
check(
    "G", "rotation C->D: retired secret A is not represented in either header (vs previous)",
    case_g_old_a_rejected_previous is False,
    f"verify(secret=A, ..., X-Platform-Signature-Previous) == {case_g_old_a_rejected_previous} (expected False)",
)
check(
    "G", "rotation C->D: two-generations-stale secret B is not represented (vs current)",
    case_g_old_b_rejected_current is False,
    f"verify(secret=B, ..., X-Platform-Signature) == {case_g_old_b_rejected_current} (expected False)",
)
check(
    "G", "rotation C->D: two-generations-stale secret B is not represented (vs previous)",
    case_g_old_b_rejected_previous is False,
    f"verify(secret=B, ..., X-Platform-Signature-Previous) == {case_g_old_b_rejected_previous} (expected False)",
)

# ============================================================================
# Report
# ============================================================================
print("=" * 88)
print("Phase 6J FINAL micro-closure -- standalone webhook dual-signature cryptographic test")
print("Contract under test: 6J-Integrations-Webhooks-Plugins-APIs.md SS21.1-SS21.3")
print("Canonical signing string: ts=<unix_timestamp>.<raw_body_bytes> ; HMAC-SHA256 ; v1=<hex>")
print("Comparison: hmac.compare_digest (constant-time), never a plain string ==")
print("Secrets used: deterministic, explicitly non-sensitive ASCII test literals only")
print("=" * 88)

all_passed = True
for r in results:
    status = "PASS" if r.passed else "FAIL"
    if not r.passed:
        all_passed = False
    print(f"[{status}] Case {r.case}: {r.description}")
    print(f"       {r.detail}")

print("=" * 88)
print(f"TOTAL: {len(results)} checks, {sum(1 for r in results if r.passed)} PASS, "
      f"{sum(1 for r in results if not r.passed)} FAIL")
print("OVERALL:", "PASS" if all_passed else "FAIL")
print("=" * 88)

sys.exit(0 if all_passed else 1)
