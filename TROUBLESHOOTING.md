# Project 1 Troubleshooting Log (Homelab + Vagrant Multi-Tier App)

This doc captures the real-world issues encountered while building the multi-tier web app locally using Vagrant + Virtualization, and the exact fixes used to get to a working state.

## Environment Snapshot
- Host: macOS (Apple Silicon homelab setup)
- Vagrant: multi-VM environment
- VMs: `web01` (Nginx), `app01` (Tomcat), `db01` (MariaDB), `mc01` (Memcached), `rmq01` (RabbitMQ)
- Networking: private network `192.168.56.0/24`
- App Entry (host): `http://127.0.0.1:<FORWARDED_PORT>` (example: `18089`)
- Tomcat Port (guest): `8080`
- Nginx Port (guest): `80`

---

## Quick “Is it Up?” Health Checks

### Check Vagrant + forwarded ports
```bash
vagrant status
vagrant port web01
Validate Nginx is listening in web01 and the app responds
bash
Copy code
vagrant ssh web01 -c "sudo ss -lntp | grep ':80 ' || true; curl -I http://localhost/login || true"
Validate service connectivity from app01
bash
Copy code
vagrant ssh app01 -c "getent hosts db01 mc01 rmq01; nc -vz db01 3306 || true; nc -vz mc01 11211 || true; nc -vz rmq01 5672 || true"
Validate Tomcat deployment artifacts exist
bash
Copy code
vagrant ssh app01 -c "ls -la /usr/local/tomcat8/webapps | egrep 'ROOT|war' || true"
Issues Log (Keep Adding to This)
1) Provider/plugin message: Vagrant VMware Utility required
Symptom

Plugin output indicated VMware Utility is required.

Cause

Vagrant provider mismatch (VMware provider selected when VirtualBox expected) or plugin installed without required utility.

Fix

Align provider with actual host setup.

Ensure Vagrantfile boxes/providers are compatible with the provider being used.

2) Box/provider mismatch (e.g., ubuntu/bionic64 not supported by provider)
Symptom

Vagrant fails with: “The box you're attempting to add doesn't support the provider you requested.”

Fix

Switch to a box that supports the active provider (example used successfully):

bento/ubuntu-22.04

3) Box download failed / DNS error
Symptom

Error example: Could not resolve host: files.midwesternmac.com

Cause

Third-party box hosting/DNS resolution issue.

Fix

Avoid that dependency by standardizing on a more reliable box source (Ubuntu 22.04 bento box used successfully).

4) “Machines not showing” / Vagrant commands run from wrong folder
Symptom

vagrant status shows nothing expected or machines not created.

VMs not visible in the provider UI.

Fix

Run Vagrant commands from the correct folder containing the Vagrantfile:

bash
Copy code
cd PROJECT_1/vagrant
vagrant up
5) Port confusion / port collisions on host
Symptom

http://127.0.0.1:<expected_port> refuses to connect.

Multiple ports in use on host.

Fix

Trust Vagrant’s forwarded port output:

bash
Copy code
vagrant port web01
Example mapping observed:

guest 80 → host 18089
So the correct URL became:

http://127.0.0.1:18089

6) Nginx upstream points to wrong Tomcat port (e.g., 8087)
Symptom

Nginx error log shows:

connect() failed (111) while connecting to upstream

upstream: "http://192.168.56.12:8087/"

Cause

Nginx config pointed to the wrong port.

Fix

Ensure Tomcat is on 8080 and Nginx upstream points to 8080:

nginx
Copy code
upstream vproapp {
  server app01:8080;
}
Restart Nginx:

bash
Copy code
vagrant ssh web01 -c "sudo nginx -t && sudo systemctl restart nginx"
7) curl -I returns 405 (HEAD not supported)
Symptom

curl -I http://.../login returns 405 and logs show:

Request method 'HEAD' not supported

Cause

curl -I uses the HEAD method; app endpoint supports GET.

Fix

Use GET:

bash
Copy code
curl -L http://127.0.0.1:<FORWARDED_PORT>/login | head
8) Login works via curl, but browser “refused to connect” after login
Symptom

Login page loads, but after submitting credentials browser redirects to:

http://127.0.0.1/ (no port) and fails/refuses connection

curl proved auth/session was working:

POST /login → 302

/welcome returned 200

Cause

App generated redirects without the forwarded host port (defaulting to port 80), but app is accessed via forwarded port (:18089).

Fix (Stable Solution)

Use Nginx redirect rewriting so Location headers return with the forwarded port.

Example (adjust port if different):

nginx
Copy code
location / {
  proxy_pass http://vproapp;

  proxy_set_header Host $http_host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;

  proxy_redirect http://app01:8080/ http://127.0.0.1:18089/;
  proxy_redirect http://localhost/  http://127.0.0.1:18089/;
  proxy_redirect http://127.0.0.1/ http://127.0.0.1:18089/;
}
Restart Nginx:

bash
Copy code
vagrant ssh web01 -c "sudo nginx -t && sudo systemctl restart nginx"
9) Tomcat logs file missing (catalina.out not found)
Symptom

tail: cannot open ... catalina.out: No such file or directory

Cause

Tomcat started under systemd; logs available via journald.

Fix

Use journalctl:

bash
Copy code
vagrant ssh app01 -c "sudo journalctl -u tomcat -n 200 --no-pager"
10) Confirmed “Working State”
Evidence

App serves login page through Nginx + forwarded port

Successful login shows welcome page

“All Users” works (DB + memcached path)

“RabbitMQ” works (broker path)

Verification Commands

bash
Copy code
curl -L http://127.0.0.1:18089/login | head
vagrant ssh app01 -c "nc -vz db01 3306; nc -vz mc01 11211; nc -vz rmq01 5672"
vagrant ssh web01 -c "curl -I http://app01:8080/login || true"

