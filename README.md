# qbit-send

Send `.torrent` files to qBittorrent on another machine, straight from your Linux desktop. Save a
torrent from the browser and it is in qBittorrent a second later; or right-click any `.torrent` and
pick **Send to qBittorrent**. One small bash script, using only curl and systemd.

```
$ qbit-send --install
Installed. .torrent files saved to /home/alice/Downloads now go to http://192.0.2.10:8080 by themselves.
Right-click a .torrent in Dolphin (or Files > Scripts) for "Send to qBittorrent".
```

Made for a desktop that downloads torrents in the browser while qBittorrent runs on a server or NAS,
without installing a desktop torrent client or a browser extension.

## How it works

- `qbit-send --install` adds a systemd **user** path unit that watches your download folder. When a
  file appears, qbit-send uploads every `.torrent` there to qBittorrent's Web API
  (`/api/v2/torrents/add`).
- Sent files move to `sent-torrents/` in that folder, and so do files qBittorrent already has.
  Files it rejects (not a valid torrent) move to `failed-torrents/` so they are not retried forever.
- If qBittorrent is off, refuses the login, or does not answer within `QBIT_TIMEOUT`, files stay
  where they are and go with the next run.
- Only one run sends at a time (the folder watcher and a right-click send can overlap).
- A desktop pop-up says what happened (if `notify-send` is there). Every action goes to the log.
- Right-click actions: KDE Dolphin (a service menu for `.torrent` files) and GNOME Files (Scripts menu).
- Torrents start right away, even when qBittorrent is set to add new torrents stopped. Save path
  follows qBittorrent's defaults; set `QBIT_CATEGORY` to file them under a category.

## Requirements

- bash, curl, systemd (user session); `flock` from util-linux (on every systemd system) keeps runs from overlapping
- qBittorrent 4.1 or newer with the Web UI on
- Optional: `notify-send` (libnotify) for pop-ups

## Install

```
install -D -m 755 qbit-send ~/.local/bin/qbit-send      # or: sudo install -m 755 qbit-send /usr/local/bin/
install -D -m 600 qbit-send.conf.example ~/.config/qbit-send.conf   # then edit QBIT_URL
qbit-send --install
```

Run `--install` again after moving the script or changing `WATCH_DIR`.

## Use

| Command | What it does |
|---|---|
| `qbit-send --install` | Watch the download folder and add the right-click actions. |
| `qbit-send` | Send every `.torrent` in the watch folder now. |
| `qbit-send FILE.torrent...` | Send just those files, from anywhere. |
| `qbit-send --uninstall` | Remove the watcher and right-click actions (settings and log stay). |
| `qbit-send --version` | Print the version. |

## Settings

`~/.config/qbit-send.conf` (start from `qbit-send.conf.example`):

| Setting | Default | Meaning |
|---|---|---|
| `QBIT_URL` | `http://localhost:8080` | qBittorrent Web UI address. |
| `QBIT_USER` | empty | Web UI username. Empty = no login (see below). |
| `QBIT_PASS` | empty | Web UI password. Sent over stdin, never on a command line. |
| `WATCH_DIR` | `~/Downloads` | Folder `--install` watches. |
| `SENT_DIR` | `WATCH_DIR/sent-torrents` | Where sent files go. |
| `FAILED_DIR` | `WATCH_DIR/failed-torrents` | Where rejected files go. |
| `NOTIFY` | `yes` | Desktop pop-up after each batch. |
| `QBIT_CATEGORY` | empty | qBittorrent category for added torrents. Empty = none. |
| `QBIT_TIMEOUT` | `120` | Seconds to wait for qBittorrent's answer per file. |

**No login needed on a home network:** in qBittorrent, Options > Web UI > tick "Bypass
authentication for clients in whitelisted IP subnets" and add your network (for example
`192.0.2.0/24`). Then leave `QBIT_USER` empty and no password is stored anywhere.

If you do set a password, keep the file private: `chmod 600 ~/.config/qbit-send.conf`.

## Troubleshooting

- **Log:** `~/.local/state/qbit-send.log` lists every file sent, rejected or left in place, with
  qBittorrent's answer.
- **Is the watcher running?** `systemctl --user status qbit-send.path`; last run:
  `journalctl --user -u qbit-send.service`.
- **"qBittorrent unreachable"**: wrong `QBIT_URL`, or the Web UI is off. Test with
  `curl http://<server>:8080/api/v2/app/version`.
- **"qBittorrent forbidden (HTTP 403)"**: the Web UI wants a login. Set `QBIT_USER`/`QBIT_PASS`, or
  whitelist your network. Too many failed logins make qBittorrent ban your IP for a while.
- **A file in `failed-torrents/`**: the log shows why (usually not a valid torrent file).
- **"did not answer within 120s"**: qBittorrent was busy (often a slow disk). The file stays and is
  sent again on the next run; if it had arrived after all, the log says "already in qBittorrent".
- **No "Send to qBittorrent" in Dolphin**: close every Dolphin window and reopen it. The service
  menu must stay executable (`--install` sets that).

## Releases and contributing

Changes are listed in [CHANGELOG.md](CHANGELOG.md). Releases are tagged `vX.Y.Z` on GitHub; the
version is `VERSION` in the script. Issues and pull requests are welcome; see the organization's
contributing guide.

## License

MIT, see [LICENSE](LICENSE).
