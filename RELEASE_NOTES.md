# v1.2.0: Canon Remote UI plugin hardening and automated tests

- Correct Bash-focused installation and configuration documentation.
- Add offline integration tests and CI validation (Bash syntax, ShellCheck, Python unittest).
- Harden authentication handling and protect the NAMAE credential and SBID session token.
- Enable TLS verification by default; allow explicit CANON_INSECURE_TLS=1 for self-signed certificates.
- Reject malformed, missing, or unknown Canon ink payloads with UNKNOWN.

**Upgrade note:** deployments relying on the previous implicit curl -k behavior must establish certificate trust or explicitly configure CANON_INSECURE_TLS=1. Raw debug trails on UNKNOWN are intentionally removed to avoid leaking secrets.

The CI tests simulate Canon endpoints and do not constitute validation against a physical printer.
