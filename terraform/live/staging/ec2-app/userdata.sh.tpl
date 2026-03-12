#!/bin/bash
# ──────────────────────────────────────────────────────────────
# Userdata script — the "fry" phase of the pack/fry pattern.
#
# The AMI was "packed" by Packer/Ansible with nginx installed and
# enabled. This script "fries" the instance at launch time by
# injecting environment-specific variables into the nginx config.
#
# Variables are rendered by Terraform's templatefile() function:
#   server_name = ${server_name}
#   environment = ${environment}
# ──────────────────────────────────────────────────────────────

set -euo pipefail

# Write environment variables to a file that the fry Ansible role
# (run via cloud-init) will consume. This keeps the fry logic in
# Ansible where it belongs, with Terraform only supplying values.
cat > /etc/nginx-fry-vars.env <<EOF
SERVER_NAME=${server_name}
ENVIRONMENT=${environment}
EOF

# Re-render the nginx config using fry-role variables
cat > /etc/nginx/conf.d/app.conf <<EOF
server {
    listen       80;
    server_name  ${server_name};
    root         /usr/share/nginx/html;
    index        index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Health check endpoint for ALB
    location /health {
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# Reload nginx to pick up the new config (service is already running from pack phase)
systemctl reload nginx
