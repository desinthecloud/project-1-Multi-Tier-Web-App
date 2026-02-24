#!/usr/bin/env bash
set -euo pipefail

echo "== Vagrant status =="
vagrant status

echo
echo "== Forwarded ports (web01) =="
vagrant port web01 || true

echo
echo "== web01: nginx listening + upstream check =="
vagrant ssh web01 -c "sudo ss -lntp | grep ':80 ' || true; curl -I http://app01:8080/login || true"

echo
echo "== app01: service connectivity to tiers =="
vagrant ssh app01 -c "nc -vz db01 3306 || true; nc -vz mc01 11211 || true; nc -vz rmq01 5672 || true"

echo
echo "== db01: basic data check =="
vagrant ssh db01 -c "sudo mariadb -e \"USE accounts; SHOW TABLES; SELECT COUNT(*) AS users FROM user;\" 2>/dev/null || true"

echo
echo "== mc01: memcached stats (high-level) =="
vagrant ssh mc01 -c "echo 'stats' | nc -w 2 localhost 11211 | egrep 'cmd_get|cmd_set|get_hits|get_misses|curr_items' || true"

echo
echo "== rmq01: rabbit status =="
vagrant ssh rmq01 -c "sudo rabbitmqctl status | head -n 15 || true"

echo
echo "== Host check: login page reachable =="
# Update port if your forwarded port changes
PORT=$(vagrant port web01 2>/dev/null | awk '/80 \(guest\)/{print $NF}' | tail -n 1)
curl -s -o /dev/null -w "Login page HTTP %{http_code}\n" "http://127.0.0.1:${PORT}/login"
