# SCA Vendor Manifest — Component Evidence

> **Document:** `.lab/sca/vendor-manifest.evidence.md`
> **Manifest:** `.lab/sca/vendor-manifest.cdx.json`
> **Project:** `mosquitto-proyecto-base` (Eclipse Mosquitto 2.0.18 DevSecOps lab fork)
> **Last updated:** 2026-04-25
> **Reviewed by:** mariodamas

This file provides the human-readable evidence trail for every component declared in
`vendor-manifest.cdx.json`. It exists because automated SBOM tools (Syft, Snyk
`--unmanaged`) cannot reliably detect header-only C/C++ dependencies or
dependencies disclosed only in build manifests such as `snap/snapcraft.yaml`.

---

## Component Evidence Table

| Component | Version | Path | PURL | Role | Included in product build | Detection method | Source of version | Purpose / Justification |
|-----------|---------|------|------|------|--------------------------|-----------------|-------------------|-------------------------|
| uthash | 2.1.0 | `deps/uthash.h` | `pkg:github/troydhanson/uthash@v2.1.0#uthash.h` | bundled-dependency | **true** | manual-inspection:source-tree | Copyright header in `deps/uthash.h` (`Copyright (c) 2003-2018, Troy D. Hanson`) — version confirmed against upstream tag v2.1.0 | Hash table macros for C structures. Used throughout the Mosquitto broker and library for client/subscription/topic tracking. Compiled into every binary produced by the standard `make` / CMake build. |
| utlist | 2.1.0 | `deps/utlist.h` | `pkg:github/troydhanson/uthash@v2.1.0#utlist.h` | bundled-dependency | **true** | manual-inspection:source-tree | Copyright header in `deps/utlist.h` (`Copyright (c) 2007-2018, Troy D. Hanson`) — co-distributed with uthash at the same tag | Linked list macros for C. Part of the uthash distribution; co-vendored in `deps/utlist.h`. Used for session and message list management in Mosquitto. Compiled into every binary produced by the standard build. |
| cJSON | 1.7.14 | `.lab/vendor/cjson-1.7.14/` | `pkg:github/DaveGamble/cJSON@v1.7.14` | sca-validation-fixture | **false** | manual-inspection:lab-vendor-directory | Directory name `.lab/vendor/cjson-1.7.14/` matches upstream release tag; confirmed against `https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.14.tar.gz` | Intentionally vendored known-vulnerable version (has published CVEs). Acts as a controlled SCA detection target to validate that the pipeline correctly identifies unmanaged C/C++ dependencies and their associated advisories. NOT compiled into the product binary. |
| libwebsockets | 2.4.2 | `.lab/vendor/libwebsockets-2.4.2/` | `pkg:github/warmcat/libwebsockets@v2.4.2` | optional-dependency | **false** | manual-inspection:snap-snapcraft-yaml | `snap/snapcraft.yaml` source URL `https://github.com/warmcat/libwebsockets/archive/v2.4.2.tar.gz` pins this exact version for the Snap build | WebSockets transport for Mosquitto Snap build. **Local fixture is a header stub only** (`include/libwebsockets.h`), not the full upstream source tree. Present to enable SCA scanning without running a full Snap build. NOT included in standard CMake/Makefile binary. The SHA-256 hash verifies the integrity of the local stub, not of the upstream source archive. |

---

## File Hashes (SHA-256, calculated 2026-04-25)

Hashes were computed with `sha256sum` directly on the vendored files present in the
repository. They allow downstream consumers to verify that the files have not been
modified since this manifest was curated.

| File | SHA-256 |
|------|---------|
| `deps/uthash.h` | `f0caac1577592c9276fc798eb8b6760209b2e6748a98195771ebfd902360e513` |
| `deps/utlist.h` | `60f6b6d30d6231ce8f93030f5701f1b0d83edbac9d0b6f5b646e575b74467bdd` |
| `.lab/vendor/cjson-1.7.14/cJSON.h` | `1037363170f189d3aeb4a14161b6d25999d89b69248b76aeb292deb2f41db3ed` |
| `.lab/vendor/cjson-1.7.14/cJSON.c` | `a981dadfbdfc8217bfe8663a584a4cdf404306b7dcaf71158dbe7da0499275f0` |
| `.lab/vendor/libwebsockets-2.4.2/include/libwebsockets.h` | `e85eef402218b69baca36b0c7f9312e26eba207c9986bdcd25451c27e1a09b12` |

> **Note for `cJSON`:** Does not have a hash in the top-level `hashes` array because
> there are two files, not a single distributable artifact. Individual file hashes are
> stored in `devsecops:file-hash:*` properties instead.
>
> **Note for `libwebsockets`:** The hash in the `hashes` array covers
> `.lab/vendor/libwebsockets-2.4.2/include/libwebsockets.h` only (a local header
> stub). It does **not** represent the integrity of the full upstream source archive.
> See `devsecops:fixture-limitation` in the manifest for the explicit caveat.

---

## Component Roles — Definitions

| Role | Meaning |
|------|---------|
| `bundled-dependency` | Third-party code vendored directly into the upstream source tree and compiled into the product binary. |
| `optional-dependency` | Third-party code used only in an optional or variant build (e.g., Snap package). Not part of the default product binary. |
| `sca-validation-fixture` | Code placed in `.lab/vendor/` deliberately to provide a known-vulnerable signal for validating SCA/SBOM pipeline detection. Not compiled into the product. |

---

## Assumptions and Limitations

1. **uthash / utlist versions** were inferred from copyright headers because the
   upstream Mosquitto repository does not maintain a `deps/` changelog. The v2.1.0
   tag is confirmed by cross-referencing the header date range (`2003-2018` /
   `2007-2018`) with the upstream release timeline.

2. **cJSON 1.7.14** version is confirmed via the vendor directory name and the
   presence of `cJSON.h` / `cJSON.c` matching the upstream release archive.

3. **libwebsockets 2.4.2** version is taken exclusively from `snap/snapcraft.yaml`.
   The actual Snap build is not executed as part of the standard CI pipeline on
   this branch.

4. **No tarball hashes** are provided for `cJSON` or `libwebsockets` because no
   complete upstream tarballs are present in the repository. Individual file hashes
   are provided instead.

5. **Vulnerability data is intentionally absent** from this manifest. Grype or
   Dependency-Track is responsible for enriching the SBOM with vulnerability
   information at scan time.
