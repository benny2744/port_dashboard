# Port Status Dashboard

A real-time web dashboard for monitoring listening ports on your system, with automatic Docker container correlation and port allocation management.

## Features

- 🔍 **Automatic Port Scanning**: Scans all listening ports using `ss` command
- 🐳 **Docker Integration**: Automatically correlates ports with Docker containers
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
sudo systemctl daemon-reload
sudo systemctl enable --now port-dashboard-refresh.timer
```

## Usage

### Access the Dashboard

After setup, access the dashboard at:
- **Direct**: http://127.0.0.1:3005/
- **Via Nginx** (if configured): http://hsapp.yungu.org/ports/

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

| Port Range | Application |
|------------|-------------|
| 4010-4019 | Debate Timer / 辩论计时器 |
| 4020-4029 | Timer App / 定时器 |
| 4030-4039 | Test Schedule / 考试安排 |
| 4040-4049 | Dify LLM / Dify 大模型 |
| 4050-4059 | Participation Tracker / 参与度追踪 |
| 4060-4069 | Feedback App / 反馈系统 |
| 4070-4079 | Video Compressor / 视频压缩 |
| 4080-4089 | Capstone / 毕业设计 |
| 4090-4099 | ClassChat / 班级聊天 |
| 4100-4109 | Grading App / 评分系统 |
| 4110-4119 | HR Game / 人力资源游戏 |
| 4120-4129 | n8n / 自动化平台 |
| 4130-4139 | EduCore / 教育核心 |
| 4140-4149 | Self-Study Guidance / 学会学习 |
| 4150-4159 | Verdaccio / NPM 仓库 |
| 4160-4169 | Chat/RocketChat / 聊天服务 |

## Project Structure

```
port-dashboard/
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
    └── ports.json              # Generated port data (auto-generated)
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

Edit `scripts/refresh-data.sh` to modify:
- Known service definitions (lines 82-98)
- Port block assignments (lines 101-118)

### Changing Port

To change the dashboard's listening port, edit `docker-compose.yml`:
```yaml
ports:
  - "0.0.0.0:YOUR_PORT:80"
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

