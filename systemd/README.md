# Systemd Service Files

These service files allow vNode instances to start automatically on boot.

## Installation

### For User Services (Recommended)

```bash
# Copy service files
mkdir -p ~/.config/systemd/user/
cp systemd/vnode@.service ~/.config/systemd/user/
cp systemd/vnode.target ~/.config/systemd/user/

# Enable linger (allows user services to run at boot)
sudo loginctl enable-linger $USER

# Enable and start an instance
systemctl --user enable vnode@us-east
systemctl --user start vnode@us-east

# Check status
systemctl --user status vnode@us-east
```

### For System Services (Multi-User)

```bash
# Copy service files (requires root)
sudo cp systemd/vnode@.service /etc/systemd/system/
sudo cp systemd/vnode.target /etc/systemd/system/

# Edit service file to use correct paths
sudo systemctl edit vnode@.service
# Add:
[Service]
WorkingDirectory=/var/lib/vnode/instances/%i

# Enable and start
sudo systemctl enable vnode@us-east
sudo systemctl start vnode@us-east

# Check status
sudo systemctl status vnode@us-east
```

## Usage

### Enable Instance on Boot

```bash
# User service
systemctl --user enable vnode@<instance-name>

# System service
sudo systemctl enable vnode@<instance-name>
```

### Manual Control

```bash
# Start
systemctl --user start vnode@<instance-name>

# Stop
systemctl --user stop vnode@<instance-name>

# Restart
systemctl --user restart vnode@<instance-name>

# Status
systemctl --user status vnode@<instance-name>

# View logs
journalctl --user -u vnode@<instance-name> -f
```

### Enable All Instances

```bash
# Enable the target (enables all vnode instances)
systemctl --user enable vnode.target
```

## Integration with vNode CLI

The vNode CLI can manage systemd services:

```bash
# This will be added in a future update
vnode systemd enable <instance-name>
vnode systemd disable <instance-name>
vnode systemd status <instance-name>
```

## Troubleshooting

### Service Won't Start

Check logs:
```bash
journalctl --user -u vnode@<instance-name> -n 50
```

Common issues:
- Docker not running: `systemctl status docker`
- Incorrect paths in service file
- .env file missing or invalid

### Docker Compose Command Not Found

Edit the service file to use full path:
```bash
systemctl --user edit vnode@.service
```

Add:
```ini
[Service]
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose stop
```

Or use Docker Compose plugin:
```ini
[Service]
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose stop
```
