# Odoo 18 Local Development Setup

A complete, automated setup for Odoo 18 local development environment on Ubuntu/Debian systems.

## 🚀 Quick Start

```bash
# Clone this repository
git clone https://github.com/yourusername/odoo18-dev-setup.git
cd odoo18-dev-setup

# Make the setup script executable
chmod +x setup-odoo18.sh

# Run the setup script
./setup-odoo18.sh
```

The script will:
- Install all required system dependencies
- Set up PostgreSQL with your user account
- Clone Odoo 18 from the official repository
- Create a Python virtual environment
- Install Python dependencies
- Configure Odoo for development
- Create systemd service for easy management
- Set up a Makefile for simple commands

## 📋 Prerequisites

- Ubuntu 20.04+ or Debian 11+
- sudo privileges user

## 🎯 What Gets Installed

### System Packages
- Python 3 with development headers
- PostgreSQL database server
- Git and build tools
- Required libraries for Odoo (XML, image processing, etc.)

### Odoo Setup
- Odoo 18 (latest from official repository)
- Python virtual environment with all dependencies
- PostgreSQL user matching your system user
- Systemd service for automatic startup
- Configuration files in your home directory

## 🛠️ Usage

After installation, navigate to the Odoo directory and use the Makefile commands:

```bash
cd /opt/odoo
```

### Available Commands

```bash
make start          # Start Odoo as a system service
make stop           # Stop Odoo service  
make restart        # Restart Odoo service
make status         # Show service status
make logs           # Show live logs (Ctrl+C to exit)
make dev            # Start in development mode with auto-reload
make manual         # Start manually with console output
make shell          # Open Odoo shell for debugging
make test           # Test if Odoo is responding
make clean          # Stop all services including PostgreSQL
make install        # Install/update Python dependencies
make help           # Show all available commands
```

### Development Workflow

For active development:
```bash
make dev            # Starts with auto-reload, file watching
```

For manual control with console output:
```bash
make manual         # See all logs in terminal
```

For production-like testing:
```bash
make start          # Runs as background service
```

## 🌐 Access

Once started, access Odoo at: **http://localhost:8069**

### Default Credentials
- **Master Password**: `admin123`
- **Database**: Create new or use existing
- **Admin User**: Set during database creation

## 📁 File Structure

```
/opt/odoo/
├── odoo18/              # Odoo source code
├── venv/                # Python virtual environment  
├── Makefile             # Management commands
└── setup-odoo18.sh      # Setup script

~/.config/odoo/
└── odoo.conf            # Odoo configuration

~/.local/share/odoo/
├── odoo.log            # Log file
├── addons/             # Custom addons directory
└── filestore/          # File storage
```

## 🔧 Configuration

### Odoo Configuration
Located at: `~/.config/odoo/odoo.conf`

Key settings:
- Database connection settings
- Addons paths
- Log configuration
- Data directory

### PostgreSQL Access
- **Host**: localhost
- **Port**: 5432  
- **User**: Your system username
- **Password**: Set during installation

## 🚀 Development Features

### Auto-reload Development Mode
```bash
make dev
```
- Automatically reloads on Python file changes
- Reloads QWeb templates on change
- Enhanced debugging with Werkzeug
- Console output for immediate feedback

### Custom Addons
Place custom addons in:
- `/opt/odoo/odoo18/addons/` (for core development)
- `~/.local/share/odoo/addons/18.0/` (for custom addons)

Update `addons_path` in config if needed.

## 🐛 Troubleshooting

### Service Issues
```bash
make status                    # Check what's running
sudo journalctl -u odoo -f     # View detailed logs
make restart                   # Restart services
```

### Database Issues
```bash
# Test PostgreSQL connection
psql -h localhost -U $USER -d postgres

# Reset database (if needed)
# This will delete all data!
sudo -u postgres dropdb your_database_name
```

### Permission Issues
```bash
# Fix ownership if needed
sudo chown -R $USER:$USER /opt/odoo
sudo chown -R $USER:$USER ~/.local/share/odoo
```

### Port Issues
```bash
# Check what's using port 8069
ss -tlnp | grep 8069

# Kill any conflicting processes
sudo pkill -f odoo-bin
```

## 🔄 Updates

### Update Odoo
```bash
cd /opt/odoo/odoo18
git pull origin 18.0
cd ..
make install    # Update dependencies if needed
make restart    # Restart with new code
```

### Update Dependencies
```bash
make install
```

## 🚫 Uninstall

To completely remove the installation:

```bash
# Stop services
make clean

# Remove systemd service
sudo systemctl disable odoo
sudo rm /etc/systemd/system/odoo.service
sudo systemctl daemon-reload

# Remove files
sudo rm -rf /opt/odoo
rm -rf ~/.config/odoo
rm -rf ~/.local/share/odoo

# Optionally remove PostgreSQL user
sudo -u postgres dropuser $USER
```

## 📝 Notes

- The setup uses your system user instead of a dedicated `odoo` user for easier development
- PostgreSQL remains running after `make stop` - use `make clean` to stop everything
- Configuration files are in your home directory for easy access
- All data is stored in `~/.local/share/odoo/`

## 🤝 Contributing

Feel free to submit issues and pull requests to improve this setup script.

## 📄 License

This setup script is provided under the MIT License. Odoo itself is licensed under LGPL v3.
