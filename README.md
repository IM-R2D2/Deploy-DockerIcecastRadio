# Deploy-DockerIcecastRadio

One-command deploy for **Icecast** (streaming server) in Docker on a Linux host. The script sets up directories, configs, and Docker Compose so you can run an Icecast radio stack with minimal manual steps.

---

## What it does

- **Checks or installs Docker** on the host (Ubuntu: official Docker repo).
- **Creates a fixed directory layout**: projects under `/usr/local/bin/docker/<project>`, logs in the same project folder (`.../logs/icecast`, `.../logs/nginx`).
- **Generates Icecast config** from a template, filled with your `.env` values.
- **Deploys a ready-to-run `docker-compose.yml`** into the project folder and **starts the stack** (`docker compose up -d`).
- **Optional:** if `iptables` is available and the Docker bridge exists, ensures firewall rules for traffic from the project bridge (`br-<PROJECT_NAME>`); repeated deploys do not duplicate the same rules (`iptables -C` before insert).
- **Checks the service** with `curl` and prints a short summary (project path, service URL/status, logs command).

You clone this repo on the server, fill in `.env`, run **`./deploy.sh` from the clone root** (so `conf/icecast-web/` with `status-json.xsl`, `xml2json.xslt`, `index.html` is next to the script — they are **committed in git**; to refresh from upstream use the commands in [`conf/icecast-web/README.md`](conf/icecast-web/README.md)). The stack is deployed and started; you only need `docker compose up -d` by hand if the script reports a start failure (e.g. after a fresh Docker install).

---

## Prerequisites

- **Linux** (tested on Ubuntu; other Debian-based systems should work).
- **Bash** (script uses `bash`).
- **sudo** for creating directories under `/usr/local/bin` and for installing Docker if missing.
- **Optional:** `envsubst` (from `gettext-base`) for variable substitution in configs; if absent, templates are copied as-is (you’d have to edit them manually).
- **Optional:** `curl` for the end-of-deploy service check; if absent, the summary shows that the check was skipped.

---

## Quick start

1. **Clone the repo** on the server (any directory, e.g. `/docker`):

   ```bash
   git clone https://github.com/IM-R2D2/Deploy-DockerIcecastRadio.git
   cd Deploy-DockerIcecastRadio
   ```

2. **Create and edit your config**:

   ```bash
   cp .env.example .env
   nano .env   # or vim, etc.
   ```

   Set at least:
   - `PROJECT_NAME` – project folder name (e.g. `radio`).
   - `IP_ADDRESS` – fixed IP for the Icecast container (e.g. `172.29.10.10`).
   - `IP_ADDRESS_GATEWAY` – gateway for that network (e.g. `172.29.10.1`).
   - Passwords and ports as needed (see [Configuration](#configuration)).

3. **Run the deploy script**:

   ```bash
   chmod +x deploy.sh install-docker.sh
   ./deploy.sh
   ```

   The script will:
   - Install Docker if it is not present.
   - Create `/usr/local/bin/docker` (if missing) and `/usr/local/bin/docker/<PROJECT_NAME>/`.
   - Create log dirs under `/usr/local/bin/docker/<PROJECT_NAME>/logs/` (e.g. `icecast`, `nginx`).
   - Generate `conf/<PROJECT_NAME>.xml` (Icecast config), `conf/<PROJECT_NAME_ICECAST>.conf` (Nginx config from `conf/nginx_example.conf`), and `docker-compose.yml` in the project folder.
   - Start the stack (`docker compose up -d`), optionally add iptables rules for the project bridge, and run a quick service check (curl). At the end it prints a short summary (project path, service status, logs command).

4. **If the stack started successfully**, you're done. To view logs:

   ```bash
   cd /usr/local/bin/docker/<PROJECT_NAME>
   docker compose logs -f
   ```

   If the script reported a **start failure** (e.g. permission denied), Docker may have been just installed. Apply the new group and start manually:

   ```bash
   newgrp docker
   cd /usr/local/bin/docker/<PROJECT_NAME>
   docker compose up -d
   ```

   Or log out and back in so the `docker` group is active.

---

## Directory layout after deploy

| Path | Purpose |
|------|--------|
| `/usr/local/bin/docker/` | Base directory for all projects. Created once; owned by the user who first ran deploy. |
| `/usr/local/bin/docker/<PROJECT_NAME>/` | One folder per project (e.g. `radio`). Contains `conf/`, `logs/`, `docker-compose.yml`. |
| `/usr/local/bin/docker/<PROJECT_NAME>/conf/<PROJECT_NAME>.xml` | Icecast config generated from `conf/icecast_example.xml` and `.env`. |
| `/usr/local/bin/docker/<PROJECT_NAME>/conf/<PROJECT_NAME_ICECAST>.conf` | Nginx config generated from `conf/nginx_example.conf` and `.env` (for reverse proxy / HTTPS). |
| `/usr/local/bin/docker/<PROJECT_NAME>/logs/icecast/` | Icecast logs (owned by `1000:1000` for the container). |
| `/usr/local/bin/docker/<PROJECT_NAME>/logs/nginx/` | Reserved for nginx logs when using the nginx config. |

### Nginx and external access

Note the example **`conf/nginx_example.conf`**: the deploy script generates from it a ready-to-use config named by project (**`conf/<PROJECT_NAME_ICECAST>.conf`**), which you can use to expose the stream via a reverse proxy (e.g. under a domain with HTTPS).

**Do not forget to:**
- **Generate SSL certificates** (e.g. with Certbot/Let’s Encrypt) for your domain.
- **Open access through iptables** (or your firewall) for HTTP/HTTPS so that nginx can receive external traffic.

### Statistics: `status-json.xsl`, `xml2json.xslt`, and “only under `/admin/…`”

The files **`status-json.xsl`** and **`xml2json.xslt`** in `conf/icecast-web/` match the current **[xiph/Icecast-Server `web/`](https://github.com/xiph/Icecast-Server/tree/master)** sources (same as the `wget` commands into `/usr/local/share/icecast/web/` on a native install). In the container they are mounted over `/usr/share/icecast/web/`. They **only change how** Icecast turns internal stats XML into **JSON** and **which fields are omitted** (the extra `xsl:template` rules live in upstream `status-json.xsl`). They **do not** move the endpoint into the admin URL space and **do not** add authentication.

By default, anyone who can reach Icecast can still call **`/status-json.xsl`** (and other public stats URLs) unless you block them at **nginx** (or firewall). Icecast **2.5+** suggests migrating to **`/admin/publicstats`** (and optionally `/admin/eventfeed`) instead of relying on `/status-json.xsl` long term — that is a **built-in admin** JSON API, not the same thing as a custom nginx path like `/admin/stats`.

To serve filtered JSON **only** on a path such as **`/admin/stats`**, configure nginx yourself, for example:

1. **`location = /admin/stats`** — `proxy_pass` to `http://127.0.0.1:<PORT_ICECAST_EXTERNAL>/status-json.xsl`, plus **`auth_basic`** (or another gate) if you want login.
2. **`location = /status-json.xsl`** (and optionally **`/status.xsl`**) — **`return 404`** (or `403`) on the public `server` so clients cannot bypass your `/admin/stats` URL.

Place these `location`s so they take effect **before** the broad `location /` that proxies to Icecast in `nginx_example.conf`.

---

## Configuration

All deploy and runtime settings are read from **`.env`** in the repo directory. Use `.env.example` as a template.

### Project and Docker Compose

| Variable | Example | Description |
|----------|---------|-------------|
| `PROJECT_NAME` | `radio` | Project folder name under `/usr/local/bin/docker/` (logs live in `.../logs/` there). |
| `PORT_ICECAST_EXTERNAL` | `38000` | Host port mapped to Icecast (e.g. stream at `http://host:38000`). Default `38000`; if the port is in use, the script picks the next free one. |
| `PORT_ICECAST` | `8000` | Port used **inside** the container (leave as is unless you change the image). |
| `IP_ADDRESS` | `172.29.10.10` | Fixed IPv4 for the Icecast container. **Required.** |
| `IP_ADDRESS_GATEWAY` | `172.29.10.1` | Gateway for the container network. **Required.** |
| `SUBNET` | `172.29.10.0/24` | Docker network subnet. Optional; if unset, derived from `IP_ADDRESS` or default `172.29.10.0/24`. |

### Icecast (limits, auth, mounts)

| Variable | Example | Description |
|----------|---------|-------------|
| `PROJECT_NAME_ICECAST` | `radio` | Value for Icecast `<location>`. |
| `PROJECT_NAME_ICECAST_ADMIN` | `techit.pro` | Admin contact / login label. |
| `LIMITS_CLIENTS` | `1000` | Max clients. |
| `LIMITS_SOURCES` | `20` | Max sources. |
| `ADMIN_LOGIN` / `ADMIN_PASSWORD` | `admin` | Admin UI login. |
| `RELAY_PASSWORD` | `relay` | Relay auth. |
| `SOURCE_PASSWORD` | `source` | Source (encoder) auth. |
| `NAME_MAIN_MOUNT` | `radio` | Main mount point (e.g. `/radio`). |
| `NAME_FALLBACK_MOUNT` | `fallback` | Fallback mount. |
| `STREAM_NAME`, `STREAM_DESCRIPTION`, `STREAM_GENRE`, `STREAM_URL` | — | Shown in directory / metadata. |

---

## What the deploy script does (step by step)

1. **Loads `.env`** from the repo directory. If `.env` is missing, uses `PROJECT_NAME=radio` and continues.
2. **Docker:** If the `docker` command is missing, runs `install-docker.sh` (installs Docker from the official Ubuntu repo and adds your user to the `docker` group). If Docker is present, ensures the Docker service is started.
3. **Directories:**
   - Creates `/usr/local/bin/docker` if it does not exist and sets ownership to the current user (or `SUDO_USER` when run with sudo).
   - Creates `/usr/local/bin/docker/<PROJECT_NAME>/` and `.../conf/`.
   - Creates `/usr/local/bin/docker/<PROJECT_NAME>/logs/icecast` and `.../logs/nginx`.
4. **Ownership:** Project directory → current user; Icecast log directory → `1000:1000` (for the container).
5. **Icecast config:** Copies `conf/icecast_example.xml` to `conf/<PROJECT_NAME>.xml`, substituting all variables from `.env` (via `envsubst` if available).
6. **Icecast web:** Копирует из **`./conf/icecast-web/`** репозитория в целевой проект три файла (`status-json.xsl`, `xml2json.xslt`, `index.html`). Они хранятся в Git заранее; обновление с [xiph/Icecast-Server `web/`](https://github.com/xiph/Icecast-Server/tree/master/web) — вручную (см. [`conf/icecast-web/README.md`](conf/icecast-web/README.md)). В `docker-compose` монтируются **по одному файлу** поверх `/usr/share/icecast/web` образа (не затирая `includes/`, `style.css`, штатный `status.xsl`).
7. **Nginx config:** Copies `conf/nginx_example.conf` to `conf/<PROJECT_NAME_ICECAST>.conf`, substituting `DOMAIN_NAME`, `PROJECT_NAME`, `NAME_MAIN_MOUNT`, `NAME_FALLBACK_MOUNT`, `PORT_ICECAST_EXTERNAL` from `.env` (via `envsubst` if available). Use this file in your nginx setup to expose the stream over HTTPS.
8. **Compose:** Writes `docker-compose.yml` into the project directory with variables from `.env` replaced. Requires `IP_ADDRESS` and `IP_ADDRESS_GATEWAY` in `.env`; otherwise the script exits with an error.
9. **Start stack:** Runs `docker compose up -d` in the project directory. On success, the containers are running.
10. **Optional iptables:** If `iptables` is available and the bridge `br-<PROJECT_NAME>` exists, inserts rules to allow established/new connections from that bridge only when an identical rule is not already present (so Docker traffic is not blocked and redeploy does not stack duplicates).
11. **Service check:** If `curl` is available, requests `http://127.0.0.1:<PORT_ICECAST_EXTERNAL>/` and prints the result in a one-line summary (e.g. `200 OK` or `недоступен`). The script then prints a final block: project path, service status, and the command to view logs.

Re-running `./deploy.sh` overwrites the generated config and compose file and restarts the stack (safe for updating settings).

---

## Running and managing the stack

- **Start:**  
  The deploy script starts the stack automatically. To start manually (e.g. after `docker compose down`):  
  `cd /usr/local/bin/docker/<PROJECT_NAME>` then `docker compose up -d`
- **Stop:**  
  `docker compose down`
- **Logs:**  
  `docker compose logs -f`  
  Icecast app logs are also in `<project_dir>/logs/icecast/`.
- **Restart after config change:**  
  Edit `conf/<PROJECT_NAME>.xml` if needed, then `docker compose restart` (or re-run `./deploy.sh` from the repo and restart).

You do **not** need a `.env` file inside the project directory for `docker compose`; the generated `docker-compose.yml` already has all values substituted.

---

## Multiple projects

Use a different `PROJECT_NAME` (and matching network/IP plan) per project:

1. Copy or edit `.env` with a new `PROJECT_NAME` and a different `IP_ADDRESS` (and optionally `SUBNET` / gateway).
2. Run `./deploy.sh` again from the same repo directory.
3. A new folder `/usr/local/bin/docker/<new_project>/` and log dirs under `.../logs/` will be created, and the script will start the new stack. If the script did not start it (e.g. permission issue), run `cd /usr/local/bin/docker/<new_project> && docker compose up -d`.

---

## Troubleshooting

- **“Permission denied” when running `docker compose`**  
  Docker was likely just installed. Run `newgrp docker` or log out and back in so your user is in the `docker` group.

- **“IP_ADDRESS and IP_ADDRESS_GATEWAY must be set”**  
  Add both variables to `.env` in the repo directory and run `./deploy.sh` again.

- **Config or compose still has `${...}` placeholders**  
  Install `gettext-base` (provides `envsubst`), then re-run `./deploy.sh`. Or edit the generated files in the project directory by hand.

- **Container cannot write logs**  
  Icecast log dir (`<project_dir>/logs/icecast`) is set to `1000:1000`. If your image uses another user/UID, adjust the `chown` step in `deploy.sh` (search for `1000:1000` and the icecast log path).

---

## Repository structure

| Item | Description |
|------|-------------|
| `deploy.sh` | Main deploy script: Docker check/install, directories, permissions, Icecast config, compose, stack start, optional iptables rules for the project bridge, and a curl-based service check with a short summary. |
| `install-docker.sh` | Standalone Docker install for Ubuntu (used by `deploy.sh` when Docker is missing). |
| `.env.example` | Sample environment file; copy to `.env` and edit. |
| `conf/icecast_example.xml` | Icecast config template (variables substituted from `.env`). |
| `conf/icecast-web/` | Переопределения web + [`README.md`](conf/icecast-web/README.md) (как обновить с Xiph). При деплое копируется на хост и монтируется по файлам (шаг 6). |
| `conf/docker-compose.yml` | Compose template (variables substituted into the deployed `docker-compose.yml`). |
| `conf/nginx_example.conf` | Nginx config template; deploy generates `conf/<PROJECT_NAME_ICECAST>.conf` from it for reverse proxy / HTTPS access. |

`.env` is listed in `.gitignore` and is not committed; keep secrets and host-specific values there.

---

## License

This project is licensed under the **MIT License**. You may use, copy, modify, and distribute it under the terms of the license.

See the [LICENSE](LICENSE) file in the repository for the full text.
