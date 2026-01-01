#!/bin/bash
###############################################################################
# refresh-data.sh - Scans listening ports and generates JSON data
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/../public"
DATA_FILE="${OUTPUT_DIR}/ports.json"
CONFIG_FILE="${SCRIPT_DIR}/../config/port-dashboard.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

mkdir -p "$OUTPUT_DIR"
chmod 755 "$OUTPUT_DIR"

# Get docker container info
get_docker_info() {
    docker ps --format '{{.Names}}|{{.Ports}}|{{.Label "com.docker.compose.project"}}|{{.Image}}' 2>/dev/null || true
}

# Parse ss output and correlate with docker
python3 - "$TIMESTAMP" "$DATA_FILE" "$CONFIG_FILE" <<'PYTHON'
import subprocess
import json
import os
import re
import sys
from collections import defaultdict
from urllib.parse import urlparse

timestamp = sys.argv[1]
output_file = sys.argv[2]
config_file = sys.argv[3] if len(sys.argv) > 3 else None

def parse_int_env(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        return default

def load_json_file(path: str):
    if not path:
        return {}
    try:
        with open(path, "r") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}
    except Exception:
        return {}

def normalize_port_blocks(raw):
    """
    Accepts either:
      - dict like {"4020-4029": "grading_app"}
      - list like [{"start": 4020, "end": 4029, "name": "grading_app"}]
    Returns a dict {"start-end": "name"}.
    """
    if not raw:
        return {}
    if isinstance(raw, dict):
        out = {}
        for k, v in raw.items():
            if k is None or v is None:
                continue
            out[str(k)] = str(v)
        return out
    if isinstance(raw, list):
        out = {}
        for item in raw:
            if not isinstance(item, dict):
                continue
            start = item.get("start")
            end = item.get("end")
            name = item.get("name") or item.get("label") or item.get("app")
            if start is None or end is None or name is None:
                continue
            try:
                start_i = int(start)
                end_i = int(end)
            except Exception:
                continue
            out[f"{start_i}-{end_i}"] = str(name)
        return out
    return {}

config = load_json_file(config_file)

def parse_scan_min_port(cfg: dict) -> int:
    try:
        scan = cfg.get("scan") or {}
        return int(scan.get("min_port", 0))
    except Exception:
        return 0

# Minimum port to include in results:
# - MIN_PORT env var overrides config.scan.min_port
min_port_env = parse_int_env("MIN_PORT", -1)
config_min_port = max(0, parse_scan_min_port(config))
min_port = max(0, min_port_env if min_port_env >= 0 else config_min_port)

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
    
    # Apply minimum port filter
    if port < min_port:
        continue
    
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
            # Apply minimum port filter
            if host_port < min_port:
                continue
            container_ports[host_port] = {
                "container": name,
                "project": project or None,
                "image": image.split(':')[0] if image else None
            }

def load_text_file(path: str):
    try:
        with open(path, "r") as f:
            return f.read()
    except FileNotFoundError:
        return None
    except Exception:
        return None

def parse_cloudflared_ingress_yaml(text: str):
    """
    Minimal YAML parser for the subset of cloudflared config we care about:

    ingress:
      - hostname: example.com
        path: /api/*
        service: http://localhost:3000
      - service: http_status:404
    """
    in_ingress = False
    routes = []
    current = None

    for raw_line in text.splitlines():
        line = raw_line.rstrip("\n")
        stripped = line.strip()

        if not stripped or stripped.startswith("#"):
            continue

        if stripped == "ingress:":
            in_ingress = True
            continue

        if not in_ingress:
            continue

        # If we hit a new top-level key, stop parsing ingress
        if line and not line.startswith((" ", "\t")) and stripped.endswith(":"):
            break

        # Start of a new list item
        if stripped.startswith("- "):
            if current:
                routes.append(current)
            current = {}
            rest = stripped[2:].strip()
            if rest and ":" in rest:
                k, v = rest.split(":", 1)
                current[k.strip()] = v.strip()
            continue

        # Continuation fields for current item
        if current is None:
            continue
        if ":" not in stripped:
            continue
        k, v = stripped.split(":", 1)
        current[k.strip()] = v.strip()

    if current:
        routes.append(current)

    return routes

def parse_cloudflared_service(service: str):
    if not service:
        return None
    s = service.strip().strip('"').strip("'")
    if "://" not in s:
        return None
    parsed = urlparse(s)
    scheme = parsed.scheme
    host = parsed.hostname
    port = parsed.port
    if port is None:
        default_ports = {"http": 80, "https": 443, "ssh": 22}
        port = default_ports.get(scheme)
    return {
        "scheme": scheme,
        "target_host": host,
        "target_port": port,
        "service": s,
    }

def is_localhost(host: str | None) -> bool:
    return host in (None, "", "localhost", "127.0.0.1", "::1")

def get_cloudflared_config_path(cfg: dict) -> str:
    cloudflared_cfg = cfg.get("cloudflared") or {}
    if isinstance(cloudflared_cfg, dict):
        path = cloudflared_cfg.get("config_path")
        if isinstance(path, str) and path.strip():
            return path.strip()
    return "/etc/cloudflared/config.yml"

cfg = config if isinstance(config, dict) else {}
cloudflared_config_path = get_cloudflared_config_path(cfg)
cloudflared_raw = load_text_file(cloudflared_config_path)

cloudflared_routes = []
if cloudflared_raw:
    for item in parse_cloudflared_ingress_yaml(cloudflared_raw):
        service = item.get("service")
        parsed = parse_cloudflared_service(service)
        if not parsed:
            continue
        port = parsed.get("target_port")
        if port is None:
            continue
        try:
            port_i = int(port)
        except Exception:
            continue

        # Apply minimum port filter
        if port_i < min_port:
            continue

        cloudflared_routes.append({
            "hostname": item.get("hostname"),
            "path": item.get("path"),
            **parsed,
            "target_port": port_i,
        })

cloudflared_by_port = defaultdict(list)
for r in cloudflared_routes:
    if is_localhost(r.get("target_host")):
        cloudflared_by_port[r["target_port"]].append({
            "hostname": r.get("hostname"),
            "path": r.get("path"),
            "service": r.get("service"),
            "scheme": r.get("scheme"),
        })

# Known service definitions (non-docker)
known_services = {
    22: {"service": "SSH", "category": "infrastructure"},
    53: {"service": "DNS", "category": "infrastructure"},
    67: {"service": "DHCP (dnsmasq/libvirt)", "category": "infrastructure"},
    323: {"service": "NTP (chronyd)", "category": "infrastructure"},
    631: {"service": "CUPS / IPP", "category": "infrastructure"},
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

def detect_port_blocks_from_docker(container_ports: dict) -> dict:
    """
    Derive port-block labels from docker-compose projects currently publishing ports.
    By default, we focus on 4000-range blocks (common dev allocation convention).
    """
    block_counts: dict[str, dict[str, int]] = {}

    for host_port, info in container_ports.items():
        if host_port < 4000 or host_port >= 5000:
            continue
        block_start = (host_port // 10) * 10
        range_key = f"{block_start}-{block_start + 9}"
        label = info.get("project") or info.get("container") or "Unknown"

        block_counts.setdefault(range_key, {})
        block_counts[range_key][label] = block_counts[range_key].get(label, 0) + 1

    detected: dict[str, str] = {}
    for range_key, counts in block_counts.items():
        detected[range_key] = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
    return detected

def parse_range_key(range_key: str):
    try:
        start_s, end_s = range_key.split("-", 1)
        return int(start_s), int(end_s)
    except Exception:
        return None

config_port_blocks = normalize_port_blocks(cfg.get("reserved_port_blocks") or cfg.get("port_blocks") or {})
detected_port_blocks = detect_port_blocks_from_docker(container_ports)

# Merge: detected first (makes the dashboard immediately relevant on a new server),
# then config overrides/adds.
port_blocks_json = {**detected_port_blocks, **config_port_blocks}

port_block_ranges = []
for range_key, name in port_blocks_json.items():
    parsed = parse_range_key(range_key)
    if not parsed:
        continue
    start, end = parsed
    port_block_ranges.append((start, end, name))
port_block_ranges.sort(key=lambda t: (t[0], t[1]))

def get_app_name(port: int):
    for start, end, name in port_block_ranges:
        if start <= port <= end:
            return name
    return None

# Build final data
result = {
    "generated": timestamp,
    "summary": {
        "total_listening": len(ports_data),
        "docker_mapped": len(container_ports),
        "cloudflared_routes": len(cloudflared_routes),
    },
    "port_blocks": port_blocks_json,
    "cloudflared": {
        "config_path": cloudflared_config_path,
        "routes": cloudflared_routes,
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

    # Attach cloudflared routes (if configured) for localhost targets
    if port in cloudflared_by_port:
        entry["cloudflared"] = cloudflared_by_port[port]

    result["ports"].append(entry)

# Add cloudflared-only ports (configured in cloudflared, but not currently listening on host)
for port in sorted(cloudflared_by_port.keys()):
    if port in ports_data:
        continue
    routes = cloudflared_by_port[port]
    hostnames = [r.get("hostname") for r in routes if r.get("hostname")]
    app_label = hostnames[0] if hostnames else "Cloudflared"
    binds = []
    for r in routes:
        hn = r.get("hostname") or "*"
        path = r.get("path") or ""
        svc = r.get("service") or ""
        binds.append(f"cloudflared {hn}{path} -> {svc}")

    protocols = sorted({r.get("scheme") for r in routes if r.get("scheme")} or {"cloudflared"})

    result["ports"].append({
        "port": port,
        "protocols": protocols,
        "binds": binds[:5],
        "bind_count": len(binds),
        "category": "cloudflared",
        "app": app_label,
        "cloudflared": routes,
    })

# Write JSON
with open(output_file, 'w') as f:
    json.dump(result, f, indent=2)

print(f"Generated {output_file} with {len(result['ports'])} ports")
PYTHON

# Make output files readable by nginx container
chmod 644 "${DATA_FILE}"

echo "Data refreshed at $(date)"

