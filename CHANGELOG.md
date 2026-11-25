# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-11-25

### Fixed
- Files with a comma or semicolon in the name (common for tracker downloads) could not be read by
  curl; this was reported as "qBittorrent unreachable" and stopped the whole batch.
- Torrents stayed stopped when qBittorrent is set to add new torrents stopped; they now start.
- The folder watcher and a manual or right-click send could run at once and send the same files
  twice; runs now take turns (`flock`).

### Changed
- Wait up to 120 seconds for qBittorrent's answer instead of 30 (`QBIT_TIMEOUT`). A timeout leaves
  the file in place; a retry of a torrent that did arrive counts as sent ("already in qBittorrent").
- A torrent qBittorrent already has (409 Conflict) moves to `sent-torrents/`, not `failed-torrents/`.

### Added
- `QBIT_CATEGORY` setting: add torrents under a qBittorrent category.

## [0.1.0] - 2026-11-24

### Added
- First public release: send `.torrent` files to qBittorrent's Web API, by name or every file in the
  download folder; sent files move to `sent-torrents/`, rejected ones to `failed-torrents/`.
- `--install`: systemd user path unit that sends new downloads automatically, plus "Send to
  qBittorrent" right-click actions for KDE Dolphin and GNOME Files. `--uninstall` undoes it.
- Optional Web UI login (password over stdin, never on a command line); works without one when
  qBittorrent whitelists the network.
- Files stay in place when qBittorrent is unreachable or refuses the login.
- Settings file `~/.config/qbit-send.conf`, log `~/.local/state/qbit-send.log`, desktop pop-ups.

[Unreleased]: https://github.com/H0m3Lab/qbit-send/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/H0m3Lab/qbit-send/releases/tag/v0.1.0
