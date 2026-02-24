#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../vagrant"

echo "== Nginx recent errors (web01) =="
vagrant ssh web01 -c "sudo tail -n 80 /var/log/nginx/error.log || true"

echo
echo "== Tomcat recent logs (app01) =="
vagrant ssh app01 -c "sudo journalctl -u tomcat -n 120 --no-pager || true"

echo
echo "== MariaDB status (db01) =="
vagrant ssh db01 -c "sudo systemctl --no-pager status mariadb | head -n 25 || true"

echo
echo "== Memcached status (mc01) =="
vagrant ssh mc01 -c "sudo systemctl --no-pager status memcached | head -n 25 || true"

echo
echo "== RabbitMQ status (rmq01) =="
vagrant ssh rmq01 -c "sudo systemctl --no-pager status rabbitmq-server | head -n 25 || true"
