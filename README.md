# Mautic

Mautic is the open-source marketing automation platform — the self-hosted alternative to HubSpot and Mailchimp. Track contacts, build segments, design emails, and run multi-step campaigns with lead scoring, all on infrastructure you control. One click deploys the official image (mautic/mautic v7.2.2, GPL-3.0) with a MySQL 8 companion: the admin account is seeded on first boot, Mautic's own cron jobs run in-container, and contacts, segments, and media survive redeploys on a Railway volume.

![Mautic dashboard with email chart and contact map](assets/mautic-dashboard.jpg)

Screenshot: upstream Mautic documentation (mautic/documentation, `en/dashboard/media/add-widget.jpg`) — the dashboard with the sent/read email chart and the contact map. The deployed UI is Mautic 7.2.2.

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.com/deploy/mautic?utm_campaign=mautic)

## Source Repository

[https://github.com/INAPP-Mobile/mautic](https://github.com/INAPP-Mobile/mautic)

## Deploy and Host

One click deploys Mautic 7.2.2 (official `mautic/mautic` image, pinned by digest) plus a MySQL 8.0 companion service. The deploy form has one generated field — an admin password — and nothing else to fill in. On first boot the admin account (`admin` / `admin@example.com` + your generated password) is created automatically by the `mautic:install` CLI, the REST API is enabled for the admin credentials, and the site URL is derived from the live public domain. Log in and start with Contacts: add a contact, put it in a segment, and build your first campaign.

## Why Deploy

- **Zero-fuss start:** no setup wizard to click through, no email step — the admin account is seeded on first boot and the cron jobs that make segments and campaigns fire are already running.
- **Real marketing automation:** contacts, segments, emails, campaigns, lead scoring, forms, landing pages, and reports — the full platform, not a demo.
- **Always-on by design:** PHP + MySQL with the upstream cron schedule (segments and campaigns every 15 minutes) running in-container, so automations fire without a second service.
- **Private by default:** your contact data stays on your own volume and database; no third-party marketing cloud sees it.

## Common Use Cases

- Replace Mailchimp/HubSpot with a self-hosted newsletter + automation stack you own outright.
- Capture leads with Mautic forms and landing pages, score them, and nurture them with drip campaigns.
- Segment contacts by behavior or fields and send targeted broadcasts without per-contact pricing.
- Track anonymous visitors and identify them when they convert, with the full contact timeline.

## Configuration

| Variable | Default | What it does |
|---|---|---|
| `MAUTIC_ADMIN_PASSWORD` | `${{secret(16)}}` (generated) | Password for the auto-seeded admin account (username `admin`, email `admin@example.com`). |
| `MAUTIC_DB_HOST` | `${{mysql.RAILWAY_PRIVATE_DOMAIN}}` | MySQL host, auto-wired from the companion service over the private network. |
| `MAUTIC_DB_PORT` | `3306` (baked) | MySQL port. |
| `MAUTIC_DB_DATABASE` | `mautic` (baked) | MySQL database. |
| `MAUTIC_DB_USER` | `mautic` (baked) | MySQL user. |
| `MAUTIC_DB_PASSWORD` | `${{mysql.MYSQL_PASSWORD}}` | MySQL password, auto-wired from the companion service. |
| `MYSQL_ROOT_PASSWORD` | `${{secret(32)}}` (generated, mysql service) | MySQL root password. |
| `MYSQL_PASSWORD` | `${{secret(32)}}` (generated, mysql service) | MySQL password for the `mautic` user. |
| `MAUTIC_MAILER_DSN` | — (optional) | SMTP transport for sending email, e.g. `smtp://user:pass@smtp.example.com:587`. Without it, Mautic can track and segment but cannot send. |
| `MAUTIC_SITE_URL` | derived at boot from `RAILWAY_PUBLIC_DOMAIN` | Public URL Mautic uses for tracking pixels and email links. Set explicitly only if you serve it behind a custom domain. |
| `PHP_INI_VALUE_MEMORY_LIMIT` | `512M` (image default) | PHP memory limit; raise for large imports. |
| `PHP_INI_VALUE_UPLOAD_MAX_FILESIZE` | `512M` (image default) | Max upload size. |
| `PHP_INI_VALUE_MAX_EXECUTION_TIME` | `300` (image default) | Max PHP execution time, seconds. |
| `DOCKER_MAUTIC_ROLE` | `mautic_web` (image default) | Container role (`mautic_web`, `mautic_cron`, `mautic_worker`). This template runs web + cron in one service; leave it alone. |
| `DOCKER_MAUTIC_LOAD_TEST_DATA` | `false` (image default) | Load demo fixtures on install. Leave `false` — it overwrites the seeded admin credentials. |
| `PORT` | injected by Railway | Mapped onto Apache on every boot. |

Any other Mautic setting can be set as an environment variable with the `MAUTIC_` prefix (see the [upstream image README](https://github.com/mautic/docker-mautic#readme)). The REST API is enabled on first boot (`api_enabled=1` in `local.php`); use HTTP Basic auth with the admin credentials against `/api/contacts`, `/api/segments`, `/api/campaigns`, and the other endpoints documented at [developer.mautic.org](https://developer.mautic.org/).

### Deployment Dependencies

- **Runtime:** Mautic 7.2.2 (PHP 8.4 + Apache) + MySQL 8.0 companion; ~512 MB PHP limit, MySQL ~128 MB buffer pool. Fits the Hobby plan.
- **Port:** 8080 by default, mapped from Railway's injected `PORT` onto Apache on every boot.
- **Persistence:** one Railway volume at `/data` (Mautic config `local.php`, logs, uploaded media/files + images) and one volume at `/var/lib/mysql` (MySQL data). Both survive redeploys.
- **Healthcheck:** `/s/login` (unauthenticated, 200 — the login page). The app root `/` redirects to it, so it cannot be the platform probe.
- **Plan tier:** Hobby plan; two services (mautic + mysql).
