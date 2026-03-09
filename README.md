# Deploy-DockerIcecastRadio

One-command deploy for **Icecast** (streaming server) in Docker on a Linux host. The script sets up directories, configs, and Docker Compose so you can run an Icecast radio stack with minimal manual steps.

---

## What it does

- **Checks or installs Docker** on the host (Ubuntu: official Docker repo).
- **Creates a fixed directory layout**: projects under `/usr/local/bin/docker/<project>`, logs under `/var/log/docker/<project>/`.
- **Generates Icecast config** from a template, filled with your `.env` values.
- **Deploys a ready-to-run `docker-compose.yml`** into the project folder so you can start the stack with `docker compose up -d`.

You clone this repo on the server, fill in `.env`, run `./deploy.sh`, then start the container. No need to copy configs by hand.

---

## Prerequisites

- **Linux** (tested on Ubuntu; other Debian-based systems should work).
- **Bash** (script uses `bash`).
- **sudo** for creating directories under `/usr/local/bin` and `/var/log`, and for installing Docker if missing.
- **Optional:** `envsubst` (from `gettext-base`) for variable substitution in configs; if absent, templates are copied as-is (you’d have to edit them manually).

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
   - Create log dirs under `/var/log/docker/<PROJECT_NAME>/` (e.g. `icecast`, `nginx`).
   - Generate `conf/<PROJECT_NAME>.xml` (Icecast config) and `docker-compose.yml` in the project folder.

4. **Start Icecast**:

   ```bash
   cd /usr/local/bin/docker/<PROJECT_NAME>
   docker compose up -d
   ```

   If Docker was **just installed** by the script, you may need to apply the new group first:

   ```bash
   newgrp docker
   # then again:
   cd /usr/local/bin/docker/<PROJECT_NAME>
   docker compose up -d
   ```

   Or log out and back in so the `docker` group is active.

---

## Directory layout after deploy

| Path | Purpose |
|------|--------|
| `/usr/local/bin/docker/` | Base directory for all projects. Created once; owned by the user who first ran deploy. |
| `/usr/local/bin/docker/<PROJECT_NAME>/` | One folder per project (e.g. `radio`). Contains `conf/`, `docker-compose.yml`. |
| `/usr/local/bin/docker/<PROJECT_NAME>/conf/<PROJECT_NAME>.xml` | Icecast config generated from `conf/icecast_example.xml` and `.env`. |
| `/var/log/docker/<PROJECT_NAME>/icecast/` | Icecast logs (owned by `1000:1000` for the container). |
| `/var/log/docker/<PROJECT_NAME>/nginx/` | Reserved for future use (e.g. nginx). |

---

## Configuration

All deploy and runtime settings are read from **`.env`** in the repo directory. Use `.env.example` as a template.

### Project and Docker Compose

| Variable | Example | Description |
|----------|---------|-------------|
| `PROJECT_NAME` | `radio` | Project folder name under `/usr/local/bin/docker/` and under `/var/log/docker/`. |
| `PORT_ICECAST_EXTERNAL` | `8000` | Host port mapped to Icecast (e.g. stream at `http://host:8000`). |
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
   - Creates `/var/log/docker/<PROJECT_NAME>/icecast` and `.../nginx`.
4. **Ownership:** Project directory → current user; Icecast log directory → `1000:1000` (for the container).
5. **Icecast config:** Copies `conf/icecast_example.xml` to `conf/<PROJECT_NAME>.xml`, substituting all variables from `.env` (via `envsubst` if available).
6. **Compose:** Writes `docker-compose.yml` into the project directory with variables from `.env` replaced. Requires `IP_ADDRESS` and `IP_ADDRESS_GATEWAY` in `.env`; otherwise the script exits with an error.

Re-running `./deploy.sh` overwrites the generated config and compose file (safe for updating settings).

---

## Running and managing the stack

- **Start:**  
  `cd /usr/local/bin/docker/<PROJECT_NAME>` then `docker compose up -d`
- **Stop:**  
  `docker compose down`
- **Logs:**  
  `docker compose logs -f`  
  Icecast app logs are also in `/var/log/docker/<PROJECT_NAME>/icecast/`.
- **Restart after config change:**  
  Edit `conf/<PROJECT_NAME>.xml` if needed, then `docker compose restart` (or re-run `./deploy.sh` from the repo and restart).

You do **not** need a `.env` file inside the project directory for `docker compose`; the generated `docker-compose.yml` already has all values substituted.

---

## Multiple projects

Use a different `PROJECT_NAME` (and matching network/IP plan) per project:

1. Copy or edit `.env` with a new `PROJECT_NAME` and a different `IP_ADDRESS` (and optionally `SUBNET` / gateway).
2. Run `./deploy.sh` again from the same repo directory.
3. A new folder `/usr/local/bin/docker/<new_project>/` and new log dirs under `/var/log/docker/<new_project>/` will be created.
4. Start it with `cd /usr/local/bin/docker/<new_project> && docker compose up -d`.

---

## Troubleshooting

- **“Permission denied” when running `docker compose`**  
  Docker was likely just installed. Run `newgrp docker` or log out and back in so your user is in the `docker` group.

- **“IP_ADDRESS and IP_ADDRESS_GATEWAY must be set”**  
  Add both variables to `.env` in the repo directory and run `./deploy.sh` again.

- **Config or compose still has `${...}` placeholders**  
  Install `gettext-base` (provides `envsubst`), then re-run `./deploy.sh`. Or edit the generated files in the project directory by hand.

- **Container cannot write logs**  
  Icecast log dir is set to `1000:1000`. If your image uses another user/UID, adjust the `chown` step in `deploy.sh` (search for `1000:1000` and the icecast log path).

---

## Repository structure

| Item | Description |
|------|-------------|
| `deploy.sh` | Main deploy script: Docker check/install, directories, permissions, Icecast config, compose. |
| `install-docker.sh` | Standalone Docker install for Ubuntu (used by `deploy.sh` when Docker is missing). |
| `.env.example` | Sample environment file; copy to `.env` and edit. |
| `conf/icecast_example.xml` | Icecast config template (variables substituted from `.env`). |
| `conf/docker-compose.yml` | Compose template (variables substituted into the deployed `docker-compose.yml`). |
| `conf/nginx_example.conf` | Placeholder for future nginx use. |

`.env` is listed in `.gitignore` and is not committed; keep secrets and host-specific values there.

---

## License

This project is licensed under the **MIT License**. You may use, copy, modify, and distribute it under the terms of the license.

See the [LICENSE](LICENSE) file in the repository for the full text.
