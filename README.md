# RTCCM Install

Real-Time Cloud Cost Metrics — self-hosted cloud cost observability for Azure, AWS, GCP.

This repository contains the **customer install manifest** only — Docker Compose file, environment templates, collector configs, and an install script. The application source code lives in a private repository; you consume RTCCM as pre-built images from Docker Hub.

## Requirements

**Host**

- Linux with kernel 5.4+ (Ubuntu 20.04+, Debian 11+, RHEL 9+)
- Docker Engine 24.0+
- `docker compose` plugin (v2)
- `python3` (used by `install.sh` for secret generation)

**Resources**

| | Minimum | Recommended |
|---|---|---|
| CPU | 4 vCPU | 8 vCPU |
| RAM | 8 GB | 16 GB |
| Disk | **25 GB free** on the docker data root | 80+ GB |

Disk breakdown at minimum:

| Phase | Disk |
|---|---|
| Image pull + extract (`cletrics/rtccm-*:1.3.0` × 10) | ~10 GB |
| First-month postgres + clickhouse + VictoriaMetrics state | ~15 GB |
| **Total minimum free** | **~25 GB** |

Plan for 25–50 GB additional headroom per year of metric retention. `install.sh` will refuse to continue if the docker data root (`/var/lib/docker` by default) has less than 25 GB free.

**Network**

- Outbound HTTPS (443) to `hub.docker.com`, `registry-1.docker.io`, `auth.docker.io` for image pulls
- Plus the cloud APIs for whichever profiles you enable (AWS EC2/CUR/Pricing, Azure Resource Manager/Cost Management, GCP BigQuery/Cloud Billing)

**Cloud prerequisites** (one or more)

- AWS account with a Cost and Usage Report (CUR) export enabled in Parquet
- Azure AD app registration with Cost Management Reader role on each tracked subscription
- GCP service account with BigQuery read access to the billing export dataset

## Quickstart

```bash
git clone --depth 1 -b v1.3.0 https://github.com/RunAIPilot/rtccm-install.git rtccm
cd rtccm
./install.sh
```

First run creates both `.env` and `.secrets.env` from templates and exits. Edit both files, then re-run `./install.sh` to pull images and start the stack.

## Cloud profiles

RTCCM ships with per-cloud collectors gated behind Docker Compose profiles. Enable only the clouds you use:

```bash
./install.sh --profile aws
./install.sh --profile aws --profile azure
./install.sh --profile aws --profile azure --profile gcp
```

Without any profile, only the core stack (API, web UI, postgres, clickhouse, grafana, OTel gateway) starts — useful for evaluating the interface before wiring up real data sources.

## Configuration files

| File | Purpose | Contains secrets? |
|---|---|---|
| `.env` | Non-sensitive settings: version, ports, hostname, feature flags | No |
| `.secrets.env` | Passwords and API keys | **Yes** — chmod 600 |
| `secrets/postgres_password.txt` | Postgres password mirrored to file (Docker secret) | **Yes** |
| `secrets/clickhouse_password.txt` | ClickHouse password (for Grafana) | **Yes** |
| `secrets/grafana_admin_password.txt` | Auto-generated on first install | **Yes** |
| `secrets/clickhouse_encryption_key.bin` | 32-byte key for at-rest encryption | **Yes** |
| `secrets/license_token.txt` | License token (set to `trial` by default) | **Yes** |
| `secrets/{aws,azure,gcp}_credentials.{json,txt}` | Cloud credentials for collectors | **Yes** |
| `collector-config/*` | OTel collector and YACE configs (editable if needed) | No |

`install.sh` bootstraps `secrets/*` from `.secrets.env` on first run. Rotate any secret by editing `.secrets.env`, deleting the corresponding file in `secrets/`, and re-running the script.

## Cloud credential setup

### AWS
1. Enable a [Cost and Usage Report](https://docs.aws.amazon.com/cur/latest/userguide/creating-cur.html) export to S3 in Parquet format.
2. Create an IAM user with `CostExplorerReadOnlyAccess` and read access to the CUR bucket.
3. Put the credentials JSON in `secrets/aws_credentials.json`:
   ```json
   {"aws_access_key_id": "AKIA...", "aws_secret_access_key": "..."}
   ```
4. Set `AWS_REGION`, `AWS_CUR_S3_BUCKET`, `AWS_CUR_S3_PREFIX`, `AWS_CUR_REPORT_NAME` in `.env`.

### Azure
1. Register an Azure AD app and grant it the `Cost Management Reader` role on each subscription you want to track.
2. Create a client secret for the app.
3. Set `RTCCM_AZURE_SUBSCRIPTION_ID(S)`, `RTCCM_AZURE_TENANT_ID`, `RTCCM_AZURE_CLIENT_ID`, `RTCCM_AZURE_CLIENT_SECRET` in `.env`.

### GCP
1. Export billing to BigQuery ([Google docs](https://cloud.google.com/billing/docs/how-to/export-data-bigquery)).
2. Create a service account with `BigQuery Data Viewer` + `BigQuery Job User` on the billing dataset.
3. Download the service account JSON to `secrets/gcp_credentials.json`.
4. Set `GCP_PROJECT_ID` and `GCP_BILLING_DATASET` in `.env`.

## Operations

```bash
# Status
docker compose ps

# Tail logs
docker compose logs -f --tail=50 api

# Upgrade
git fetch && git checkout v1.3.1 && ./install.sh --profile aws

# Stop
docker compose down

# Stop and wipe data (destructive)
docker compose down -v
```

## First login

1. Open `http://<RTCCM_HOST>:<WEB_PORT>/` — default `http://localhost:5173/`.
2. The web UI walks you through creating the initial admin account.
3. Subsequent logins use email + password (MFA optional — toggle in `.env` with `RTCCM_MFA_SKIP`).

## Troubleshooting

**`docker compose up` fails with `INFRACOST_DB_PASSWORD must be set`**
You did not replace `CHANGEME_infracost_db_password` in `.env`. Edit the file and re-run.

**A container restarts in a loop**
```bash
docker compose logs <service> --tail=100
```
Common causes: missing env var in `.env`, wrong cloud credentials in `secrets/`, insufficient host memory. File an issue at https://github.com/RunAIPilot/rtccm-install/issues with the last 100 log lines.

**Web UI shows "setup" screen after upgrade**
The API container is not running or is restarting. Check `docker compose logs api` and confirm `cletrics/rtccm-api:<tag>` pulled successfully.

## Support

- Installation issues: https://github.com/RunAIPilot/rtccm-install/issues
- Product support: support@runaipilot.com
- Security disclosures: security@runaipilot.com

## License

RTCCM images are distributed under a commercial license with a built-in trial. See `secrets/license_token.txt`. Contact sales@runaipilot.com for production licensing.
