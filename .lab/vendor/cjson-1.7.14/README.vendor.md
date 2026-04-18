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

## What analysis phases should detect this

| Phase | Expected finding in this lab |
|-------|------------------------------|
| SCA (Snyk unmanaged, stage 06) | Primary/authoritative detection path for vendored cJSON and related CVEs |
| SBOM (Syft, stage 04) | May not include `cjson@1.7.14` in the current repository-wide source scan |
| SCA (Grype, stage 05) | Depends on SBOM contents; if cJSON is absent from SBOM, Grype can report 0 matches |
| SAST (semgrep / cppcheck) | May show generic code issues, but not CVE attribution for vendored fingerprinting |

So, for this branch and pipeline design, the expected CVE signal for vendored
cJSON should be evaluated from Snyk unmanaged results.

## Integration with the lab build

`CMakeLists.lab.txt` at the repository root defines a `cjson_vendored`
static library target that can be referenced by lab-only targets. The
upstream `CMakeLists.txt` is not modified and does not reference this file.
