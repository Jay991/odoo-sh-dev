#!/bin/bash

function info {
  echo "[INFO] $1"
}

set -e

info "Updating the system..."
sudo apt-get update -y
sudo apt-get upgrade -y

sudo apt install snapd -y
sudo snap install core; sudo snap refresh core
export PATH="$PATH:/snap/bin"

info "Installing pyenv prerequisites..."
sudo apt install -y curl git-core gcc make zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libssl-dev

source "$HOME/.bashrc"

# Install pyenv if not installed
if ! command -v pyenv &> /dev/null; then
  info "Installing pyenv..."
  curl https://pyenv.run | bash

  # Add pyenv to bashrc or zshrc
  info "Setting up pyenv environment variables..."
  if [ -f ~/.bashrc ]; then
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.bashrc
    echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.bashrc
    echo 'eval "$(pyenv init --path)"' >> ~/.bashrc
    echo 'eval "$(pyenv init -)"' >> ~/.bashrc
    source ~/.bashrc
  elif [ -f ~/.zshrc ]; then
    echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.zshrc
    echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.zshrc
    echo 'eval "$(pyenv init --path)"' >> ~/.zshrc
    echo 'eval "$(pyenv init -)"' >> ~/.zshrc
    source ~/.zshrc
  else
    info "No supported shell configuration file found."
    exit 1
  fi
else
  info "pyenv already installed."
fi

# Install Python 3.11.2
info "Installing Python 3.11.2..."
pyenv install 3.11.2

# Set Python 3.11.2 as global version
info "Setting Python 3.11.2 as the global Python version..."
pyenv global 3.11.2

# Link python to python3
info "Linking 'python' to 'python3'..."
sudo ln -sf "$(pyenv which python3)" "$(pyenv which python)"
sudo ln -sf "$(pyenv which python3)" /usr/local/bin/python

# Verify Python installation
info "Python version:"
python --version

info "Installing Nginx..."
sudo apt-get install -y nginx

info "Removing default Nginx site configuration..."
sudo rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default

info "Configuring Nginx for domain..."
read -p "Enter your domain or subdomain name: " domain_name

sudo bash -c "cat > /etc/nginx/sites-available/odoo" <<EOF
server {
    listen 80;
    server_name $domain_name;
    location / {
        proxy_pass http://127.0.0.1:8069;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-NginX-Proxy true;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_redirect off;
        proxy_request_buffering off;
        proxy_connect_timeout  36000s;
        proxy_read_timeout  36000s;
        proxy_send_timeout  36000s;
        send_timeout  36000s;
        client_max_body_size 10240m;
    }

    location /longpolling {
        proxy_pass http://127.0.0.1:8072;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Redirect HTTP to HTTPS
server {
    if (\$host = $domain_name) {
        return 301 https://\$host\$request_uri;
    }

    listen 80;
    server_name $domain_name;
    return 404; 
}
EOF

info "Enabling Nginx site configuration..."
sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/

info "Testing Nginx configuration and reloading service..."
sudo nginx -t && sudo systemctl reload nginx

if ! command -v certbot &> /dev/null; then
    info "Installing Certbot for Let's Encrypt SSL..."
    sudo snap install core; sudo snap refresh core
    sudo snap install --classic certbot
fi

read -p "Enter your email address for SSL certificate registration and renewals: " cert_email
info "Setting up SSL certificate for domain..."
sudo certbot --nginx -d "$domain_name" --non-interactive --agree-tos -m "$cert_email" --redirect

info "Ensuring Certbot auto-renewal is enabled..."
sudo systemctl enable --now snap.certbot.renew.timer

info "Installing PostgreSQL..."
sudo apt-get install -y postgresql

info "Installing wkhtmltopdf..."
WKHTMLTOX_VERSION="0.12.6-1"
WKHTMLTOX_ARCH="amd64"
WKHTMLTOX_URL="https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOX_VERSION}/wkhtmltox_${WKHTMLTOX_VERSION}.buster_${WKHTMLTOX_ARCH}.deb"
wget ${WKHTMLTOX_URL} -O wkhtmltox.deb
sudo apt install -y ./wkhtmltox.deb
rm wkhtmltox.deb

info "Installing Odoo dependencies..."
sudo apt-get install -y git python3-pip build-essential wget python3-dev python3-venv \
python3-wheel libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools node-less libpq-dev

info "Upgrading pip and installing psycopg2..."
sudo python3 -m pip install --upgrade pip
sudo pip install psycopg2 || sudo pip install psycopg2-binary

if id "odoo" &>/dev/null; then
    info "User 'odoo' already exists."
else
    info "Creating 'odoo' user..."
    sudo adduser --system --quiet --shell=/bin/bash --home=/opt/odoo --gecos 'Odoo' --group odoo
fi

if [ ! -d "/opt/odoo/odoo" ]; then
    info "Cloning Odoo source code..."
    sudo -u odoo git clone --depth=1 --branch=17.0 https://github.com/odoo/odoo.git /opt/odoo/odoo
else
    info "Odoo source code already cloned."
fi

info "Installing Odoo and setting up Python virtual environment..."
pushd /opt/odoo/odoo && sudo ./setup/debinstall.sh && popd
sudo -u odoo python3 -m venv /opt/odoo/odoo-venv

source /opt/odoo/odoo-venv/bin/activate
pip install wheel
pip install -r /opt/odoo/odoo/requirements.txt
pip install psycopg2 || pip install psycopg2-binary
pip install PyPDF2
deactivate

PG_USER_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$USER'")
if [ "$PG_USER_EXISTS" != "1" ]; then
    info "Creating PostgreSQL user $USER..."
    sudo -u postgres createuser --createdb --username postgres --no-createrole --no-superuser "$USER"
else
    info "PostgreSQL user $USER already exists."
fi

info "Creating /etc/odoo directory if it does not exist..."
sudo mkdir -p /etc/odoo

info "Creating Odoo configuration file..."
cat <<EOF | sudo tee /etc/odoo/odoo.conf
[options]
admin_passwd = admin
db_host = False
db_port = False
db_user = odoo
db_password = False
addons_path = /opt/odoo/odoo/addons
logfile = /var/log/odoo/odoo.log
log_level = debug
proxy_mode = True
EOF

sudo chown odoo: /etc/odoo/odoo.conf
sudo chmod 640 /etc/odoo/odoo.conf

info "Creating Odoo service..."
ODDO_SERVICE="/etc/systemd/system/odoo.service"
if [ ! -f "$ODDO_SERVICE" ]; then
    sudo bash -c "cat > /etc/systemd/system/odoo.service" <<EOF
[Unit]
Description=Odoo
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo
User=odoo
Group=odoo
ExecStart=/opt/odoo/odoo-venv/bin/python3 /opt/odoo/odoo/odoo-bin -c /etc/odoo/odoo.conf
WorkingDirectory=/opt/odoo/odoo/
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable --now odoo.service
    info "Odoo is now set up to start automatically at boot."
    info "Odoo is now accessible at https://$domain_name"
    info "Use 'sudo systemctl start odoo' to start Odoo."
    info "Use 'sudo systemctl stop odoo' to stop Odoo."
    info "Use 'sudo systemctl status odoo' to view Odoo status."
fi
