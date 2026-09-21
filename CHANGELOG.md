# Changelog

## v1.2.0 — 2026-09-21

### Fixed
- Correct the documentation: the actual plugin is Bash, not Python, and takes configuration from environment variables rather than unsupported CLI flags.
- Return UNKNOWN for malformed, missing or unrecognized ink data, duplicate cartridge identifiers, and unreadable levels reported as OK.
- Retry a failed or incomplete login without inadvertently reporting an unrelated shell or curl exit status.

### Security
- Verify HTTPS certificates by default; allow the former insecure behavior only with the explicit CANON_INSECURE_TLS=1 opt-out.
- Stop following HTTP redirects during authenticated requests.
- Pass NAMAE and SBID from restrictive temporary files rather than curl command-line arguments.
- Prevent diagnostic output from exposing credentials, session tokens, response bodies, or cookies.
- Validate environment input and clean up per-run temporary files on exit.

### Quality and release
- Add deterministic offline end-to-end tests, Bash syntax validation and ShellCheck in GitHub Actions.
- Gate release creation on successful validation of the main branch.
- Document configuration, compatibility, exit codes, perfdata, and the limitations of mock-only validation.

## Earlier releases

Historical GitHub releases include v1.1.0 (2026-03-12), v0.1.0 and v0.1.1 (2026-05-19). GitHub's previous "latest" release ordering did not follow semantic version order; v1.2.0 advances beyond the existing v1.1.0 tag.
