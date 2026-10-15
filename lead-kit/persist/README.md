# Persistence kit

Back up explicitly configured files to an encrypted local store, optionally
copying the encrypted archive to SSH storage. Requires Bash, Python 3.12+
(for safe extraction), GNU tar/coreutils, gzip, and OpenSSL. Remote operations
also require Paramiko in the interpreter selected by `PERSIST_PY`.

Copy `persist.env.example` to `~/.config/lead-kit/persist.env`, or set
`PERSIST_CONFIG` to another file. Configuration is KEY=VALUE data with shell
quoting and comments, without variable expansion or command execution.
Environment values override file values. Use absolute local paths.

- `PERSIST_STORE` is always required. Create it outside included paths, restrict
  access, and create a readable `passphrase` file there before encrypted backup.
- `PERSIST_INCLUDE` is a shell-quoted list of paths to archive, including any
  credentials you need to restore. Nothing is included implicitly.
- `HUB_DB` optionally selects a SQLite database to copy consistently with its
  backup API. Its configured absolute path is preserved in the archive.
- Remote operations require `PERSIST_HOST`, `PERSIST_USER`, `PERSIST_KEY`,
  `PERSIST_PORT`, `PERSIST_KNOWN_HOSTS`, and `PERSIST_REMOTE_DIR`.
  The remote directory is absolute or relative to the SSH user's home.
  Provision the known-hosts file using a verified host key; unknown hosts fail.
- `PERSIST_PY` is the Python executable with Paramiko, defaulting to `python3`.
  It is an executable path/name, not a command with arguments.

```sh
./backup.sh --no-vps
./backup.sh
./restore.sh --dry-run /tmp/restore-preview
./restore.sh --snapshot 20260101-120000
./restore.sh --from-vps --dry-run /tmp/restore-preview
./restore.sh --plain --dry-run /tmp/restore-preview
```

Encrypted snapshots use AES-256-CBC with PBKDF2 (200,000 iterations), retain five
dated snapshots, and maintain a local latest copy and checksum files.
The passphrase must be available independently for recovery. Checksums detect
accidental corruption; the CBC archive and checksums do not authenticate a
maliciously modified backup.

If the passphrase is unavailable, backup uses a plain remote fallback.
It excludes credential/config/key filenames, the configured key, known-hosts,
config file, and store; scans file contents for secret and IP patterns; drops
matching files; and aborts if the complete SQLite dump contains matches.
It writes a checksum and a `.dropped` manifest alongside the archive.
Review include paths before enabling this heuristic fallback: secret detection
cannot guarantee that arbitrary sensitive data is identified. `--no-vps` fails
if encrypted local backup is unavailable.

Restore preserves archived absolute paths beneath the extraction root (default
`/`). Preview under a separate directory before restoring into the filesystem.
Plain restore verifies its checksum and restores only the scanned data.
Restore installs no tools and does not alter shell configuration;
`--skip-install` remains accepted for compatibility. Older machine-specific
two-archive layouts are not supported by this generic format.
