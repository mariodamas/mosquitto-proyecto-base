#!/usr/bin/env python3
"""
validate_vendor_manifest.py
Validates .lab/sca/vendor-manifest.cdx.json against the project's CycloneDX
curated-manifest conventions.

Exit codes:
  0 - all checks passed
  1 - one or more validation errors found
"""

import json
import sys
import os

MANIFEST_PATH = os.path.join(
    os.path.dirname(__file__), "vendor-manifest.cdx.json"
)

REQUIRED_COMPONENT_FIELDS = ("bom-ref", "name", "version", "properties")
REQUIRED_PROPERTY_ROLE = "devsecops:component-role"
REQUIRED_PROPERTY_INCLUDED = "devsecops:included-in-product-build"
VALID_ROLES = {"bundled-dependency", "optional-dependency", "sca-validation-fixture"}
FIXTURE_ROLE = "sca-validation-fixture"
ROOT_BOM_REF = "pkg:github/mariodamas/mosquitto-proyecto-base@2.0.18"

errors = []
warnings = []


def fail(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


def section(title):
    print(f"\n{'='*60}")
    print(f"  {title}")
    print(f"{'='*60}")


# ── 1. Load and parse JSON ────────────────────────────────────────────────────

section("1. JSON syntax")
try:
    with open(MANIFEST_PATH, encoding="utf-8") as f:
        bom = json.load(f)
    print(f"  OK  Loaded {MANIFEST_PATH}")
except FileNotFoundError:
    print(f"  ERR File not found: {MANIFEST_PATH}")
    sys.exit(1)
except json.JSONDecodeError as exc:
    print(f"  ERR Invalid JSON: {exc}")
    sys.exit(1)

# ── 2. Top-level structure ────────────────────────────────────────────────────

section("2. Top-level structure")

if bom.get("bomFormat") == "CycloneDX":
    print("  OK  bomFormat = CycloneDX")
else:
    fail(f"bomFormat must be 'CycloneDX', got: {bom.get('bomFormat')!r}")
    print(f"  ERR bomFormat: {bom.get('bomFormat')!r}")

if "specVersion" in bom:
    print(f"  OK  specVersion = {bom['specVersion']}")
else:
    fail("Missing field: specVersion")
    print("  ERR Missing specVersion")

if "version" in bom:
    print(f"  OK  version = {bom['version']}")
else:
    fail("Missing field: version")
    print("  ERR Missing version")

serial = bom.get("serialNumber", "")
if serial.startswith("urn:uuid:") and len(serial) == len("urn:uuid:") + 36:
    print(f"  OK  serialNumber = {serial}")
else:
    fail(f"serialNumber must be 'urn:uuid:<uuid>', got: {serial!r}")
    print(f"  ERR serialNumber invalid: {serial!r}")

# ── 3. metadata.component ────────────────────────────────────────────────────

section("3. metadata.component")

metadata = bom.get("metadata", {})
meta_comp = metadata.get("component")
if not meta_comp:
    fail("Missing metadata.component")
    print("  ERR metadata.component is absent")
else:
    for field in ("type", "name", "version", "bom-ref"):
        if meta_comp.get(field):
            print(f"  OK  metadata.component.{field} = {meta_comp[field]!r}")
        else:
            fail(f"metadata.component.{field} is missing or empty")
            print(f"  ERR metadata.component.{field} missing")

# ── 4. components array ───────────────────────────────────────────────────────

section("4. components")

components = bom.get("components", [])
if not components:
    fail("No components declared")
    print("  ERR components array is empty")
else:
    print(f"  OK  {len(components)} component(s) declared")

bom_refs_seen = {}
fixture_bom_refs = set()

for idx, comp in enumerate(components):
    label = comp.get("name", f"components[{idx}]")
    comp_ok = True

    for field in REQUIRED_COMPONENT_FIELDS:
        if not comp.get(field):
            fail(f"Component '{label}': missing or empty field '{field}'")
            print(f"  ERR [{label}] missing field: {field}")
            comp_ok = False

    # Require purl OR cpe — at least one machine-readable identifier
    has_purl = bool(comp.get("purl"))
    has_cpe = bool(comp.get("cpe"))
    if has_purl:
        print(f"  OK  [{label}] purl = {comp['purl']}")
    if has_cpe:
        print(f"  OK  [{label}] cpe  = {comp['cpe']}")
    if not has_purl and not has_cpe:
        fail(f"Component '{label}': must have at least one of 'purl' or 'cpe'")
        print(f"  ERR [{label}] missing both purl and cpe")
        comp_ok = False

    bom_ref = comp.get("bom-ref", "")
    if bom_ref:
        if bom_ref in bom_refs_seen:
            fail(
                f"Duplicate bom-ref '{bom_ref}' in '{label}' "
                f"(also in '{bom_refs_seen[bom_ref]}')"
            )
            print(f"  ERR [{label}] duplicate bom-ref: {bom_ref!r}")
            comp_ok = False
        else:
            bom_refs_seen[bom_ref] = label

    props = comp.get("properties", [])
    prop_names = [p.get("name", "") for p in props]

    role_value = None
    has_role = any(n == REQUIRED_PROPERTY_ROLE for n in prop_names)
    if not has_role:
        fail(f"Component '{label}': missing property '{REQUIRED_PROPERTY_ROLE}'")
        print(f"  ERR [{label}] missing property: {REQUIRED_PROPERTY_ROLE}")
        comp_ok = False
    else:
        role_value = next(
            p["value"] for p in props if p.get("name") == REQUIRED_PROPERTY_ROLE
        )
        if role_value not in VALID_ROLES:
            warn(
                f"Component '{label}': property '{REQUIRED_PROPERTY_ROLE}' "
                f"has unexpected value {role_value!r}. "
                f"Expected one of: {sorted(VALID_ROLES)}"
            )
            print(f"  WARN [{label}] unexpected role value: {role_value!r}")
        else:
            print(f"  OK  [{label}] role = {role_value}")

    included_value = None
    has_included = any(n == REQUIRED_PROPERTY_INCLUDED for n in prop_names)
    if not has_included:
        fail(
            f"Component '{label}': missing property '{REQUIRED_PROPERTY_INCLUDED}'"
        )
        print(f"  ERR [{label}] missing property: {REQUIRED_PROPERTY_INCLUDED}")
        comp_ok = False
    else:
        included_value = next(
            p["value"]
            for p in props
            if p.get("name") == REQUIRED_PROPERTY_INCLUDED
        )
        if included_value not in ("true", "false"):
            fail(
                f"Component '{label}': property '{REQUIRED_PROPERTY_INCLUDED}' "
                f"must be 'true' or 'false', got {included_value!r}"
            )
            print(
                f"  ERR [{label}] {REQUIRED_PROPERTY_INCLUDED} = {included_value!r} "
                "(must be 'true' or 'false')"
            )
            comp_ok = False
        else:
            print(
                f"  OK  [{label}] included-in-product-build = {included_value}"
            )

    # Fixture-specific rule: sca-validation-fixture must not be in the product build
    if role_value == FIXTURE_ROLE:
        if included_value is not None and included_value != "false":
            fail(
                f"Component '{label}': role is '{FIXTURE_ROLE}' but "
                f"'{REQUIRED_PROPERTY_INCLUDED}' = {included_value!r} (must be 'false')"
            )
            print(
                f"  ERR [{label}] fixture must have included-in-product-build = false"
            )
            comp_ok = False
        elif included_value == "false":
            print(f"  OK  [{label}] fixture correctly excluded from product build")
        if bom_ref:
            fixture_bom_refs.add(bom_ref)

    if comp_ok:
        print(f"  OK  [{label}] all required fields present")

# ── 5. dependencies ───────────────────────────────────────────────────────────

section("5. dependencies")

all_bom_refs = set(bom_refs_seen.keys())
if meta_comp and meta_comp.get("bom-ref"):
    all_bom_refs.add(meta_comp["bom-ref"])

root_depends_on = []
dependencies = bom.get("dependencies", [])
if not dependencies:
    warn("No 'dependencies' section found — consider adding one for traceability")
    print("  WARN No dependencies section")
else:
    print(f"  OK  {len(dependencies)} dependency node(s)")
    for dep in dependencies:
        ref = dep.get("ref", "")
        if ref not in all_bom_refs:
            fail(
                f"dependencies: ref {ref!r} does not match any known bom-ref"
            )
            print(f"  ERR ref not found: {ref!r}")
        else:
            print(f"  OK  ref {ref!r} resolved")
            if ref == ROOT_BOM_REF:
                root_depends_on = dep.get("dependsOn", [])

        for depends_on_ref in dep.get("dependsOn", []):
            if depends_on_ref not in all_bom_refs:
                fail(
                    f"dependencies[{ref!r}].dependsOn: "
                    f"{depends_on_ref!r} does not match any known bom-ref"
                )
                print(f"  ERR dependsOn ref not found: {depends_on_ref!r}")
            else:
                print(f"  OK  dependsOn {depends_on_ref!r} resolved")

# ── 6. Fixture dependency integrity ──────────────────────────────────────────

section("6. Fixture dependency integrity")

if not fixture_bom_refs:
    print("  OK  No fixture components declared (nothing to check)")
else:
    print(f"  OK  {len(fixture_bom_refs)} fixture bom-ref(s) identified")
    contaminated = [r for r in root_depends_on if r in fixture_bom_refs]
    if contaminated:
        for ref in contaminated:
            fail(
                f"Root component dependsOn includes SCA fixture {ref!r}. "
                "Fixtures must not appear as product dependencies."
            )
            print(f"  ERR root component incorrectly depends on fixture: {ref!r}")
    else:
        print(
            "  OK  Root component dependsOn does not include any fixture bom-ref"
        )

# ── Summary ───────────────────────────────────────────────────────────────────

section("SUMMARY")

print(f"  Components declared : {len(components)}")
print(f"  Fixture components  : {len(fixture_bom_refs)}")
print(f"  Errors              : {len(errors)}")
print(f"  Warnings            : {len(warnings)}")

if warnings:
    print("\nWarnings:")
    for w in warnings:
        print(f"  WARN  {w}")

if errors:
    print("\nErrors:")
    for e in errors:
        print(f"  ERR   {e}")
    print("\nResult: FAILED")
    sys.exit(1)

print("\nResult: PASSED — manifest is valid")
sys.exit(0)
