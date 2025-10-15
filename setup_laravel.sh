#!/bin/bash
set -euo pipefail

# -----------------------------
# COLORS & LOGGING HELPERS
# -----------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
RESET='\033[0m'

log()   { echo -e "${GREEN}✔${RESET} $1"; }
info()  { echo -e "${BLUE}ℹ${RESET} $1"; }
warn()  { echo -e "${YELLOW}⚠${RESET} $1"; }
err()   { echo -e "${RED}✖${RESET} $1"; }

# -----------------------------
# CONFIG
# -----------------------------
PROJECT_NAME=${PROJECT_NAME:-my-new-app}
BASE_DIR=${BASE_DIR:-$(pwd)}
PROJECT_DIR="$BASE_DIR/$PROJECT_NAME"
DOCROOT=public

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RESOURCE_DIR="$SCRIPT_DIR/resources"
BASE_SCAFFOLD_DIR="$SCRIPT_DIR/base_scaffold"
PATCH_DIR="$SCRIPT_DIR/patches"

PATCH_SUCCEEDED=()
PATCH_FAILED=()

# -----------------------------
# UTILITY FUNCTIONS
# -----------------------------
command_exists() { command -v "$1" >/dev/null 2>&1; }

fail_step() {
    err "$1 failed."
    exit 1
}

# -----------------------------
# MODULAR STEPS
# -----------------------------
check_host_dependencies() {
    HOST_TOOLS=(ddev jq open lsof)
    for tool in "${HOST_TOOLS[@]}"; do
        if ! command_exists "$tool"; then
            fail_step "$tool not installed on host"
        fi
    done
    log "Host dependencies verified."
}

clean_project() {
    if ddev list --json-output 2>/dev/null | jq -e --arg name "$PROJECT_NAME" '.projects? // [] | map(select(.name==$name)) | length > 0' >/dev/null; then
        info "Stopping existing DDEV project..."
        ddev stop --unlist "$PROJECT_NAME" || warn "Failed to stop existing project"
    fi
    rm -rf "$PROJECT_DIR"
    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR" || fail_step "Cannot cd into project dir"
    log "Clean project directory ready."
}

create_ddev_project() {
    info "Creating DDEV project..."
    ddev config --project-type=laravel --docroot="$DOCROOT" --project-name="$PROJECT_NAME" || fail_step "DDEV config failed"
    ddev start || fail_step "DDEV start failed"
}

wait_web_container() {
    info "Waiting for web container to become healthy..."
    WEB_CONTAINER=$(docker ps --filter "name=ddev-${PROJECT_NAME}-web" --format "{{.Names}}")
    MAX_WAIT=180
    WAITED=0
    SLEEP_INTERVAL=5
    until [ "$WAITED" -ge "$MAX_WAIT" ]; do
        STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$WEB_CONTAINER" 2>/dev/null || echo "starting")
        if [ "$STATUS" == "healthy" ]; then
            log "Web container is healthy."
            return
        elif [ "$STATUS" == "unhealthy" ]; then
            warn "Web container is unhealthy."
            return
        fi
        info "Waiting for web container... ($WAITED/$MAX_WAIT seconds)"
        sleep $SLEEP_INTERVAL
        WAITED=$((WAITED + SLEEP_INTERVAL))
    done
    warn "Web container did not become healthy within $MAX_WAIT seconds."
}

install_container_tools() {
    CONTAINER_TOOLS=(jq npm php)
    for tool in "${CONTAINER_TOOLS[@]}"; do
        if ! ddev exec command -v "$tool" >/dev/null 2>&1; then
            info "Installing missing container tool: $tool"
            ddev exec bash -c "apt-get update && apt-get install -y $tool" || fail_step "Installing $tool failed"
        fi
    done
    log "All required container tools installed."
}

install_laravel() {
    info "Installing Laravel into project..."
    ddev exec rm -rf /tmp/laravel-temp
    ddev exec mkdir -p /tmp/laravel-temp
    ddev exec composer create-project laravel/laravel:^12 /tmp/laravel-temp || fail_step "Composer create-project failed"
    ddev exec rsync -a /tmp/laravel-temp/ /var/www/html/ || fail_step "rsync failed"
    log "Laravel installed."
}

ensure_package_json() {
    ddev exec bash -c '
    cd /var/www/html
    if [ ! -f package.json ]; then
        echo "Initializing package.json..."
        npm init -y
    fi
    ' || fail_step "Ensuring package.json failed"
    log "package.json ensured."
}

install_node_dependencies() {
    info "Installing Node dependencies..."
    for file_path in resources/css/app.css resources/js/app.js vite.config.js package.json; do
        ddev exec bash -c "cd /var/www/html && [ -f \"$file_path\" ] || touch \"$file_path\""
    done
    ddev exec bash -c 'cd /var/www/html && mkdir -p resources/css resources/js'
    ddev exec bash -c 'cd /var/www/html && npm install --save-dev tailwindcss postcss autoprefixer prettier prettier-plugin-blade prettier-plugin-tailwindcss --legacy-peer-deps || true'
    ddev exec bash -c 'cd /var/www/html && npm install --legacy-peer-deps || true'
    log "Node dependencies installed."
}

install_ide_helpers() {
    info "Installing Laravel IDE Helper package..."
    ddev exec bash -c '
        cd /var/www/html
        composer require --dev barryvdh/laravel-ide-helper
        php artisan ide-helper:generate
        php artisan ide-helper:models --nowrite
        php artisan ide-helper:meta
    ' || fail_step "IDE helper setup failed"

    info "Adding helpers script to package.json..."
    log "Laravel IDE Helper installed and helpers script added."
}

append_ddev_ports() {
    info "Appending DDEV extra web ports at the end of config.yaml..."
    cat <<EOF >> .ddev/config.yaml
web_extra_exposed_ports:
  - name: node-vite
    container_port: 5173
    http_port: 5172
    https_port: 5173
EOF
}

replace_vite_config() {
    info "Replacing vite.config.js with resource version..."
    ddev exec mkdir -p /tmp/resources
    cat "$RESOURCE_DIR/vite.config.js" | ddev exec bash -c "cat > /tmp/resources/vite.config.js"
    ddev exec bash -c 'cp /tmp/resources/vite.config.js /var/www/html/vite.config.js'
    log "vite.config.js replaced successfully."
}

apply_patches() {
    local PATCH_FILE="$1"
    if [ -f "$PATCH_FILE" ]; then
        info "Applying patch: $PATCH_FILE"
        PATCH_NAME=$(basename "$PATCH_FILE")
        ddev exec bash -c "mkdir -p /tmp/patches && rm -f /tmp/patches/$PATCH_NAME"
        cat "$PATCH_FILE" | ddev exec bash -c "cat > /tmp/patches/$PATCH_NAME"
        ddev exec bash -c "cd /var/www/html && patch -p0 < /tmp/patches/$PATCH_NAME" || warn "Patch failed: $PATCH_FILE"
    fi
}

final_cleanup() {
    info "Cleaning up temporary files..."
    ddev exec bash -c 'rm -rf /tmp/base_scaffold /tmp/laravel-temp /tmp/resources /tmp/patches || true'
    rm -rf "$BASE_SCAFFOLD_DIR"
    log "Cleanup complete."
}

# -----------------------------
# RUN ALL STEPS
# -----------------------------
check_host_dependencies
clean_project
create_ddev_project
wait_web_container
install_container_tools
install_laravel
ensure_package_json
install_node_dependencies
install_ide_helpers
append_ddev_ports
replace_vite_config
apply_patches "$PATCH_DIR/prettierrc.patch"
ddev npm pkg set scripts.format="npx prettier --write resources/"
ddev npm pkg set scripts.helpers="php artisan ide-helper:generate && php artisan ide-helper:models && php artisan ide-helper:meta"
final_cleanup
log "Project setup complete."
