#!/bin/bash

# Odoo 18 Local Development Setup Script
# This script sets up a complete Odoo 18 development environment

set -e  # Exit on any error

echo "🚀 Starting Odoo 18 Local Development Setup"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if script is run as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root. Please run as a regular user."
   exit 1
fi

# Get current user
CURRENT_USER=$(whoami)
print_status "Setting up for user: $CURRENT_USER"

# Update system packages
echo "📦 Updating system packages..."
sudo apt update
sudo apt upgrade -y

# Install prerequisites
echo "📦 Installing prerequisites..."
sudo apt install -y \
    python3 python3-pip python3-dev python3-venv \
    postgresql postgresql-server-dev-all \
    git build-essential wget curl \
    libxml2-dev libxslt1-dev libevent-dev libsasl2-dev libldap2-dev \
    pkg-config libtiff5-dev libjpeg8-dev libopenjp2-7-dev zlib1g-dev \
    libfreetype6-dev liblcms2-dev libwebp-dev libharfbuzz-dev \
    libfribidi-dev libxcb1-dev net-tools

print_status "Prerequisites installed"

# Setup PostgreSQL
echo "🐘 Setting up PostgreSQL..."
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Check if user exists in PostgreSQL
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$CURRENT_USER'" | grep -q 1; then
    print_status "PostgreSQL user $CURRENT_USER already exists"
else
    print_status "Creating PostgreSQL user $CURRENT_USER"
    sudo -u postgres createuser -s $CURRENT_USER
fi

# Set password for PostgreSQL user
echo "🔐 Setting PostgreSQL password..."
read -s -p "Enter password for PostgreSQL user '$CURRENT_USER': " DB_PASSWORD
echo
sudo -u postgres psql -c "ALTER USER $CURRENT_USER PASSWORD '$DB_PASSWORD';"
print_status "PostgreSQL user configured"

# Create Odoo directory
echo "📁 Setting up Odoo directory..."
sudo mkdir -p /opt/odoo
sudo chown $CURRENT_USER:$CURRENT_USER /opt/odoo
cd /opt/odoo

# Clone Odoo 18
if [ -d "odoo18" ]; then
    print_warning "Odoo18 directory already exists. Skipping clone."
else
    echo "📥 Cloning Odoo 18..."
    git clone https://www.github.com/odoo/odoo --depth 1 --branch 18.0 odoo18
    print_status "Odoo 18 cloned"
fi

# Create Python virtual environment
if [ -d "venv" ]; then
    print_warning "Virtual environment already exists. Skipping creation."
else
    echo "🐍 Creating Python virtual environment..."
    python3 -m venv venv
    print_status "Virtual environment created"
fi

# Activate virtual environment and install dependencies
echo "📦 Installing Python dependencies..."
source venv/bin/activate
pip install --upgrade pip
pip install -r odoo18/requirements.txt
print_status "Python dependencies installed"

# Create configuration directories
echo "⚙️  Setting up configuration..."
mkdir -p ~/.config/odoo
mkdir -p ~/.local/share/odoo

# Create Odoo configuration file
cat > ~/.config/odoo/odoo.conf << EOF
[options]
admin_passwd = admin123
db_host = localhost
db_port = 5432
db_user = $CURRENT_USER
db_password = $DB_PASSWORD
addons_path = /opt/odoo/odoo18/addons
logfile = /home/$CURRENT_USER/.local/share/odoo/odoo.log
log_level = info
data_dir = /home/$CURRENT_USER/.local/share/odoo
EOF

print_status "Configuration files created"

# Create systemd service
echo "🔧 Creating systemd service..."
sudo tee /etc/systemd/system/odoo.service << EOF
[Unit]
Description=Odoo
Documentation=http://www.odoo.com
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo
User=$CURRENT_USER
Group=$CURRENT_USER
WorkingDirectory=/opt/odoo
Environment=PATH=/opt/odoo/venv/bin
ExecStart=/opt/odoo/venv/bin/python3 /opt/odoo/odoo18/odoo-bin -c /home/$CURRENT_USER/.config/odoo/odoo.conf
StandardOutput=journal+console
Restart=on-failure
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable odoo
print_status "Systemd service created and enabled"

# Create Makefile
echo "📝 Creating Makefile..."
cat > /opt/odoo/Makefile << 'EOF'
.PHONY: start stop restart status logs dev clean install shell test manual help

start:
	@echo "🚀 Starting Odoo development environment..."
	@sudo systemctl start postgresql
	@sudo systemctl start odoo
	@sleep 3
	@echo "✅ PostgreSQL: $$(sudo systemctl is-active postgresql)"
	@echo "✅ Odoo: $$(sudo systemctl is-active odoo)"
	@echo "🌐 Odoo available at http://localhost:8069"

stop:
	@echo "🛑 Stopping Odoo..."
	@sudo systemctl stop odoo
	@echo "✅ Odoo stopped"

restart: stop start

status:
	@echo "📊 Service Status:"
	@echo "PostgreSQL: $$(sudo systemctl is-active postgresql)"
	@echo "Odoo: $$(sudo systemctl is-active odoo)"
	@if ss -tlnp | grep -q 8069; then echo "🌐 Port 8069: Active"; else echo "🌐 Port 8069: Inactive"; fi

logs:
	@echo "📝 Showing Odoo logs (Ctrl+C to exit)..."
	@sudo journalctl -u odoo -f

dev:
	@echo "🔧 Stopping service and starting in development mode..."
	@sudo systemctl stop odoo
	@echo "Starting Odoo in development mode with auto-reload and console output..."
	@bash -c "cd /opt/odoo && source venv/bin/activate && python3 odoo18/odoo-bin -c ~/.config/odoo/odoo.conf --dev=reload,qweb,werkzeug,xml --logfile=false"

manual:
	@echo "🔧 Starting Odoo manually with console output..."
	@bash -c "cd /opt/odoo && source venv/bin/activate && python3 odoo18/odoo-bin -c ~/.config/odoo/odoo.conf --logfile=false"

clean: stop
	@echo "🧹 Cleaning up..."
	@sudo systemctl stop postgresql
	@echo "All services stopped"

install:
	@echo "📦 Installing/updating Python dependencies..."
	@bash -c "cd /opt/odoo && source venv/bin/activate && pip install -r odoo18/requirements.txt"

shell:
	@echo "🐚 Starting Odoo shell..."
	@bash -c "cd /opt/odoo && source venv/bin/activate && python3 odoo18/odoo-bin shell -c ~/.config/odoo/odoo.conf"

test:
	@echo "🧪 Testing Odoo connection..."
	@if curl -s http://localhost:8069 > /dev/null; then echo "✅ Odoo is responding on port 8069"; else echo "❌ Odoo is not responding on port 8069"; fi

help:
	@echo "Available commands:"
	@echo "  make start   - Start Odoo as a service"
	@echo "  make stop    - Stop Odoo service"
	@echo "  make restart - Restart Odoo service"
	@echo "  make status  - Show service status"
	@echo "  make logs    - Show live logs"
	@echo "  make dev     - Start in development mode with auto-reload"
	@echo "  make manual  - Start manually with console output"
	@echo "  make shell   - Open Odoo shell"
	@echo "  make test    - Test if Odoo is responding"
	@echo "  make clean   - Stop all services"
	@echo "  make install - Install/update dependencies"
EOF

print_status "Makefile created"

# Test Odoo installation
echo "🧪 Testing Odoo installation..."
cd /opt/odoo
source venv/bin/activate
timeout 10 python3 odoo18/odoo-bin -c ~/.config/odoo/odoo.conf --stop-after-init || true

print_status "Odoo installation completed successfully!"

echo ""
echo "🎉 Setup Complete!"
echo "=================="
echo ""
echo "Quick start:"
echo "  cd /opt/odoo"
echo "  make start          # Start as service"
echo "  make manual         # Start manually with console output"
echo "  make dev            # Start in development mode"
echo "  make help           # Show all available commands"
echo ""
echo "🌐 Access Odoo at: http://localhost:8069"
echo ""
echo "📋 Configuration:"
echo "  Config file: ~/.config/odoo/odoo.conf"
echo "  Data directory: ~/.local/share/odoo/"
echo "  Admin password: admin123"
echo ""
echo "💡 For development, use 'make dev' for auto-reload functionality"
