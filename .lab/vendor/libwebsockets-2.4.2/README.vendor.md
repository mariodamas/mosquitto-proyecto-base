# Vendored dependency — libwebsockets 2.4.2

## Origin

| Field      | Value                                                               |
|------------|---------------------------------------------------------------------|
| Library    | libwebsockets                                                       |
| Version    | 2.4.2                                                               |
| Upstream   | https://github.com/warmcat/libwebsockets                            |
| Tag        | v2.4.2                                                              |
| Tarball    | https://github.com/warmcat/libwebsockets/archive/v2.4.2.tar.gz     |
| Retrieved  | Referenced in snap/snapcraft.yaml — upstream snap build uses this exact version |

## Lab contents

This directory contains representative source files with the correct version
markers for lab identification purposes:

- `include/libwebsockets.h` — public header with `LWS_LIBRARY_VERSION "2.4.2"` define
- `CMakeLists.txt` — build configuration with version strings

For Snyk `--unmanaged` fingerprinting to work, the full source tarball should
be extracted here. Obtain it from:
```
wget https://github.com/warmcat/libwebsockets/archive/v2.4.2.tar.gz
tar -xzf v2.4.2.tar.gz --strip-components=1 -C .lab/vendor/libwebsockets-2.4.2/
```

## Known CVE exposure at this version

libwebsockets 2.4.2 (released 2018) predates several security fixes applied
in later releases. Grype should identify applicable CVEs via the purl
`pkg:github/warmcat/libwebsockets@v2.4.2` in the vendor manifest.

## Why this dependency is vendored

libwebsockets 2.4.2 is the version pinned in Mosquitto's `snap/snapcraft.yaml`
for the Snap package build. It is referenced explicitly:

```yaml
lws:
  plugin: cmake
  source: https://github.com/warmcat/libwebsockets/archive/v2.4.2.tar.gz
  source-type: tar
```

This makes it a real (not synthetic) vendored dependency of the Mosquitto
ecosystem. It is included here as a second SCA detection target alongside
cJSON 1.7.14 to provide a more realistic and multi-component SCA signal.

## What analysis phases detect this

| Phase | Expected result |
|-------|----------------|
| SCA — Grype (stage 05, scan 2/2) | CVE matches via vendor manifest purl |
| SCA — Snyk --unmanaged (stage 06) | May not detect without full source in Snyk's fingerprint DB |
| SBOM — Syft (stage 04) | Not detected — no package manifest present |

## Integration with the lab build

This directory is **not** compiled into the lab build. It exists purely as an
SCA detection target to validate pipeline coverage of embedded C/C++ vendored
dependencies.
