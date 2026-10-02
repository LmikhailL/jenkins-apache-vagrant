# Jenkins → Apache2 deployment on a Vagrant (Oracle VirtualBox) VM

```
 macOS host
 ├── Docker (Colima) ── container "jenkins"  http://localhost:8090
 │                        │  pulls Jenkinsfile from this GitHub repo
 │                        │  ssh/http via host.docker.internal (192.168.5.2)
 └── VirtualBox ─────── VM "apache-vm" (Ubuntu 24.04, created by Vagrant)
                          ports forwarded: 2223 → 22 (ssh), 8081 → 80 (http)
```

## Layout

| Path | Purpose |
|------|---------|
| `Vagrantfile` | Clean Ubuntu 24.04 VM; authorizes the Jenkins deploy key |
| `Jenkinsfile` | Pipeline: check VM → install Apache2 → deploy → smoke test → fake errors → log analysis |
| `apache/lab-site.conf` | Virtual host incl. endpoints that return 403/410/500/503 |
| `site/` | Web page + intentionally broken CGI script (500) |
| `scripts/check_logs.sh` | Counts and lists 4xx/5xx in `access.log`, shows `error.log` errors |
| `jenkins/` | Jenkins image: plugins (`plugins.txt`) + Configuration-as-Code (`casc.yaml`: admin user, SSH credential, pipeline job from SCM) |
| `docker-compose.yml` | Runs Jenkins in Docker (nothing installed on the host) |

## Run

```bash
# 1. deploy key for Jenkins -> VM (kept out of git)
mkdir -p keys && ssh-keygen -t ed25519 -N '' -C jenkins-deploy -f keys/jenkins_deploy

# 2. target VM
vagrant up

# 3. Jenkins
cat > .env <<ENV
JENKINS_ADMIN_ID=admin
JENKINS_ADMIN_PASSWORD=change-me
GIT_REPO_URL=https://github.com/LmikhailL/jenkins-apache-vagrant.git
HOST_GATEWAY_IP=192.168.5.2   # Colima; with Docker Desktop use host-gateway
ENV
docker compose up -d --build
```

Open http://localhost:8090 → job **apache-deploy** → *Build with Parameters*.
Jenkins fetches the `Jenkinsfile` from GitHub (Pipeline script from SCM) and runs it.
The deployed site is at http://localhost:8081.

## Fake errors generated

| Request | Status |
|---------|--------|
| `/does-not-exist.html`, `/wp-login.php` | 404 |
| `/private/` | 403 |
| `DELETE /index.html` | 405 |
| HTTP/1.1 without `Host`, `/../../etc/passwd` | 400 |
| `/old-page` | 410 |
| `/cgi-bin/broken.cgi` | 500 |
| `/maintenance` | 503 |

The *Analyse Apache logs* stage runs `check_apache_logs` on the VM, prints the report,
archives it as `apache-log-report.txt` and writes `4xx: N, 5xx: M` into the build description.
Manual check on the VM: `vagrant ssh -c 'sudo check_apache_logs'`.

## Cleanup

```bash
docker compose down -v   # removes Jenkins container + volume
vagrant destroy -f       # removes the VM
```
