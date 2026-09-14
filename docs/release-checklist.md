# Candidate certification

Record the candidate run URL, archive SHA256, script commit, CUA version, Windows
version, OpenSSH version and tested Codex/Hermes versions in a public issue/report.
Do not upload screenshots, secrets or private host addresses.

- [ ] Candidate build and HTTP smoke test passed.
- [ ] Review THIRD-PARTY-NOTICES and exact-version source availability (including MPL runtime).
- [ ] Interactive desktop: Explorer window enumeration and inline MCP screenshot passed.
- [ ] Fresh Notepad document: launch, type a harmless test string, read it back; do not overwrite user files.
- [ ] SSH key connection and password connection both pass; wrong password fails cleanly.
- [ ] Paths with spaces work (script and driver directories).
- [ ] Local/remote port conflict prevents startup; existing services are unaffected.
- [ ] Duplicate Start does not create duplicate children.
- [ ] Closing the visible start window leaves the connection usable.
- [ ] Killing/disconnecting the tunnel stops the owned driver; Stop releases both ports.
- [ ] Codex initializes and performs a harmless GUI action through the tunnel.
- [ ] Hermes initializes, lists tools and performs a harmless GUI action.
- [ ] Start and Status show the same five fields; stopped state never claims connected.
- [ ] No personal settings, logs or credentials in the archive.

Use a dedicated logged-in Windows desktop. Do not register a service-mode runner
and assume it can access the interactive desktop. Do not run untrusted PR jobs on
a self-hosted GUI machine. Desktop GUI checks remain manual until a dedicated,
trusted runner is configured; the repository does not claim they are automated.

Only then dispatch **Publish tested candidate** with the original run ID and report
URL. The `release` environment can require an additional reviewer. A maintainer
must not attest to checks that were skipped. Source-only releases may be published
separately and must explicitly state that no CUA binary is included.
