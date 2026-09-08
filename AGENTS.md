# Agent conventions — Port dashboard

Host conventions: `/home/benny/agent/AGENTS.md`.

## Production on YGappServer

- Public origin: **https://hsapp.yungu.org/ports/** (DigiCert `*.yungu.org`).
- Compose binds **127.0.0.1:3005** only. Do not publish `:3005` on the LAN.
- `public/ports.json` is generated data; do not treat refresh-script churn
  as a TLS change.
- After bind or Caddy `/ports` edits:
  `python3 ~/agent/scripts/check-hsapp-https.py`.
