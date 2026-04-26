# SCA Vendor Manifest — Component Evidence

> **Document:** `.lab/sca/vendor-manifest.evidence.md`
> **Manifest:** `.lab/sca/vendor-manifest.cdx.json`
> **Project:** `mosquitto-proyecto-base` (Eclipse Mosquitto 2.0.18 DevSecOps lab fork)
> **Last updated:** 2026-04-26
> **Reviewed by:** mariodamas

This file provides the human-readable evidence trail for every component declared in
`vendor-manifest.cdx.json`. It exists because automated SBOM tools (Syft, Snyk
`--unmanaged`) cannot reliably detect header-only C/C++ dependencies or dependencies
disclosed only in build manifests such as `snap/snapcraft.yaml`.

---

## Component Evidence Table

| Component | Version | PURL | CPE | Role | Included in product build | Purpose | Empirical Grype result | Notes |
|-----------|---------|------|-----|------|--------------------------|---------|----------------------|-------|
| uthash | 2.1.0 | `pkg:github/troydhanson/uthash@v2.1.0#uthash.h` | — | bundled-dependency | **true** | Hash table macros for C structures. Used throughout the Mosquitto broker for client/subscription/topic tracking. Compiled into every binary produced by the standard `make` / CMake build. | No CVEs expected or observed. | Version confirmed from copyright header in `deps/uthash.h` (`Copyright (c) 2003-2018`). |
| utlist | 2.1.0 | `pkg:github/troydhanson/uthash@v2.1.0#utlist.h` | — | bundled-dependency | **true** | Linked list macros for C. Part of the uthash distribution; co-vendored in `deps/utlist.h`. Used for session and message list management in Mosquitto. Compiled into every binary produced by the standard build. | No CVEs expected or observed. | Co-distributed with uthash at tag v2.1.0. Copyright header `2007-2018`. |
| cJSON | 1.7.14 | `pkg:github/DaveGamble/cJSON@v1.7.14` | `cpe:2.3:a:cjson_project:cjson:1.7.14:*:*:*:*:*:*:*` | sca-validation-fixture | **false** | Intentionally vendored known-vulnerable version to serve as a controlled SCA detection target. Acts as a pipeline validation signal. NOT compiled into the product binary. | PURL-only scan: **0 matches**. CPE scan: **CVE-2023-53154 detected**. CPE is mandatory for Grype to correlate this component. | Physical files present in `.lab/vendor/cjson-1.7.14/`. Vulnerabilities must NOT be attributed to the Mosquitto binary. |
| libwebsockets | 2.4.2 | `pkg:github/warmcat/libwebsockets@v2.4.2` | — | optional-dependency | **false** | WebSockets transport for Mosquitto Snap build. Retained as an optional build reference. Local fixture is a header stub only. NOT a CVE detection fixture. | **No matches** found for tested PURL/CPE/version combinations with local Grype DB v6.1.4. | Version from `snap/snapcraft.yaml`. Not a reliable SCA fixture with current local DB. |
| zlib | 1.2.11 | `pkg:generic/zlib@1.2.11` | `cpe:2.3:a:zlib:zlib:1.2.11:*:*:*:*:*:*:*` | sca-validation-fixture | **false** | Controlled SCA detection fixture selected empirically to validate end-to-end pipeline vulnerability detection. No physical files vendored — SBOM-only fixture. NOT compiled into the Mosquitto binary. | Positive-control test: **~3 vulnerability matches** observed with Grype 0.111.0 / DB v6.1.4. | Selected via empirical positive-control testing. Vulnerabilities must NOT be attributed to the Mosquitto runtime binary. License: `Zlib` (SPDX). |
| sqlite | 3.39.1 | `pkg:generic/sqlite@3.39.1` | `cpe:2.3:a:sqlite:sqlite:3.39.1:*:*:*:*:*:*:*` | sca-validation-fixture | **false** | Controlled SCA detection fixture selected empirically to validate end-to-end pipeline vulnerability detection. No physical files vendored — SBOM-only fixture. NOT compiled into the Mosquitto binary. | Positive-control test: **~14 vulnerability matches** observed with Grype 0.111.0 / DB v6.1.4. | Selected via empirical positive-control testing. License is public domain ("blessing"); `devsecops:license-review-required=true` set. Vulnerabilities must NOT be attributed to the Mosquitto runtime binary. |

---

## Critical note on SCA fixture interpretation

Findings reported by Grype against `cJSON`, `zlib`, or `sqlite` in this manifest
are **pipeline validation signals**, not vulnerabilities in the Mosquitto product:

- `uthash` and `utlist` are the **only** components compiled into the Mosquitto binary.
- All components with `devsecops:included-in-product-build = false` must not be
  attributed to the Mosquitto runtime artifact.
- The `dependencies` graph enforces this: only `uthash` and `utlist` appear in
  `mosquitto-proyecto-base`'s `dependsOn` list. `cJSON`, `libwebsockets`, `zlib`,
  and `sqlite` are standalone nodes with `dependsOn: []`.

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
> **Note for `libwebsockets`:** The hash covers
> `.lab/vendor/libwebsockets-2.4.2/include/libwebsockets.h` only (a local header
> stub). It does **not** represent the integrity of the full upstream source archive.
>
> **Note for `zlib` and `sqlite`:** These are SBOM-only fixtures. No physical files
> are vendored in the repository; no file hashes are provided.

---

## Component Roles — Definitions

| Role | Meaning |
|------|---------|
| `bundled-dependency` | Third-party code vendored directly into the upstream source tree and compiled into the product binary. |
| `optional-dependency` | Third-party code used only in an optional or variant build (e.g., Snap package). Not part of the default product binary. |
| `sca-validation-fixture` | Code or SBOM entry placed deliberately to provide a known-vulnerable signal for validating SCA/SBOM pipeline detection. Not compiled into the product. |

---

## Assumptions and Limitations

1. **uthash / utlist versions** were inferred from copyright headers because the
   upstream Mosquitto repository does not maintain a `deps/` changelog. The v2.1.0
   tag is confirmed by cross-referencing the header date range (`2003-2018` /
   `2007-2018`) with the upstream release timeline.

2. **cJSON 1.7.14** version is confirmed via the vendor directory name and the
   presence of `cJSON.h` / `cJSON.c` matching the upstream release archive.
   **CPE is required** for Grype to produce matches; the GitHub PURL alone yields
   0 results with Grype 0.111.0 / DB v6.1.4.

3. **libwebsockets 2.4.2** version is taken exclusively from `snap/snapcraft.yaml`.
   Empirical testing showed no CVE matches for any tested PURL/CPE/version
   combination with the local Grype DB v6.1.4. This component is retained as a
   build reference only and must not be relied upon as a CVE detection fixture.

4. **zlib 1.2.11** and **sqlite 3.39.1** are SBOM-only fixtures (no physical files
   vendored). They were selected via empirical positive-control testing with
   Grype 0.111.0 and DB v6.1.4. Expected match counts (3 and 14 respectively)
   reflect the DB state at the time of testing and may differ in future DB versions.

5. **No tarball hashes** are provided for `cJSON` or `libwebsockets` because no
   complete upstream tarballs are present in the repository. Individual file hashes
   are provided instead.

6. **Vulnerability data is intentionally absent** from this manifest. Grype or
   Dependency-Track is responsible for enriching the SBOM with vulnerability
   information at scan time.

7. **Air-gapped environments** must set `GRYPE_DB_MAX_ALLOWED_BUILT_AGE=720h` to
   prevent Grype from refusing a local DB that is more than 5 days old.
