# Security and reporting

The Windows endpoint and remote SSH forward bind to loopback. Any client with the
Bearer token can use the admitted CUA tools on that desktop. Do not publish
tokens, `.runtime`, private keys, desktop screenshots, or configured local copies.

Use SSH host-key verification; establish trust with an ordinary SSH login before
the first run. Passwords are requested interactively and stored temporarily with
Windows CurrentUser DPAPI for SSH_ASKPASS; the supervisor removes that encrypted
password file on exit. The token remains DPAPI-encrypted in runtime configuration.
Fixed tokens in your personal `config.ini` are plain text. Keep that file private;
it is ignored by Git and excluded from release ZIPs. Only the clean template ships.

Use a dedicated, empty desktop for GUI integration testing. Do not execute pull
request code on a personal/self-hosted desktop runner. Hosted CI smoke checks do
not certify real desktop control.

Report vulnerabilities privately using the repository's GitHub security advisory
feature when available. Do not place credentials or exploit details in public issues.
