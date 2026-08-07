#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
  echo "usage: $0 command [args...]" >&2
  exit 64
fi

MYSQLD_BIN="${MYSQLD_BIN:-$(command -v mysqld)}"
MYSQL_BIN="${MYSQL_BIN:-$(command -v mysql)}"
MYSQLADMIN_BIN="${MYSQLADMIN_BIN:-$(command -v mysqladmin)}"
if [[ -z "$MYSQLD_BIN" || -z "$MYSQL_BIN" || -z "$MYSQLADMIN_BIN" ]]; then
  echo "mysqld, mysql, and mysqladmin are required" >&2
  exit 69
fi

TEST_ROOT="$(mktemp -d /tmp/poker-coach-mysql.XXXXXX)"
DATA_DIR="$TEST_ROOT/data"
SOCKET_PATH="$TEST_ROOT/mysql.sock"
PID_FILE="$TEST_ROOT/mysql.pid"
ERROR_LOG="$TEST_ROOT/mysql.err"
MYSQL_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
MYSQL_PID=""

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM
  if [[ -n "$MYSQL_PID" ]] && kill -0 "$MYSQL_PID" 2>/dev/null; then
    "$MYSQLADMIN_BIN" --no-defaults --protocol=socket --socket="$SOCKET_PATH" -uroot shutdown >/dev/null 2>&1 || true
    wait "$MYSQL_PID" 2>/dev/null || true
  fi
  rm -rf -- "$TEST_ROOT"
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

mkdir -p "$DATA_DIR"
DATA_DIR="$(cd "$DATA_DIR" && pwd -P)"
"$MYSQLD_BIN" --no-defaults --initialize-insecure --datadir="$DATA_DIR" --log-error="$ERROR_LOG"
"$MYSQLD_BIN" \
  --no-defaults \
  --datadir="$DATA_DIR" \
  --bind-address=127.0.0.1 \
  --port="$MYSQL_PORT" \
  --socket="$SOCKET_PATH" \
  --pid-file="$PID_FILE" \
  --log-error="$ERROR_LOG" \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_0900_ai_ci &
MYSQL_PID=$!

ready=0
for _ in $(seq 1 100); do
  if "$MYSQLADMIN_BIN" --no-defaults --protocol=socket --socket="$SOCKET_PATH" -uroot ping >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$MYSQL_PID" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
if [[ "$ready" -ne 1 ]]; then
  sed -n '1,200p' "$ERROR_LOG" >&2
  exit 70
fi

"$MYSQL_BIN" --no-defaults --protocol=socket --socket="$SOCKET_PATH" -uroot <<'SQL'
CREATE DATABASE poker_coach_test CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
CREATE USER 'poker_coach_test'@'127.0.0.1' IDENTIFIED BY 'test-only-password';
GRANT ALL PRIVILEGES ON `poker_coach_test%`.* TO 'poker_coach_test'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

MYSQL_SERVER_UUID="$("$MYSQL_BIN" --no-defaults --batch --skip-column-names --protocol=socket --socket="$SOCKET_PATH" -uroot -e 'SELECT @@server_uuid')"

export POKER_COACH_ENV=test
export POKER_COACH_MYSQL_DSN="poker_coach_test:test-only-password@tcp(127.0.0.1:$MYSQL_PORT)/poker_coach_test?charset=utf8mb4&parseTime=true&loc=UTC"
export POKER_COACH_HTTP_ADDR=127.0.0.1:0
export POKER_COACH_MYSQL_TEST_DATADIR="$DATA_DIR"
export POKER_COACH_MYSQL_TEST_SERVER_UUID="$MYSQL_SERVER_UUID"
export GOCACHE="${GOCACHE:-$TEST_ROOT/go-cache}"

cd "$(dirname "$0")/../Server"
"$@"
