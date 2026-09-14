# Binary candidate license policy

The build inspects the locked Windows Cargo dependency graph (including some
build/test dependencies conservatively). It copies license/notice files supplied
with crates. When a crate omits its monorepo license, the build consults that
crate's `.cargo_vcs_info.json` and fetches ancestor license files only from the
recorded Git commit, recording each source URL. It never substitutes the latest
license or silently invents copyright notices.

New/unknown expressions, missing source metadata, and unrecoverable notices stop
the build. The current allowlist includes permissive software licenses and MPL-2.0;
MPL components also require corresponding-source availability. Rust crate source
links are exact name/version downloads. CUA's separate Node-runtime MPL notice
points to the exact upstream release's dependency and transformation script.

Additional reviewed licenses:

- MIT-0 permits distribution without an attribution condition; preserve supplied
  notices anyway: https://spdx.org/licenses/MIT-0.html
- CDLA-Permissive-2.0 permits sharing data provided the agreement accompanies it:
  https://cdla.dev/permissive-2-0/ (used by the TLS root certificate data).

This is an automated inventory and conservative gate, not proof of every binary's
provenance. Reviewers must still check the exact artifact, any native/vendored
components, and MPL source availability before approving a public binary release.
