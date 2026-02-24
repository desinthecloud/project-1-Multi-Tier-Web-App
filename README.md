# Project 1: Manual Setup of Multi-Tier Web Application (Vagrant + VirtualBox)

This project is my hands-on reality check between being certified and landing my first engineering role. The goal is to stand up a full multi-tier app manually so I understand every moving piece before automating it.

## Architecture

| Layer | Service |
|-------|---------|
| Web | Nginx (reverse proxy) |
| App | Tomcat (Java) |
| Cache | Memcached |
| Messaging | RabbitMQ |
| Database | MariaDB/MySQL |
| Provisioning | Vagrant + VirtualBox (local homelab) |

![Architecture](./images/architecture.png)

## Prerequisites

- Oracle VM VirtualBox
- Vagrant
- Git Bash or equivalent terminal
- Vagrant plugins:
  ```bash
  vagrant plugin install vagrant-hostmanager
  vagrant plugin install vagrant-vbguest
  ```

---

## Step 1: Bring Up the Environment

From the project directory, run:

```bash
cd vagrant
vagrant up
```

This launches five VMs, one for each service. Verify they are all running in the VirtualBox manager.

![Virtual Machines](./images/vagrant.png)

SSH into web01 to confirm all VMs are connected by checking the hosts file:

```bash
vagrant ssh web01
cat /etc/hosts
```

![Vagrant Validation](./images/vagrant_validate.png)

Repeat for each VM: app01, rmq01, mc01, db01. You can also ping other VMs from within any machine to confirm connectivity.

---

## Step 2: Database VM (MariaDB)

![VProfile Web Architecture](./images/vprofile_web_arc.png)

SSH into db01 and switch to root:

```bash
vagrant ssh db01
sudo -i
```

Update the OS and install dependencies:

```bash
yum update -y
yum install epel-release -y
yum install git mariadb-server -y
```

Set the database password as an environment variable and make it permanent:

```bash
DATABASE_PASS='admin123'
vi /etc/profile
source /etc/profile
```

Start and enable MariaDB:

```bash
systemctl start mariadb
systemctl enable mariadb
systemctl status mariadb
```

![DB Service](./images/db_verification.png)

Run the secure installation script and set the root password to `admin123`:

```bash
mysql_secure_installation
```

![MariaDB Setup](./images/mariadb_setup.png)

Clone the source repo and initialize the database:

```bash
git clone -b local-setup https://github.com/apotitech/vprofile-project.git
cd vprofile-project/src/main/resources

mysql -u root -p"$DATABASE_PASS" -e "create database accounts"
mysql -u root -p"$DATABASE_PASS" -e "grant all privileges on accounts.* TO 'admin'@'app01' identified by 'admin123'"
cd ../../..
mysql -u root -p"$DATABASE_PASS" accounts < src/main/resources/db_backup.sql
mysql -u root -p"$DATABASE_PASS" -e "FLUSH PRIVILEGES"
```

Verify the database contains the `role`, `user`, and `user_role` tables:

```bash
mysql -u root -p"$DATABASE_PASS"
MariaDB [(none)]> show databases;
MariaDB [(none)]> use accounts;
MariaDB [accounts]> show tables;
MariaDB [accounts]> exit
```

Restart MariaDB and exit:

```bash
systemctl restart mariadb
logout
```

---

## Step 3: Cache VM (Memcached)

SSH into mc01 and switch to root:

```bash
vagrant ssh mc01
sudo -i
```

Update and install Memcached:

```bash
yum update -y
yum install epel-release -y
yum install memcached -y
systemctl start memcached
systemctl enable memcached
systemctl status memcached
```

![Memcached](./images/memcached.png)

Configure Memcached to listen on TCP port 11211 and UDP port 11111:

```bash
memcached -p 11211 -U 11111 -u memcached -d
```

Validate it is running on the correct port:

```bash
ss -tunlp | grep 11211
```

![Memcached Validation](./images/memcached_valid.png)

Exit the VM:

```bash
logout
```

---

## Step 4: Messaging VM (RabbitMQ)

SSH into rmq01 and switch to root:

```bash
vagrant ssh rmq01
sudo -i
```

Update the OS and install dependencies:

```bash
yum update -y
yum install epel-release -y
sudo yum install wget -y
cd /tmp/
wget http://packages.erlang-solutions.com/erlang-solutions-2.0-1.noarch.rpm
sudo rpm -Uvh erlang-solutions-2.0-1.noarch.rpm
sudo yum -y install erlang socat
```

Install and start RabbitMQ:

```bash
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | sudo bash
sudo yum install rabbitmq-server -y
sudo systemctl start rabbitmq-server
sudo systemctl enable rabbitmq-server
sudo systemctl status rabbitmq-server
```

![RabbitMQ Validation](./images/rabbitmq_validation.png)

Configure RabbitMQ, create the app user, and restart the service:

```bash
sudo sh -c 'echo "[{rabbit, [{loopback_users, []}]}]." > /etc/rabbitmq/rabbitmq.config'
sudo rabbitmqctl add_user test test
sudo rabbitmqctl set_user_tags test administrator
systemctl restart rabbitmq-server
logout
```

---

## Step 5: App VM (Tomcat)

SSH into app01 and switch to root:

```bash
vagrant ssh app01
sudo -i
```

Update the OS and install dependencies:

```bash
yum update -y
yum install epel-release -y
yum install java-1.8.0-openjdk -y
yum install git maven wget -y
```

Download and extract Tomcat:

```bash
cd /tmp/
wget https://archive.apache.org/dist/tomcat/tomcat-8/v8.5.37/bin/apache-tomcat-8.5.37.tar.gz
tar xzvf apache-tomcat-8.5.37.tar.gz
```

Create the tomcat user and copy files to the home directory:

```bash
useradd --home-dir /usr/local/tomcat8 --shell /sbin/nologin tomcat
cp -r /tmp/apache-tomcat-8.5.37/* /usr/local/tomcat8/
```

Create the systemd service file:

```bash
vi /etc/systemd/system/tomcat.service
```

Paste the following content:

```ini
[Unit]
Description=Tomcat
After=network.target

[Service]
User=tomcat
WorkingDirectory=/usr/local/tomcat8
Environment=JRE_HOME=/usr/lib/jvm/jre
Environment=JAVA_HOME=/usr/lib/jvm/jre
Environment=CATALINA_HOME=/usr/local/tomcat8
Environment=CATALINE_BASE=/usr/local/tomcat8
ExecStart=/usr/local/tomcat8/bin/catalina.sh run
ExecStop=/usr/local/tomcat8/bin/shutdown.sh
SyslogIdentifier=tomcat-%i

[Install]
WantedBy=multi-user.target
```

Enable and start Tomcat:

```bash
systemctl daemon-reload
systemctl start tomcat
systemctl enable tomcat
```

Build and deploy the application:

```bash
git clone -b local-setup https://github.com/apotitech/vprofile-project.git
cd vprofile-project
mvn install
systemctl stop tomcat
rm -rf /usr/local/tomcat8/webapps/ROOT*
cp target/vprofile-v2.war /usr/local/tomcat8/webapps/ROOT.war
systemctl start tomcat
chown tomcat.tomcat /usr/local/tomcat8/webapps -R
systemctl restart tomcat
```

---

## Step 6: Web VM (Nginx)

SSH into web01 and switch to root:

```bash
vagrant ssh web01
sudo -i
```

Update the OS and install Nginx:

```bash
apt update && apt upgrade -y
apt install nginx -y
```

Create the Nginx reverse proxy config:

```bash
vi /etc/nginx/sites-available/vproapp
```

Paste the following content:

```nginx
upstream vproapp {
  server app01:8080;
}
server {
  listen 80;
  location / {
    proxy_pass http://vproapp;
  }
}
```

Remove the default config and activate the new one:

```bash
rm -rf /etc/nginx/sites-enabled/default
ln -s /etc/nginx/sites-available/vproapp /etc/nginx/sites-enabled/vproapp
systemctl restart nginx
```

---

## Validation

Get the IP address of the web01 VM:

```bash
ifconfig
```

![IP Address](./images/ip_addr.png)

Open your browser and navigate to `http://192.168.56.11`. The application should load.

![Website](./images/web.png)

Log in with username `admin_vp` and password `admin_vp`. A successful login confirms MySQL is connected.

![Welcome Page](./images/welcome_page.png)

Click `All Users` to confirm Memcached is connected.

![Memcache](./images/memcache.png)

Click `RabbitMQ` to confirm the message broker is connected.

![RabbitMQ](./images/rabbit.png)

---

## Troubleshooting

- **502 from Nginx** - Tomcat is not running or the upstream IP/port is wrong
- **Login fails** - Check the DB dump imported correctly and credentials match
- **Session issues** - Confirm Memcached is reachable from the app VM
- **Async features fail** - Check RabbitMQ user permissions

---

## Cleanup

```bash
vagrant destroy
```

Confirm all VMs are gone in the VirtualBox manager.

![Vagrant Destroy](./images/des-vag.png)

---

## What I Learned

- How each tier fails and what good looks like at each layer
- Why manual setup is valuable before automating anything
- What to automate next (Project 2)
