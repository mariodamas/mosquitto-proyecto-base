# Synthetic secrets — detection lab

**Nothing in this directory is a real credential.** Every secret-shaped string
here is a fabricated value that matches the lexical pattern expected by
secret-scanning tools (Gitleaks, detect-secrets, truffleHog). They exist as
controlled detection targets for the pipeline's secret-scanning phase.

## Why synthetic secrets?

A scanner that misses a synthetic secret it should find has a demonstrated
false-negative. A scanner that only runs against a repository with no
secrets tells you nothing about its detection efficacy. Having plausible,
realistic-looking secrets in the lab branch makes the detection signal
measurable and repeatable.

The secrets are formatted to look *plausible in context* — not like random
character strings — because real scanner bypasses almost always exploit the
gap between "looks like a secret" and "looks like a secret in a real config
file". Realistic placement tests whether the scanner is fooled by context.

## Planted secrets and their detection targets

### `broker_tls_example.conf`

| Secret | Type | Pattern Gitleaks looks for |
|--------|------|----------------------------|
| `AKIAIOSFODNN7EXAMPLE` | AWS Access Key ID | `/AKIA[0-9A-Z]{16}/` |
| `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` | AWS Secret Access Key | 40-char base64 near `secret` keyword |
| `Sup3rSecret!AdminPass2023` | Hardcoded password | keyword proximity (`admin_password =`) |
| `S3cret-Bridge-P@ss` | Hardcoded password | `remote_password` keyword proximity |
| RSA PRIVATE KEY block | Private key | `-----BEGIN RSA PRIVATE KEY-----` header |

The AWS pair (`AKIAIOSFODNN7EXAMPLE` / `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`)
are the official AWS documentation example values. They appear in Gitleaks
rule test suites and must be detected by any correctly configured scanner.

### `admin_helper.py`

| Variable | Type | Pattern |
|----------|------|---------|
| `GITHUB_PAT` | GitHub Personal Access Token | `/ghp_[A-Za-z0-9]{36}/` |
| `ADMIN_BEARER_JWT` | JWT bearer token | Three base64url segments separated by `.` |
| `DD-API-KEY` | Datadog API key | `/dd_api_[a-f0-9]{32}/` or generic high-entropy |

The GitHub PAT (`ghp_ABCDEFabcdef0123456789abcdef0123456789`) matches the
`ghp_` prefix introduced by GitHub in 2021. Any scanner with an up-to-date
ruleset must detect it.

The JWT matches the three-part base64url pattern with a recognisable
`{"alg":"HS256","typ":"JWT"}` header.

## Verification command

After the pipeline's secret-scanning step runs, verify the results with:

```sh
gitleaks detect --source .lab/secrets/ --verbose
```

A clean (`no leaks found`) result from Gitleaks against this directory is a
**tool misconfiguration**, not a clean bill of health.

Expected minimum findings:

- `AKIAIOSFODNN7EXAMPLE`
- `ghp_ABCDEFabcdef0123456789abcdef0123456789`
- `-----BEGIN RSA PRIVATE KEY-----`

## Scope

These secrets are present **only on `exp/mosquitto-v2.0.18-lab`**. They are
absent from `exp/mosquitto-v2.0.18-upstream`. A scanner run against both
branches must produce different finding counts; equal counts indicate the
scanner is not reading the lab additions or is wholly misconfigured.
