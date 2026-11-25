#!/bin/bash
# shellcheck disable=SC2034  # U, rc are read inside the eval'd check strings
# Tests for qbit-send. No qBittorrent and no systemd needed: curl and systemctl are stubbed.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "ok   $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# stub curl: behaviour picked by $FAKE (sent | ok | conflict | invalid | down | forbidden | login-bad | slow)
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_LOG"
if [[ "$*" == *auth/login* ]]; then
  pw=$(cat); echo "login-pw=$pw" >> "$FAKE_LOG"
  [ "$FAKE" = login-bad ] && { printf 'Fails.'; exit 0; }
  printf 'Ok.'; exit 0
fi
# like real curl: the upload file must be readable via the quoted torrents=@"..." form field
for a in "$@"; do
  case $a in torrents=@*)
    f=${a#torrents=@}
    if [ "${f:0:1}" = '"' ]; then f=${f:1:${#f}-2}; f=${f//\\\"/\"}; f=${f//\\\\/\\}
    else f=${f%%[,;]*}; fi
    [ -r "$f" ] || { printf '\n000'; exit 26; } ;;
  esac
done
sleep "${FAKE_DELAY:-0}"
case $FAKE in
  slow)      printf '\n000'; exit 28 ;;
  sent)      printf '{"success_count":1,"failure_count":0}\n200' ;;
  ok)        printf 'Ok.\n200' ;;
  conflict)  printf 'Conflict\n409' ;;
  invalid)   printf "Error: 'x' is not a valid torrent file.\n415" ;;
  forbidden) printf 'Forbidden\n403' ;;
  down)      printf '\n000'; exit 7 ;;
esac
EOF
cat > "$T/bin/systemctl" <<'EOF'
#!/bin/bash
echo "systemctl $*" >> "$FAKE_LOG"
EOF
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH" FAKE_LOG="$T/calls" HOME="$T/home" QBIT_SEND_SETTLE=0
export XDG_CONFIG_HOME="$T/home/.config" XDG_DATA_HOME="$T/home/.local/share" XDG_STATE_HOME="$T/home/.local/state"
mkdir -p "$HOME/Downloads"
Q="$ROOT/qbit-send"
D="$HOME/Downloads"
run() { FAKE=$1; export FAKE; shift; : > "$FAKE_LOG"; bash "$Q" "$@" >/dev/null 2>&1; }

# --- helpers (sourced) ---
# shellcheck source=/dev/null
( . "$Q"
  check "classify json success"  '[ "$(classify "{\"success_count\":2}" 200 0)" = sent ]'
  check "classify Ok."           '[ "$(classify Ok. 200 0)" = sent ]'
  check "classify zero success"  '[ "$(classify "{\"success_count\":0,\"failure_count\":1}" 200 0)" = failed ]'
  check "classify conflict"      '[ "$(classify Conflict 409 0)" = already ]'
  check "classify timeout"       '[ "$(classify "" 000 28)" = timeout ]'
  check "classify unreadable"    '[ "$(classify "" 000 26)" = unreadable ]'
  check "classify invalid"       '[ "$(classify "Error: x" 415 0)" = failed ]'
  check "classify down"          '[ "$(classify "" 000 7)" = unreachable ]'
  check "classify forbidden"     '[ "$(classify Forbidden 403 0)" = forbidden ]'
  check "is_torrent case"        'is_torrent a.TORRENT && ! is_torrent a.txt'
  check "unit_path escapes %"    '[ "$(unit_path "/x/50%off")" = "/x/50%%off" ]'
) | tee "$T/sub"; pass=$((pass+$(grep -c '^ok' "$T/sub"))); fail=$((fail+$(grep -c '^FAIL' "$T/sub")))

# --- sending ---
touch "$D/a.torrent" "$D/B.TORRENT" "$D/notes.txt"
run sent
check "sends every .torrent (any case)" '[ -f "$D/sent-torrents/a.torrent" ] && [ -f "$D/sent-torrents/B.TORRENT" ]'
check "leaves other files alone"        '[ -f "$D/notes.txt" ]'
check "uses default URL"                'grep -q "http://localhost:8080/api/v2/torrents/add" "$FAKE_LOG"'
check "no login without a user"         '! grep -q auth/login "$FAKE_LOG"'

touch "$D/c.torrent"; run ok
check "old 'Ok.' reply counts as sent"  '[ -f "$D/sent-torrents/c.torrent" ]'

touch "$D/d.torrent"; run conflict; rc=$?
check "already in qBittorrent counts as sent" '[ -f "$D/sent-torrents/d.torrent" ] && [ $rc -eq 0 ]'
touch "$D/d2.torrent"; run invalid; rc=$?
check "invalid parked in failed"        '[ -f "$D/failed-torrents/d2.torrent" ]'
check "failure gives exit 1"            '[ $rc -eq 1 ]'

touch "$D/Boss,_Do_What;You \"Love\".torrent"; run sent; rc=$?
check "comma, semicolon, quote in name" '[ -f "$D/sent-torrents/Boss,_Do_What;You \"Love\".torrent" ] && [ $rc -eq 0 ]'
check "added started, not stopped"      'grep "torrents/add" "$FAKE_LOG" | grep -q "stopped=false"'
check "no category unless set"          '! grep -q "category=" "$FAKE_LOG"'

touch "$D/s.torrent"; run slow; rc=$?
check "timeout: file stays put, exit 1" '[ -f "$D/s.torrent" ] && [ $rc -eq 1 ]'
check "default timeout 120s"            'grep "torrents/add" "$FAKE_LOG" | grep -q -- "-m 120"'
run conflict
check "retry after timeout: already there -> sent" '[ -f "$D/sent-torrents/s.torrent" ]'

touch "$D/e.torrent"; run down; rc=$?
check "server down: file stays put"     '[ -f "$D/e.torrent" ] && [ $rc -eq 1 ]'
run forbidden
check "403: file stays put"             '[ -f "$D/e.torrent" ]'

mkdir -p "$T/other"; touch "$T/other/f.torrent" "$T/other/g.txt"
run sent "$T/other/f.torrent" "$T/other/g.txt"
check "named files are sent"            '[ -f "$D/sent-torrents/f.torrent" ] && [ -f "$T/other/g.txt" ]'
check "watch-folder files untouched when files are named" '[ -f "$D/e.torrent" ]'

if command -v flock >/dev/null; then
  mkdir -p "$T/race"; touch "$T/race/r1.torrent" "$T/race/r2.torrent" "$T/race/r3.torrent"
  : > "$FAKE_LOG"; export FAKE=sent FAKE_DELAY=0.3
  printf 'WATCH_DIR="%s"\nNOTIFY="no"\n' "$T/race" > "$T/race.conf"
  for _ in 1 2; do QBIT_SEND_CONF="$T/race.conf" bash "$Q" >/dev/null 2>&1 & done; wait
  unset FAKE_DELAY
  check "two runs at once send each file once" '[ "$(grep -c "torrents/add" "$FAKE_LOG")" -eq 3 ] && [ -f "$T/race/sent-torrents/r3.torrent" ]'
fi

run sent   # sends the e.torrent left over from the "down" test
run sent
check "nothing to do: no calls"         '[ ! -s "$FAKE_LOG" ]'

# --- settings file + login ---
mkdir -p "$XDG_CONFIG_HOME"
cat > "$XDG_CONFIG_HOME/qbit-send.conf" <<'EOF'
QBIT_URL="http://192.0.2.10:8080/"
QBIT_USER="alice"
QBIT_PASS="s3cret pass"
WATCH_DIR="$HOME/Torrents"
NOTIFY="no"
QBIT_CATEGORY="books"
QBIT_TIMEOUT=45
EOF
mkdir -p "$HOME/Torrents"; touch "$HOME/Torrents/h.torrent"
run sent
check "custom URL, trailing / dropped"  'grep -q "http://192.0.2.10:8080/api/v2/torrents/add" "$FAKE_LOG"'
check "custom watch folder"             '[ -f "$HOME/Torrents/sent-torrents/h.torrent" ]'
check "logs in first"                   'grep -q "auth/login" "$FAKE_LOG"'
check "password via stdin only"         'grep -q "login-pw=s3cret pass" "$FAKE_LOG" && ! grep -v "^login-pw" "$FAKE_LOG" | grep -q s3cret'
check "cookie used for upload"          'grep "torrents/add" "$FAKE_LOG" | grep -q -- "-b "'
check "category sent when set"          'grep "torrents/add" "$FAKE_LOG" | grep -q "category=books"'
check "timeout setting used"            'grep "torrents/add" "$FAKE_LOG" | grep -q -- "-m 45"'
touch "$HOME/Torrents/i.torrent"; run login-bad; rc=$?
check "bad login: nothing sent, exit 1" '[ -f "$HOME/Torrents/i.torrent" ] && [ $rc -eq 1 ] && ! grep -q torrents/add "$FAKE_LOG"'
rm -f "$XDG_CONFIG_HOME/qbit-send.conf"

# --- install / uninstall ---
run sent --install
U="$XDG_CONFIG_HOME/systemd/user"
check "path unit watches Downloads"     'grep -qx "PathChanged=$D" "$U/qbit-send.path"'
check "service runs this script"        'grep -q "ExecStart=\"$(readlink -f "$Q")\"" "$U/qbit-send.service"'
check "watcher enabled"                 'grep -q "enable --now qbit-send.path" "$FAKE_LOG"'
check "Dolphin action executable"       '[ -x "$XDG_DATA_HOME/kio/servicemenus/qbit-send.desktop" ]'
check "Dolphin action for torrents"     'grep -q "MimeType=application/x-bittorrent;" "$XDG_DATA_HOME/kio/servicemenus/qbit-send.desktop"'
check "Nautilus script executable"      '[ -x "$XDG_DATA_HOME/nautilus/scripts/Send to qBittorrent" ]'
bash -n "$XDG_DATA_HOME/nautilus/scripts/Send to qBittorrent" && ok "Nautilus script syntax" || bad "Nautilus script syntax"
run sent --uninstall
check "uninstall removes everything"    '[ ! -e "$U/qbit-send.path" ] && [ ! -e "$U/qbit-send.service" ] && [ ! -e "$XDG_DATA_HOME/kio/servicemenus/qbit-send.desktop" ] && [ ! -e "$XDG_DATA_HOME/nautilus/scripts/Send to qBittorrent" ]'
check "--version"                       '[ "$(bash "$Q" --version)" = "qbit-send $(sed -n "s/^VERSION=\"\(.*\)\"/\1/p" "$Q")" ]'
bash "$Q" --bogus >/dev/null 2>&1; rc=$?
check "unknown option exits 2"          '[ $rc -eq 2 ]'

echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
