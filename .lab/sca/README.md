# SCA — Software Composition Analysis

This directory contains the curated SBOM manifest and supporting artefacts for the
`mosquitto-proyecto-base` DevSecOps lab pipeline.

---

## Files

| File | Purpose |
|------|---------|
| `vendor-manifest.cdx.json` | Hand-curated CycloneDX 1.4 SBOM for vendored C/C++ dependencies |
| `vendor-manifest.evidence.md` | Human-readable evidence table (versions, paths, hashes, justifications) |
| `validate_vendor_manifest.py` | Python validation script; exits 0 on success |
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
their versions, PURLs, licenses, and file hashes, making them visible to downstream
tools such as **Grype** and **Dependency-Track**.

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
grype sbom:results/sbom/syft-sbom.cdx.json           # auto-generated
grype sbom:.lab/sca/vendor-manifest.cdx.json          # curated
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
  "ref": "cJSON",         "dependsOn": []  // standalone — fixture, not a product dep
},
{
  "ref": "libwebsockets", "dependsOn": []  // standalone — Snap-only / fixture
}
```

This prevents analysis tools from inferring that `mosquitto-proyecto-base` depends
on `cJSON` or `libwebsockets` in its standard build, while still ensuring both
components appear in the scan inventory.

---

## Component roles

Three distinct roles are used in `vendor-manifest.cdx.json`:

### `bundled-dependency`
Third-party code that is copied into the repository and compiled into every
product binary produced by the standard `make` / CMake build.

**Examples:** `uthash`, `utlist` (both in `deps/`)

### `optional-dependency`
Third-party code used only in an optional or variant build. Not part of the
default binary, but legitimately required for that variant.

**Examples:** `libwebsockets` (Snap build only, declared in `snap/snapcraft.yaml`)

### `sca-validation-fixture`
Code placed under `.lab/vendor/` specifically to act as a known-vulnerable
detection target for the SCA pipeline. This code is **never compiled into the
product**. Its presence tests whether the pipeline correctly identifies unmanaged
C/C++ dependencies and their CVEs.

**Examples:** `cJSON 1.7.14` (has published CVEs; acts as a deliberate signal)

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
python3 .lab/sca/validate_vendor_manifest.py
```

Or from within this directory:

```bash
python3 validate_vendor_manifest.py
```

The script checks:

- Valid JSON syntax
- `bomFormat == "CycloneDX"`
- `metadata.component` is present and complete
- Every component has `bom-ref`, `name`, `version`, `purl`, `properties`
- Every component has `devsecops:component-role` and `devsecops:included-in-product-build`
- No duplicate `bom-ref` values
- `dependencies` references only known `bom-ref` values

Exit code `0` = valid. Exit code `1` = validation errors found.

---

## How to scan with Grype

Scan the curated manifest directly:

```bash
grype sbom:.lab/sca/vendor-manifest.cdx.json
```

Save results to a file (JSON format, compatible with Dependency-Track):

```bash
grype sbom:.lab/sca/vendor-manifest.cdx.json \
  --output json \
  --file results/sca/grype-vendor-manifest.json
```

Expected findings (as of the manifest creation date):

| Component | Version | Expected CVEs |
|-----------|---------|--------------|
| cJSON | 1.7.14 | Yes — this version has published advisories (intentional fixture) |
| libwebsockets | 2.4.2 | Possible — old release |
| uthash / utlist | 2.1.0 | None known at time of writing |

> **Note:** The presence of CVEs for `cJSON` is intentional and expected. It
> validates that the pipeline correctly detects vulnerable vendored dependencies
> in C/C++ projects. Do not suppress or allowlist these findings without
> documenting the rationale.

---

## How to scan with jq (syntax check only)

```bash
jq empty .lab/sca/vendor-manifest.cdx.json && echo "JSON valid"
```

---

## Maintaining the manifest

Update `vendor-manifest.cdx.json` and `vendor-manifest.evidence.md` whenever:

1. A vendored dependency is upgraded or replaced in `deps/` or `.lab/vendor/`.
2. A new vendored dependency is added to the project.
3. The Snap build (`snap/snapcraft.yaml`) pins a new version of an external library.

After any update, re-run the validation script and commit both the manifest and
the evidence file together.

---

## Pipeline integration

The Jenkins pipeline (`Jenkinsfile`) scans this manifest as part of the SCA stage:

```groovy
sh 'grype sbom:.lab/sca/vendor-manifest.cdx.json --output json --file results/sca/grype-vendor-manifest.json'
```

Results are archived alongside the Syft auto-SBOM scan results. Both are uploaded
to Dependency-Track for unified vulnerability tracking.
