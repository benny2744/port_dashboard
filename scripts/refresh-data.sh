#!/bin/bash
###############################################################################
# refresh-data.sh - Scans listening ports and generates JSON data
###############################################################################
set -euo pipefail

OUTPUT_DIR="/home/benny/port-dashboard/public"
DATA_FILE="${OUTPUT_DIR}/ports.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$OUTPUT_DIR"
chmod 755 "$OUTPUT_DIR"

# Get docker container info
get_docker_info() {
    docker ps --format '{{.Names}}|{{.Ports}}|{{.Label "com.docker.compose.project"}}|{{.Image}}' 2>/dev/null || true
}

# Parse ss output and correlate with docker
python3 - "$TIMESTAMP" "$DATA_FILE" <<'PYTHON'
import subprocess
import json
import re
import sys
from collections import defaultdict

timestamp = sys.argv[1]
output_file = sys.argv[2]

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.DEVNULL)
    except:
        return ""

# Get listening ports from ss
ss_out = run("ss -H -lntu")
ports_data = defaultdict(lambda: {"protocols": set(), "binds": set(), "process": None})

for line in ss_out.strip().split('\n'):
    if not line.strip():
        continue
    parts = line.split()
    if len(parts) < 5:
        continue
    proto = parts[0]
    local = parts[4]
    
    # Extract port
    m = re.search(r':(\d+)$', local)
    if not m:
        continue
    port = int(m.group(1))
    
    ports_data[port]["protocols"].add(proto)
    ports_data[port]["binds"].add(local)

# Get docker container mappings
docker_out = run("docker ps --format '{{.Names}}|{{.Ports}}|{{.Label \"com.docker.compose.project\"}}|{{.Image}}'")
container_ports = {}

for line in docker_out.strip().split('\n'):
    if not line.strip():
        continue
    parts = line.split('|')
    if len(parts) < 4:
        continue
    name, ports_str, project, image = parts
    
    # Parse port mappings like "127.0.0.1:4010->3000/tcp"
    for mapping in ports_str.split(', '):
        m = re.search(r'(?:[\d.]+|\[\:\:\])?:?(\d+)->(\d+)', mapping)
        if m:
            host_port = int(m.group(1))
            container_ports[host_port] = {
                "container": name,
                "project": project or None,
                "image": image.split(':')[0] if image else None
            }

# Known service definitions (non-docker)
known_services = {
    22: {"service": "SSH", "category": "infrastructure"},
    53: {"service": "DNS (systemd-resolved)", "category": "infrastructure"},
    80: {"service": "Nginx", "category": "web"},
    111: {"service": "RPC Portmapper", "category": "infrastructure"},
    137: {"service": "Samba (nmbd)", "category": "infrastructure"},
    138: {"service": "Samba (nmbd)", "category": "infrastructure"},
    139: {"service": "Samba (smbd)", "category": "infrastructure"},
    445: {"service": "Samba (smbd)", "category": "infrastructure"},
    1883: {"service": "MQTT Broker", "category": "infrastructure"},
    2377: {"service": "Docker Swarm Manager", "category": "docker"},
    4789: {"service": "Docker Swarm VXLAN", "category": "docker"},
    5353: {"service": "mDNS (Avahi)", "category": "infrastructure"},
    7946: {"service": "Docker Swarm Gossip", "category": "docker"},
    16443: {"service": "MicroK8s API", "category": "kubernetes"},
    25000: {"service": "MicroK8s Cluster Agent", "category": "kubernetes"},
}

# Port block assignments
port_blocks = {
    range(4010, 4020): "Debate Timer",
    range(4020, 4030): "Timer App", 
    range(4030, 4040): "Test Schedule",
    range(4040, 4050): "Dify LLM",
    range(4050, 4060): "Participation Tracker",
    range(4060, 4070): "Feedback App",
    range(4070, 4080): "Video Compressor",
    range(4080, 4090): "Capstone",
    range(4090, 4100): "ClassChat",
    range(4100, 4110): "Grading App",
    range(4110, 4120): "HR Game",
    range(4120, 4130): "n8n",
    range(4130, 4140): "EduCore",
    range(4140, 4150): "Self-Study Guidance",
    range(4150, 4160): "Verdaccio",
    range(4160, 4170): "Chat/RocketChat",
}

def get_app_name(port):
    for port_range, name in port_blocks.items():
        if port in port_range:
            return name
    return None

# Build final data
result = {
    "generated": timestamp,
    "summary": {
        "total_listening": len(ports_data),
        "docker_mapped": len(container_ports),
    },
    "ports": []
}

for port in sorted(ports_data.keys()):
    info = ports_data[port]
    entry = {
        "port": port,
        "protocols": sorted(info["protocols"]),
        "binds": sorted(info["binds"])[:5],  # Limit binds shown
        "bind_count": len(info["binds"]),
    }
    
    # Add docker info if available
    if port in container_ports:
        entry["docker"] = container_ports[port]
        entry["category"] = "docker"
        entry["app"] = container_ports[port].get("project") or container_ports[port].get("container")
    elif port in known_services:
        entry["service"] = known_services[port]["service"]
        entry["category"] = known_services[port]["category"]
        entry["app"] = known_services[port]["service"]
    else:
        app_name = get_app_name(port)
        if app_name:
            entry["app"] = app_name
            entry["category"] = "webapp"
        else:
            entry["category"] = "unknown"
            entry["app"] = "Unknown"

    result["ports"].append(entry)

# Write JSON
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Generated {output_file} with {len(result['ports'])} ports")
PYTHON

# Make output files readable by nginx container
chmod 644 "${DATA_FILE}"

echo "Data refreshed at $(date)"

