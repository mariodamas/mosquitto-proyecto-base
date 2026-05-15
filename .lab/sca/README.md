# SCA — Software Composition Analysis

This directory contains the curated SBOM manifest and supporting artefacts for the
`mosquitto-proyecto-base` DevSecOps lab pipeline.

---

## Files

| File | Purpose |
|------|---------|
| `manual-manifest.cdx.json` | Hand-curated CycloneDX 1.4 SBOM for vendored C/C++ dependencies |
| `manual-manifest.evidence.md` | Human-readable evidence table (versions, paths, hashes, justifications) |
| `validate_manual_manifest.py` | Python validation script; exits 0 on success |
| `README.md` | This document |

---

## Why a curated manifest is needed in C/C++ projects

Automated SBOM generators such as **Syft** work well for package-manager-managed
ecosystems (npm, pip, cargo, Maven). In C/C++ projects, third-party code is
frequently vendored directly into the source tree as header files or source files,
without any package manifest that tools can parse.

Mosquitto 2.0.18 is a typical example:

- **uthash / utlist** (`deps/*.h`) — header-only libraries, no `CMakeLists.txt`
  or `package.json`. Syft cannot identify them by scanning the source tree.
- **cJSON 1.7.14** (`.lab/vendor/`) — two raw `.c`/`.h` files; no version
  metadata visible to automated scanners.
- **libwebsockets 2.4.2** — declared only in `snap/snapcraft.yaml`; never present
  as a compiled artefact in the default build.

The curated manifest closes this gap by explicitly declaring these components with
their versions, PURLs, CPEs, licenses, and file hashes, making them visible to
downstream tools such as **Grype** and **Dependency-Track**.

---

## Automated SBOM (Syft) vs. curated manifest

| Aspect | Syft auto-SBOM | Curated manifest |
|--------|---------------|-----------------|
| Coverage | Package-managed deps (OS packages, known lockfiles) | Vendored / header-only / build-manifest-only deps |
| Version accuracy | High for packages | High when based on source inspection + hashes |
| Human effort | None | Required per component |
| Vulnerability detection | Yes (via Grype) | Yes (via Grype) |
| Traceability | Limited | Full: path, hash, role, detection method |
| Stale-data risk | Low | Must be updated when vendored deps change |

Both artefacts are complementary. The pipeline scans both:

```
grype sbom:results/sca/sbom-source.cyclonedx.json      # auto-generated
grype sbom:.lab/sca/manual-manifest.cdx.json            # curated
```

Results are merged in Dependency-Track for a unified view.

### `dependencies` graph design

The manifest's `dependencies` section distinguishes real product dependencies from
inventory-only fixtures:

```json
{
  "ref": "mosquitto-proyecto-base",
  "dependsOn": ["uthash", "utlist"]   // compiled into the product binary
},
{
  "ref": "cJSON",         "dependsOn": []  // standalone — SCA fixture, not a product dep
},
{
  "ref": "libwebsockets", "dependsOn": []  // standalone — Snap-only / fixture
},
{
  "ref": "zlib",          "dependsOn": []  // standalone — SCA fixture, not a product dep
},
{
  "ref": "sqlite",        "dependsOn": []  // standalone — SCA fixture, not a product dep
}
```

This prevents analysis tools from inferring that `mosquitto-proyecto-base` depends
on `cJSON`, `libwebsockets`, `zlib`, or `sqlite` in its standard build, while still
ensuring all components appear in the scan inventory.

---

## Component roles

Three distinct roles are used in `manual-manifest.cdx.json`:

### `bundled-dependency`
Third-party code that is copied into the repository and compiled into every
product binary produced by the standard `make` / CMake build.

**Examples:** `uthash`, `utlist` (both in `deps/`)

### `optional-dependency`
Third-party code used only in an optional or variant build. Not part of the
default binary, but legitimately required for that variant.

**Examples:** `libwebsockets` (Snap build only, declared in `snap/snapcraft.yaml`)

### `sca-validation-fixture`
Code or SBOM entries placed deliberately to act as known-vulnerable detection
targets for the SCA pipeline. This code is **never compiled into the product**.
Its presence tests whether the pipeline correctly identifies unmanaged
C/C++ dependencies and their CVEs.

**Examples:** `cJSON 1.7.14`, `zlib 1.2.11`, `sqlite 3.39.1`

---

## Scope field mapping

| CycloneDX `scope` | Used for |
|-------------------|---------|
| `required` | bundled-dependency (always compiled in) |
| `optional` | optional-dependency (Snap / conditional build) **and** sca-validation-fixture |

> **Why `optional` for `sca-validation-fixture` instead of `excluded`?**
> Some scanners (including Grype) skip components with `scope: excluded`. Using
> `optional` ensures the fixture is always scanned. The true nature of the component
> is conveyed by `devsecops:component-role` and `devsecops:included-in-product-build`,
> not by the scope field alone.

---

## How to validate the manifest

Run the Python validation script from the repository root:

```bash
python3 .lab/sca/validate_manual_manifest.py
```

Or from within this directory:

```bash
python3 validate_manual_manifest.py
```

The script checks:

- Valid JSON syntax
- `bomFormat == "CycloneDX"`
- `metadata.component` is present and complete
- Every component has `bom-ref`, `name`, `version`, `properties`
- Every component has at least one of `purl` or `cpe`
- Every component has `devsecops:component-role` and `devsecops:included-in-product-build`
- Every `sca-validation-fixture` component has `included-in-product-build = false`
- No duplicate `bom-ref` values
- `dependencies` references only known `bom-ref` values
- The root component's `dependsOn` does not include any fixture `bom-ref`

Exit code `0` = valid. Exit code `1` = validation errors found.

---

## How to scan with Grype

Scan the curated manifest directly:

```bash
grype sbom:.lab/sca/manual-manifest.cdx.json
```

Save results to a file (JSON format, compatible with Dependency-Track):

```bash
grype sbom:.lab/sca/manual-manifest.cdx.json \
  --output json \
  --file results/sca/grype-manual-manifest.json
```

In air-gapped environments with an offline DB, set:

```bash
export GRYPE_DB_MAX_ALLOWED_BUILT_AGE=720h
```

Expected findings (as of the manifest creation date):

| Component | Version | Expected CVEs |
|-----------|---------|--------------|
| cJSON | 1.7.14 | Yes — CVE-2023-53154 via CPE `cjson_project:cjson`; PURL-only yields 0 results |
| libwebsockets | 2.4.2 | None — no matches found with tested PURL/CPE/version combinations in the local Grype DB |
| uthash / utlist | 2.1.0 | None known at time of writing |
| zlib | 1.2.11 | Yes — ~3 matches observed in empirical positive-control test |
| sqlite | 3.39.1 | Yes — ~14 matches observed in empirical positive-control test |

> **Note:** CVEs reported against `cJSON`, `zlib`, or `sqlite` are expected and
> intentional — they validate pipeline detection capability. These components are
> **not compiled into the Mosquitto binary** and their findings must not be
> attributed to the Mosquitto runtime artifact. See `devsecops:fixture-limitation`
> on each fixture component.

---

## Empirical Grype findings

These results were obtained with **Grype 0.111.0**, **Syft 1.42.4**, and Grype
vulnerability DB **v6.1.4** in an air-gapped environment.
`GRYPE_DB_MAX_ALLOWED_BUILT_AGE=720h` was required to prevent the stale-DB error
that occurs when the local DB is older than 5 days.

### cJSON 1.7.14

| Identifier | Result |
|-----------|--------|
| PURL `pkg:github/DaveGamble/cJSON@v1.7.14` | **0 matches** — Grype does not correlate GitHub PURLs against NVD/OSV data for this component |
| CPE `cpe:2.3:a:cjson_project:cjson:1.7.14:*:*:*:*:*:*:*` | **CVE-2023-53154 detected** |

**Conclusion:** `cJSON` requires a CPE to produce findings. The manifest includes
`"cpe": "cpe:2.3:a:cjson_project:cjson:1.7.14:*:*:*:*:*:*:*"` alongside the PURL
to ensure Grype can correlate the component.

### libwebsockets 2.4.2

No vulnerability matches were found for any tested PURL/CPE/version combination
against the local Grype DB v6.1.4. This component is retained in the manifest as
an `optional-dependency` (Snap build reference) but must **not** be relied upon as
a CVE detection fixture with the current DB.

### zlib 1.2.11 and sqlite 3.39.1

Both components were verified as positive controls before being added as fixtures:

| Component | Version | Observed matches (Grype 0.111.0 / DB v6.1.4) |
|-----------|---------|----------------------------------------------|
| zlib | 1.2.11 | ~3 vulnerability matches |
| sqlite | 3.39.1 | ~14 vulnerability matches |

These are declared as `sca-validation-fixture` components to demonstrate end-to-end
SCA detection without modifying the Mosquitto build or vendoring physical files.
They are SBOM-only fixtures — no source files are present in the repository.

### Air-gapped DB configuration

```bash
export GRYPE_DB_MAX_ALLOWED_BUILT_AGE=720h
grype sbom:.lab/sca/manual-manifest.cdx.json \
  --output json \
  --file results/sca/grype-manual-manifest.json
```

Set `GRYPE_DB_MAX_ALLOWED_BUILT_AGE` to a sufficiently large value (e.g., `720h`
= 30 days) when the vulnerability DB was pre-populated and cannot be updated from
the network. The pipeline sets this variable in the SCA stage environment.

---

## How to scan with jq (syntax check only)

```bash
jq empty .lab/sca/manual-manifest.cdx.json && echo "JSON valid"
```

If `jq` is not available, use Python:

```bash
python3 -c "import json,sys; json.load(open('.lab/sca/manual-manifest.cdx.json')); print('JSON valid')"
```

---

## Maintaining the manifest

Update `manual-manifest.cdx.json` and `manual-manifest.evidence.md` whenever:

1. A vendored dependency is upgraded or replaced in `deps/` or `.lab/vendor/`.
2. A new vendored dependency is added to the project.
3. The Snap build (`snap/snapcraft.yaml`) pins a new version of an external library.
4. A new SCA validation fixture is added or removed.

After any update, re-run the validation script and commit both the manifest and
the evidence file together.

---

## Pipeline integration

The Jenkins pipeline (`Jenkinsfile`) scans this manifest as part of the SCA stage.
It first validates the manifest, then runs Grype against it:

```groovy
sh 'python3 .lab/sca/validate_manual_manifest.py'
sh 'grype sbom:.lab/sca/manual-manifest.cdx.json --output json --file results/sca/grype-manual-manifest.json'
```

Results are archived alongside the Syft auto-SBOM scan results. Both are uploaded
to Dependency-Track for unified vulnerability tracking.
