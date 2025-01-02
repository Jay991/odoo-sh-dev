#!/bin/bash

# Exit on error, undefined variables, and pipe failures
set -euo pipefail
trap 'echo "Error occurred on line $LINENO. Exit code: $?"' ERR

# Configuration variables
ODOO_VERSION="17.0"
ODOO_USER="odoo"
ODOO_HOME="/opt/odoo"
ODOO_CONFIG="/etc/odoo/odoo.conf"
NGINX_CONFIG="/etc/nginx/sites-available/odoo"
ODOO_LOG_DIR="/var/log/odoo"

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check and create user
create_user() {
    if ! id "$ODOO_USER" &>/dev/null; then
        log "Creating '$ODOO_USER' user..."
        sudo adduser --system --quiet --shell=/bin/bash --home="$ODOO_HOME" --gecos 'Odoo' --group "$ODOO_USER"
    else
        log "User '$ODOO_USER' already exists."
    fi
}

# Function to install system dependencies
install_dependencies() {
    log "Updating the system..."
    sudo apt-get update -y
    
    log "Installing required packages..."
    sudo apt-get install -y nginx postgresql git python3-pip build-essential wget \
        python3-dev python3-venv python3-wheel libxslt-dev libzip-dev libldap2-dev \
        libsasl2-dev python3-setuptools node-less libpq-dev libfreetype6-dev \
        libjpeg-dev zlib1g-dev
}

# Function to configure Nginx
configure_nginx() {
    local domain_name="$1"
    
    log "Removing default Nginx configuration..."
    sudo rm -f /etc/nginx/sites-{enabled,available}/default

    log "Configuring Nginx for domain: $domain_name"
    sudo bash -c "cat > $NGINX_CONFIG" <<EOF
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name $domain_name;
    return 301 https://\$host\$request_uri;
}

# Main HTTPS server block
server {
    listen 443 ssl http2;
    server_name $domain_name;

    ssl_certificate /etc/letsencrypt/live/$domain_name/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain_name/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    add_header Content-Security-Policy "upgrade-insecure-requests";

    # Proxy settings
    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;
    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /longpolling {
        proxy_pass http://127.0.0.1:8072;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    gzip_min_length 1000;
    gzip_proxied any;

    # Logs
    error_log /var/log/nginx/odoo_error.log;
    access_log /var/log/nginx/odoo_access.log combined buffer=512k flush=1m;
}
EOF

    sudo ln -sf "$NGINX_CONFIG" /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl reload nginx
}

# Function to setup SSL with Certbot
setup_ssl() {
    local domain_name="$1"
    local cert_email="$2"

    if ! command_exists certbot; then
        log "Installing Certbot..."
        sudo snap install core
        sudo snap refresh core
        sudo snap install --classic certbot
        sudo ln -sf /snap/bin/certbot /usr/bin/certbot
    fi

    log "Setting up SSL certificate..."
    sudo certbot --nginx -d "$domain_name" --non-interactive --agree-tos -m "$cert_email" --redirect
    sudo systemctl enable --now snap.certbot.renew.timer
}

# Function to setup PostgreSQL
setup_postgresql() {
    log "Configuring PostgreSQL..."
    if ! sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ODOO_USER'" | grep -q 1; then
        sudo -u postgres createuser --createdb --no-createrole --no-superuser "$ODOO_USER"
    fi
}

# Function to setup Odoo
setup_odoo() {
    log "Setting up Odoo..."
    
    # Create required directories
    sudo mkdir -p "$ODOO_HOME" "$ODOO_LOG_DIR"
    
    # Clone Odoo if not exists
    if [ ! -d "$ODOO_HOME/odoo" ]; then
        sudo -u "$ODOO_USER" git clone --depth=1 --branch="$ODOO_VERSION" https://github.com/odoo/odoo.git "$ODOO_HOME/odoo"
    fi

    # Setup virtual environment
    if [ ! -d "$ODOO_HOME/odoo-venv" ]; then
        sudo -u "$ODOO_USER" python3 -m venv "$ODOO_HOME/odoo-venv"
        sudo -u "$ODOO_USER" "$ODOO_HOME/odoo-venv/bin/pip" install --upgrade pip wheel
        sudo -u "$ODOO_USER" "$ODOO_HOME/odoo-venv/bin/pip" install -r "$ODOO_HOME/odoo/requirements.txt"
        sudo -u "$ODOO_USER" "$ODOO_HOME/odoo-venv/bin/pip" install PyPDF2
    fi

    # Create Odoo configuration
    sudo mkdir -p "$(dirname $ODOO_CONFIG)"
    cat <<EOF | sudo tee "$ODOO_CONFIG"
[options]
admin_passwd = $(openssl rand -base64 12)
db_host = False
db_port = False
db_user = $ODOO_USER
db_password = False
addons_path = $ODOO_HOME/odoo/addons
logfile = $ODOO_LOG_DIR/odoo.log
log_level = info
workers = $(( $(nproc) * 2 ))
max_cron_threads = $(nproc)
longpolling_port = 8072
EOF

    sudo chown "$ODOO_USER:" "$ODOO_CONFIG"
    sudo chmod 640 "$ODOO_CONFIG"
}

# Function to create systemd service
create_service() {
    log "Creating Odoo service..."
    cat <<EOF | sudo tee /etc/systemd/system/odoo.service
[Unit]
Description=Odoo
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_HOME/odoo-venv/bin/python3 $ODOO_HOME/odoo/odoo-bin -c $ODOO_CONFIG
WorkingDirectory=$ODOO_HOME/odoo
StandardOutput=journal+console
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now odoo.service
}

# Main execution
main() {
    # Get user input
    read -p "Enter your domain or subdomain name: " domain_name
    read -p "Enter your email address for SSL certificate: " cert_email

    # Execute installation steps
    install_dependencies
    create_user
    configure_nginx "$domain_name"
    setup_ssl "$domain_name" "$cert_email"
    setup_postgresql
    setup_odoo
    create_service

    log "Installation completed successfully!"
    log "Odoo is now accessible at https://$domain_name"
    log "Use 'sudo systemctl {start|stop|status} odoo' to manage the service."
}

main "$@"
