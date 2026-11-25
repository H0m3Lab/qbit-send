# CLAUDE.md: qbit-send

Guide for AI coding agents (and humans) working on this repository. Organization rules:
https://github.com/H0m3Lab/.github/blob/main/STANDARDS.md

## Purpose

Send `.torrent` files from a Linux desktop to a remote qBittorrent over its Web API: automatically
from the download folder (systemd user path unit) or by right-click in the file manager. One bash
script, no dependencies beyond curl and systemd.

## Architecture

Everything is in `qbit-send`:

- `main` parses the command (`--install`, `--uninstall`, `--version`, `--help`, or files to send).
- `do_send` sends the named files, or every `*.torrent` in `WATCH_DIR`. `login` (only when
  `QBIT_USER` is set) gets a session cookie; `upload` posts one file; `classify` turns the reply into
  `sent` (move to `SENT_DIR`), `failed` (move to `FAILED_DIR`), or `unreachable` / `forbidden`
  (leave the file, stop, exit 1).
- `do_install` writes `qbit-send.path` + `qbit-send.service` (systemd user units), a KDE service menu
  and a Nautilus script, all pointing at the script's own resolved path, then enables the path unit.
  `do_uninstall` removes exactly those files.
- Settings: bash `KEY="value"` file `~/.config/qbit-send.conf` (`QBIT_SEND_CONF` overrides).
  `QBIT_SEND_LOG`, `QBIT_SEND_UNIT_DIR`, `QBIT_SEND_SETTLE` exist for tests.

## Stack

- Language / runtime: bash
- System: curl, systemd user units, optional notify-send
- Storage: none (files are moved between folders; log in `~/.local/state/qbit-send.log`)

## Repository layout

```
qbit-send                  the tool (VERSION at the top)
qbit-send.conf.example     settings, placeholder values
tests/test.sh              tests with stubbed curl and systemctl (no qBittorrent, no systemd)
.github/workflows/ci.yml   shellcheck, tests, gitleaks
```

## Commands

| Task | Command |
|---|---|
| Test | `bash tests/test.sh` |
| Lint | `shellcheck -S warning qbit-send tests/test.sh` |
| Run locally | `./qbit-send --help` |

CI runs shellcheck, the tests, and gitleaks over the full history. Keep it green.

## Configuration

Settings are documented in the README settings table and `qbit-send.conf.example`. When you add or
change one: update both, give it a safe default, and add a CHANGELOG line.

## Conventions

- Stay one file; bash, curl and systemd only (plus `flock` from util-linux when present).
- Every outcome is logged with qBittorrent's answer; failures say what to do next.

## Data safety (do not break)

- Never delete a `.torrent` file: it is moved to `SENT_DIR` or `FAILED_DIR`, or left in place.
- When qBittorrent is unreachable or refuses the login, leave files where they are.
- `--uninstall` removes only the files `--install` wrote.

## Security

- Never put the Web UI password on a command line (it is piped to curl's stdin) or in the log.
- Never hardcode private values (real IPs, host names, domains, keys, names). Use placeholders like
  `192.0.2.10` in code, tests and docs.

## Releases

Semantic versioning. Version lives in `VERSION` at the top of `qbit-send`. Steps: CHANGELOG
`[Unreleased]` → new version section, bump `VERSION`, commit, tag `vX.Y.Z`, GitHub release with the
changelog section as notes.
