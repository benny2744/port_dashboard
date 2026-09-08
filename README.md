# Port Status Dashboard

A real-time web dashboard for monitoring listening ports on your system, with automatic Docker container correlation and port allocation management.

## Features

- 🔍 **Automatic Port Scanning**: Scans all listening ports using `ss` command
- 🐳 **Docker Integration**: Automatically correlates ports with Docker containers
- ☁️ **Cloudflared Integration**: Parses Cloudflared `ingress` routes to show tunnel origin ports (even if not exposed on the host)
- 📊 **Visual Dashboard**: Beautiful, modern web interface with filtering and search
- 🔄 **Auto-Refresh**: Hourly updates via systemd timer
- 📋 **Port Allocation Management**: Tracks reserved port blocks (4000 range) for application deployment
- 🌐 **Multi-language Support**: English and Chinese instructions

## Screenshots

The dashboard displays:
- Summary statistics (Docker containers, infrastructure, web apps, unidentified ports)
- Filterable port table with expandable port groups
- Port allocation legend showing reserved blocks
- Real-time data refresh

## Requirements

- Linux system with `ss` command
- Docker and Docker Compose
- Python 3
- systemd (for automatic refresh)
- Nginx (optional, for reverse proxy)

## Installation

1. Clone the repository:
```bash
git clone git@github.com:benny2744/port_dashboard.git
cd port_dashboard
```

2. Run the setup script:
```bash
./setup.sh
```

The setup script will:
- Make the refresh script executable
- Generate initial port data
- Start the web server container
- Provide instructions for systemd timer installation

3. Install the systemd timer (optional, for automatic hourly refresh):
```bash
sudo cp systemd/port-dashboard-refresh.service /etc/systemd/system/
sudo cp systemd/port-dashboard-refresh.timer /etc/systemd/system/
echo "PORT_DASHBOARD_DIR=/absolute/path/to/port_dashboard" | sudo tee /etc/default/port-dashboard >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable --now port-dashboard-refresh.timer
```

## Usage

### Access the Dashboard

After setup, access the dashboard at:
- **Public (this host)**: https://hsapp.yungu.org/ports/
- **Loopback** (Caddy upstream): http://127.0.0.1:3005/

Compose binds `127.0.0.1:3005` only — do not publish `:3005` on the LAN.

### Manual Data Refresh

To manually refresh port data:
```bash
./scripts/refresh-data.sh
```

### Docker Management

Start/stop the dashboard:
```bash
docker compose up -d    # Start
docker compose down      # Stop
docker compose logs -f   # View logs
```

## Port Allocation Rules

The dashboard helps manage port allocation for development servers:

- **Port Range**: All dev servers use ports in the `4000` range
- **Block Size**: Each application is allocated a block of `10 ports`
- **Increment**: Each new app increments by 10 (e.g., 4010, 4020, 4030...)
- **Service Distribution**: Keep all services for one app within its 10-port block
  - Main gateway/frontend uses `x0`
  - Backend/API uses `x1`
  - Database uses `x2`
  - etc.

### Reserved Port Blocks

Reserved blocks are configured per-server in `config/port-dashboard.json` (this file is gitignored).
Copy `config/port-dashboard.example.json` and customize it for your environment.

Example:

| Port Range | Application |
|------------|-------------|
| 4010-4019  | example-app-a |
| 4020-4029  | example-app-b |

## Project Structure

```
port-dashboard/
├── config/
│   └── port-dashboard.example.json   # Example per-server config (copy to port-dashboard.json)
├── docker-compose.yml          # Docker Compose configuration
├── ports.nginx.conf            # Nginx reverse proxy config
├── setup.sh                    # Installation script
├── scripts/
│   └── refresh-data.sh         # Port scanning and data generation script
├── systemd/
│   ├── port-dashboard-refresh.service  # Systemd service unit
│   └── port-dashboard-refresh.timer    # Systemd timer unit
└── public/
    ├── index.html              # Dashboard web interface
    └── ports.json              # Generated port data (auto-generated, gitignored)
```

## How It Works

1. **Data Collection**: The `refresh-data.sh` script:
   - Uses `ss -lntu` to scan listening ports
   - Queries Docker for container port mappings
   - Correlates ports with known services and Docker containers
   - Generates `public/ports.json` with structured data

2. **Web Interface**: The dashboard (`public/index.html`):
   - Loads port data from `ports.json`
   - Displays ports in a filterable, searchable table
   - Groups ports by 10-port blocks
   - Shows Docker container information
   - Auto-refreshes every 5 minutes

3. **Serving**: Nginx container serves the static files from `public/`

## Configuration

### Customizing Port Blocks

Create `config/port-dashboard.json` to match this server (copy from `config/port-dashboard.example.json`):

- **`scan.min_port`**: Minimum port to include in the dashboard (set to `0` to show everything).
  - You can also override this at runtime with `MIN_PORT`, e.g. `MIN_PORT=3000 ./scripts/refresh-data.sh`
- **`cloudflared.config_path`**: Path to a Cloudflared config (`config.yml`) to parse `ingress` routes and show their local origin ports.
- **`reserved_port_blocks`**: Reserved 10-port blocks for your apps, e.g. `"4020-4029": "example-app"`

If you want to tweak built-in service labels, edit the `known_services` mapping in `scripts/refresh-data.sh`.

### Changing Port

To change the dashboard's listening port, edit `docker-compose.yml`:
```yaml
ports:
  - "127.0.0.1:YOUR_PORT:80"
```

### Nginx Reverse Proxy

The `ports.nginx.conf` file can be included in your main Nginx configuration to serve the dashboard at `/ports/`.

## Troubleshooting

### Dashboard shows "Failed to load port data"
- Run `./scripts/refresh-data.sh` manually to generate the data file
- Check file permissions: `chmod 644 public/ports.json`

### Ports not updating
- Check systemd timer status: `systemctl status port-dashboard-refresh.timer`
- Check service logs: `journalctl -u port-dashboard-refresh.service`
- Verify timer is enabled: `systemctl is-enabled port-dashboard-refresh.timer`

### Docker containers not detected
- Ensure Docker is running: `docker ps`
- Check that containers have port mappings: `docker ps --format '{{.Names}}|{{.Ports}}'`

## License

This project is open source and available for use.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

