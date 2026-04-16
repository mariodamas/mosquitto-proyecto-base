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

These vulnerabilities are the reason this specific version is vendored here:
they are well-documented in NVD and any SCA tool with an up-to-date database
must detect them against this file content.

## Why this dependency is vendored

This library is vendored **intentionally** as a controlled SCA / SBOM
detection target on the lab branch. It is NOT used by the upstream Mosquitto
broker build. The vendoring exercise tests whether the pipeline's SBOM and
SCA phases can identify unmanaged third-party C source, a common weakness in
embedded C/C++ projects where package managers are absent.

## What analysis phases should detect this

| Phase | Expected finding |
|-------|-----------------|
| SBOM (Syft / cdxgen) | Component `cjson@1.7.14` should appear in the generated SBOM |
| SCA (Grype / OWASP Dependency-Check) | CVE-2023-50472, CVE-2023-50471, CVE-2022-24795 flagged |
| SAST (semgrep / cppcheck) | NULL-check and buffer-size findings in cJSON.c |

A SBOM run that does NOT list `cjson@1.7.14` has failed to detect the
vendored dependency and should be investigated as a false-negative.

## Integration with the lab build

`CMakeLists.lab.txt` at the repository root defines a `cjson_vendored`
static library target that can be referenced by lab-only targets. The
upstream `CMakeLists.txt` is not modified and does not reference this file.
