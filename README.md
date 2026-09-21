# icinga-check-canon-rui-ink

[![CI](https://github.com/DanielVd/icinga-check-canon-rui-ink/actions/workflows/ci.yml/badge.svg)](https://github.com/DanielVd/icinga-check-canon-rui-ink/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/DanielVd/icinga-check-canon-rui-ink)](https://github.com/DanielVd/icinga-check-canon-rui-ink/releases/latest)
![Bash](https://img.shields.io/badge/bash-4.3%2B-blue)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A Bash Nagios/Icinga plugin for monitoring Canon printer ink levels through the device's Remote UI (RUI). The observed TS3100-series authentication flow uses <code>sendpw.cgi</code>, a session token (<code>SBID</code>), and <code>prninfo_data.cgi</code>. Other Canon models or firmware may expose different endpoints or payload formats.

**Release:** [v1.2.0](https://github.com/DanielVd/icinga-check-canon-rui-ink/releases/tag/v1.2.0). Source releases are published on GitHub; this is a standalone shell script, not a Python package. See [CHANGELOG.md](CHANGELOG.md) for history and [RELEASE_NOTES.md](RELEASE_NOTES.md) for this release's scope.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Quick start](#quick-start)
- [Icinga and Nagios output](#icinga-and-nagios-output)
- [Validation and CI](#validation-and-ci)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Compatibility](#compatibility)

## Requirements

- Linux with Bash 4.3 or later, curl, grep, sed, head and mktemp.
- Network access to the printer's Canon Remote UI.
- A valid RUI credential in the <code>NAMAE</code> format expected by the printer. Treat this value as a password-equivalent secret.
- A trusted TLS certificate for HTTPS, or an explicitly configured exception for printers with self-signed certificates.

The plugin itself does **not** require Python. Python 3 is used only to run the offline test suite.

## Installation

To install the tagged source release:

~~~bash
git clone --branch v1.2.0 --depth 1 https://github.com/DanielVd/icinga-check-canon-rui-ink.git
cd icinga-check-canon-rui-ink
install -m 0755 check_canon_rui_ink.sh /usr/lib/nagios/plugins/check_canon_rui_ink.sh
~~~

The installation path is an example; use your distribution's or Icinga deployment's plugin directory. To review unreleased changes, inspect <code>main</code> rather than assuming that it matches the tagged release.

## Configuration

Configure the plugin with environment variables:

| Variable | Required | Default | Meaning |
| --- | --- | --- | --- |
| <code>BASE</code> | Yes | None | Printer Remote UI origin, for example <code>https://printer.example.local</code> (no path or credentials). |
| <code>NAMAE</code> | Yes | None | RUI credential value supplied to <code>sendpw.cgi</code>. Keep it secret. |
| <code>IDTYPE</code> | No | <code>2</code> | Canon login account type; model/firmware-dependent. |
| <code>LOGIN_RETRIES</code> | No | <code>3</code> | Login attempts (1–99), including when the printer wakes slowly. |
| <code>WAKEUP_DELAY_SECONDS</code> | No | <code>3</code> | Delay between attempts. Set to <code>0</code> in tests. |
| <code>CANON_INSECURE_TLS</code> | No | <code>0</code> | Set to <code>1</code> only if the device's HTTPS certificate cannot be verified. |

The plugin does not accept <code>--host</code>, <code>--warning</code>, <code>--critical</code>, or other CLI options. It uses **the Canon-reported consumable status**, not configurable percentage thresholds: status 0 is OK, 1 or 3 is WARNING, 2 is CRITICAL, and malformed or unrecognized data yields UNKNOWN.

## Quick start

Pass the actual device origin and secret from a protected secret store or monitoring configuration (never commit credentials):

~~~bash
BASE=https://printer.example.local NAMAE="$CANON_RUI_SECRET" \
  /usr/lib/nagios/plugins/check_canon_rui_ink.sh
~~~

For a self-signed printer certificate, install a trusted certificate or CA if possible. If that is not feasible and the printer is on a trusted network, you may explicitly opt out of verification by adding <code>CANON_INSECURE_TLS=1</code>. The opt-out affects transport authenticity; it is not the default.

## Icinga and Nagios output

The script emits one plugin output line and the standard exit code:

~~~text
[OK] Color:40% Black:80% | color=40%;;;0;100 black=80%;;;0;100
~~~

| Code | State | Condition |
| --- | --- | --- |
| 0 | OK | All returned cartridges have Canon status 0 and readable levels. |
| 1 | WARNING | At least one cartridge has Canon status 1 or 3 and none has status 2. |
| 2 | CRITICAL | At least one cartridge has Canon status 2. |
| 3 | UNKNOWN | Connection/authentication failure, expired session, invalid or unreadable payload, or missing configuration. |

Percentage values are derived from Canon's discrete level indices (0→100%, 10→0%). Index 11 has no reliable percentage and is displayed as <code>?%</code> without fabricated performance data. The cartridge's Canon status drives severity; the percentage shown is not a separate threshold check. These are **device-reported estimates**, not measured ink volume.

## Validation and CI

Run the deterministic, offline checks from a checkout:

~~~bash
bash -n check_canon_rui_ink.sh
python3 -m unittest discover -s tests -v
~~~

The [CI workflow](.github/workflows/ci.yml) runs Bash syntax validation, ShellCheck, and the offline end-to-end tests on pull requests and pushes to <code>main</code>. A successful validation on <code>main</code> gates the GitHub release job for the version in [VERSION](VERSION); existing releases are not overwritten. No printer, real credential, or GitHub repository secret is needed for these tests.

**Validation boundary:** the tests use a deterministic fake <code>curl</code>, covering expected request sequence, secret handling, state mapping, parsing, failure conditions, and output. They do not prove compatibility with every real Canon model or firmware. No live-device test is claimed.

## Security

- HTTPS certificate verification is enabled by default. The legacy unconditional <code>curl -k</code> behavior is removed; use the explicit opt-out only when appropriate.
- Redirects are **not** followed, avoiding inadvertent forwarding of session credentials to a different destination.
- Secret login and session-token values are passed to curl from temporary files, not in its command-line arguments.
- The temporary directory is created with restrictive permissions and removed on exit. Do not enable shell tracing for a check containing secrets.
- Error output does not dump response bodies, cookies, session tokens, URLs, or the supplied credential into monitoring logs. Use a protected troubleshooting environment for device-specific diagnostics.
- Restrict access to the secret in the Icinga configuration or runtime environment, and keep the printer UI on a trusted management network.

## Troubleshooting

An UNKNOWN state indicates an incomplete check, not necessarily an empty cartridge. Verify the printer origin and route, confirm that the RUI login account has access, and check TLS trust. If a device returns no <code>INKREST</code> entries, its firmware or model may implement a different RUI contract. Do not publish HTML responses, cookies, or credential values in issues.

## Compatibility

This update retains the Bash entry point, environment variables <code>BASE</code>, <code>NAMAE</code> and <code>IDTYPE</code>, the existing color/black labels, Canon status severity, and Nagios/Icinga performance-data format. Two security-relevant behavior changes are intentional: TLS is verified unless explicitly opted out, and UNKNOWN output no longer contains a raw debug trail. Check existing deployments that relied on either legacy behavior before upgrading.

Licensed under [MIT](LICENSE).
