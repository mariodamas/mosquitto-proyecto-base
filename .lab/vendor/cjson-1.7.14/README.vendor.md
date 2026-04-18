# Vendored dependency — cJSON 1.7.14

## Origin

| Field      | Value                                               |
|------------|-----------------------------------------------------|
| Library    | cJSON                                               |
| Version    | 1.7.14                                              |
| Upstream   | https://github.com/DaveGamble/cJSON                 |
| Tag        | v1.7.14                                             |
| Retrieved  | 2024 — git clone --depth 1 --branch v1.7.14        |

## File checksums (SHA-256)

```
a981dadfbdfc8217bfe8663a584a4cdf404306b7dcaf71158dbe7da0499275f0  cJSON.c
1037363170f189d3aeb4a14161b6d25999d89b69248b76aeb292deb2f41db3ed  cJSON.h
```

These checksums were recorded at the time of initial vendor import. Verify
with `sha256sum cJSON.c cJSON.h` after any modification.

## Known CVEs at this version

| CVE | Severity | Summary |
|-----|----------|---------|
| CVE-2023-50472 | Medium | NULL pointer dereference via crafted JSON input |
| CVE-2023-50471 | Medium | NULL pointer dereference via crafted JSON input (variant) |
| CVE-2022-24795 | High | Stack buffer overflow via deeply nested JSON |

These vulnerabilities are the reason this specific version is vendored here.
In this lab, detection is validated primarily through the Snyk unmanaged
vendored-source scan (stage 06).

## Why this dependency is vendored

This library is vendored **intentionally** as a controlled SCA / SBOM
detection target on the lab branch. It is NOT used by the upstream Mosquitto
broker build. The vendoring exercise tests whether the pipeline's SBOM and
SCA phases can identify unmanaged third-party C source, a common weakness in
embedded C/C++ projects where package managers are absent.

## What analysis phases detect this

| Phase | Expected finding |
|-------|-----------------|
| SCA — Grype (stage 05, scan 2/2) | **Primary detection path** — CVE lookup via purl in vendor manifest |
| SCA — Snyk --unmanaged (stage 06) | Fingerprinting against Snyk DB — may return 0 if cJSON not in DB (known limitation) |
| SBOM — Syft (stage 04) | Not detected — no package manifest for C/C++ source |

**Key finding from lab validation:**
Snyk `--unmanaged`, Syft, and Grype (fed the Syft SBOM) all returned 0 detections
for cJSON 1.7.14. This confirmed the canonical C/C++ SCA blind spot. The
authoritative detection path is Grype scanning the hand-curated vendor manifest
at `.lab/sca/vendor-manifest.cdx.json`. This gap is documented in
`.lab/docs/lab-decisions.md` as a pipeline-risk finding.

## Integration with the lab build

`CMakeLists.lab.txt` at the repository root defines a `cjson_vendored`
static library target that can be referenced by lab-only targets. The
upstream `CMakeLists.txt` is not modified and does not reference this file.
