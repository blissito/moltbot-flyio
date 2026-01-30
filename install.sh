#!/bin/bash
set -e

# ============================================================================
# MoltBot Multi-Cloud Installer
# Deploy your personal AI assistant to Fly.io or DigitalOcean
#
# Usage: curl -fsSL https://raw.githubusercontent.com/blissito/moltbot-flyio/main/install.sh | bash
# ============================================================================

# Get script directory (works for both direct execution and curl|bash)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# For curl|bash execution, we need to handle this differently
if [ ! -f "$SCRIPT_DIR/lib/common.sh" ]; then
    # Running via curl|bash - clone the repo first to get the lib files
    TEMP_INSTALL_DIR="/tmp/moltbot-installer-$$"
    git clone --depth 1 https://github.com/blissito/moltbot-flyio.git "$TEMP_INSTALL_DIR" 2>/dev/null
    SCRIPT_DIR="$TEMP_INSTALL_DIR"
fi

# Source library modules
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/config.sh"

# Provider selection (will source the appropriate provider module)
CLOUD_PROVIDER=""

# ============================================================================
# Provider Selection
# ============================================================================

select_provider() {
    echo ""
    echo -e "${WHITE}Where would you like to deploy MoltBot?${NC}"
    echo ""
    echo "  1. Fly.io        - \$22-25/mo (4GB RAM, persistent volume)"
    echo "  2. DigitalOcean  - \$12-24/mo (App Platform, simpler setup)"
    echo ""

    local choice
    choice=$(prompt_input "Select provider (1-2)" "1")

    case "$choice" in
        2)
            CLOUD_PROVIDER="digitalocean"
            source "$SCRIPT_DIR/lib/provider-digitalocean.sh"
            ;;
        *)
            CLOUD_PROVIDER="flyio"
            source "$SCRIPT_DIR/lib/provider-flyio.sh"
            ;;
    esac

    log_success "Selected: ${PROVIDER_DISPLAY_NAME}"
}

# ============================================================================
# Requirement Checks
# ============================================================================

check_requirements() {
    log_step "Step 1/8: Checking requirements"

    local missing=0

    # Check git
    if check_command git; then
        log_success "git installed"
    else
        log_error "git not found - install from https://git-scm.com"
        missing=1
    fi

    # Check provider CLI
    if ! provider_check_cli; then
        missing=1
    fi

    # Check openssl (for token generation)
    if check_command openssl; then
        log_success "openssl installed"
    else
        log_error "openssl not found (needed for token generation)"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        echo ""
        log_error "Please install missing requirements and run again"
        exit 1
    fi

    echo ""
    log_success "All requirements met!"
}

# ============================================================================
# Provider Authentication
# ============================================================================

check_provider_auth() {
    log_step "Step 2/8: ${PROVIDER_DISPLAY_NAME} Authentication"

    if provider_check_auth; then
        return 0
    else
        if ! provider_login; then
            exit 1
        fi
    fi
}

# ============================================================================
# Gather Configuration
# ============================================================================

gather_all_config() {
    log_step "Step 3/8: Configuration"

    echo -e "${WHITE}Let's configure your MoltBot deployment${NC}"
    echo ""

    # App name
    gather_app_name "blissmoltbot"

    # Region (provider-specific)
    echo ""
    provider_select_region

    # AI provider configuration
    gather_ai_provider

    # Channel configuration
    gather_channels
}

# ============================================================================
# Clone Repository
# ============================================================================

clone_repo() {
    log_step "Step 4/8: Cloning MoltBot repository"

    INSTALL_DIR="${INSTALL_DIR:-$(pwd)/moltbot-deploy}"

    if [ -d "$INSTALL_DIR" ]; then
        if prompt_confirm "Directory $INSTALL_DIR exists. Remove and re-clone?"; then
            rm -rf "$INSTALL_DIR"
        else
            log_info "Using existing directory"
            cd "$INSTALL_DIR"
            return
        fi
    fi

    log_info "Cloning to ${WHITE}${INSTALL_DIR}${NC}..."
    git clone --depth 1 https://github.com/moltbot/moltbot.git "$INSTALL_DIR" 2>&1 | while read -r line; do
        echo -e "  ${line}"
    done

    cd "$INSTALL_DIR"
    log_success "Repository cloned!"
}

# ============================================================================
# Create Cloud Resources
# ============================================================================

create_cloud_resources() {
    log_step "Step 5/8: Creating ${PROVIDER_DISPLAY_NAME} resources"

    if ! provider_create_app "$APP_NAME" "$REGION"; then
        exit 1
    fi

    if ! provider_create_storage "$APP_NAME" "$REGION"; then
        exit 1
    fi
}

# ============================================================================
# Configure Secrets
# ============================================================================

configure_secrets() {
    log_step "Step 6/8: Configuring secrets"

    # Base secrets (always required)
    local secrets=("${API_KEY_NAME}=${API_KEY}" "CLAWDBOT_GATEWAY_TOKEN=${GATEWAY_TOKEN}")

    # Add channel tokens if provided
    [ -n "$TELEGRAM_TOKEN" ] && secrets+=("TELEGRAM_BOT_TOKEN=${TELEGRAM_TOKEN}")
    [ -n "$DISCORD_TOKEN" ] && secrets+=("DISCORD_BOT_TOKEN=${DISCORD_TOKEN}")
    [ -n "$SLACK_BOT_TOKEN" ] && secrets+=("SLACK_BOT_TOKEN=${SLACK_BOT_TOKEN}")
    [ -n "$SLACK_APP_TOKEN" ] && secrets+=("SLACK_APP_TOKEN=${SLACK_APP_TOKEN}")

    provider_set_secrets "$APP_NAME" "${secrets[@]}"
}

# ============================================================================
# Deploy
# ============================================================================

deploy_app() {
    log_step "Step 7/8: Deploying to ${PROVIDER_DISPLAY_NAME}"

    if ! provider_deploy "$APP_NAME"; then
        exit 1
    fi
}

# ============================================================================
# Configure Gateway
# ============================================================================

configure_gateway() {
    log_step "Step 8/8: Configuring gateway"

    log_info "Waiting for server to start (45 seconds)..."
    sleep 45

    log_info "Creating moltbot.json configuration..."

    local config_json
    config_json=$(generate_config_json)

    if ! provider_write_config "$APP_NAME" "$config_json"; then
        log_warn "You may need to manually configure channels in the dashboard"
    fi

    # Restart to apply config
    log_info "Restarting to apply configuration..."
    provider_restart "$APP_NAME" > /dev/null 2>&1 || true

    log_info "Waiting for restart (30 seconds)..."
    sleep 30

    log_success "Configuration applied!"
}

# ============================================================================
# Success Message
# ============================================================================

print_success() {
    local app_url
    app_url=$(provider_get_url "$APP_NAME")

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}                    DEPLOYMENT SUCCESSFUL!                    ${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Your MoltBot is ready!${NC}"
    echo ""
    echo -e "${CYAN}Dashboard URL:${NC}"
    echo -e "  ${WHITE}${app_url}/?token=${GATEWAY_TOKEN}${NC}"
    echo ""
    echo -e "${CYAN}Gateway Token (save this!):${NC}"
    echo -e "  ${WHITE}${GATEWAY_TOKEN}${NC}"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}IMPORTANT: Save the token above! You need it to access${NC}"
    echo -e "${YELLOW}your dashboard. Keep it secret - anyone with this token${NC}"
    echo -e "${YELLOW}can pair their device and access your bot permanently.${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local enabled_channels
    enabled_channels=$(get_enabled_channels)

    echo -e "${WHITE}Next steps:${NC}"
    echo -e "  1. Open the dashboard URL above"
    echo -e "  2. Your browser will be paired automatically on first access"
    if [ "$WHATSAPP_ENABLED" = "true" ]; then
        echo -e "  3. Connect WhatsApp by scanning QR in the dashboard"
    fi
    if [ "$TELEGRAM_ENABLED" = "true" ] && [ -z "$TELEGRAM_TOKEN" ]; then
        echo -e "  3. Configure Telegram bot token in the dashboard"
    fi
    if [ "$DISCORD_ENABLED" = "true" ] && [ -z "$DISCORD_TOKEN" ]; then
        echo -e "  3. Configure Discord bot token in the dashboard"
    fi
    if [ "$SLACK_ENABLED" = "true" ] && [ -z "$SLACK_BOT_TOKEN" ]; then
        echo -e "  3. Configure Slack tokens in the dashboard"
    fi
    echo ""
    echo -e "${WHITE}Security:${NC}"
    echo -e "  - Your token is like a password - don't share it"
    echo -e "  - Once paired, devices have permanent access"
    echo ""
    echo -e "${WHITE}Provider: ${GREEN}${PROVIDER_DISPLAY_NAME}${NC}"
    echo -e "${WHITE}AI Provider: ${GREEN}${AI_PROVIDER}${NC}"
    echo -e "${WHITE}Model: ${GREEN}${MODEL}${NC}"
    echo -e "${WHITE}Channels: ${GREEN}${enabled_channels:-None}${NC}"
    echo -e "${WHITE}Estimated monthly cost: ${GREEN}${PROVIDER_COST_ESTIMATE}${NC} (hosting only, API usage extra)"
    echo ""
    echo -e "${WHITE}Useful commands:${NC}"
    echo -e "  ${CYAN}./moltbot-cli.sh logs${NC}        # View logs"
    echo -e "  ${CYAN}./moltbot-cli.sh status${NC}      # Check status"
    echo -e "  ${CYAN}./moltbot-cli.sh restart${NC}     # Restart bot"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    print_banner

    echo -e "${WHITE}This script will deploy MoltBot to the cloud.${NC}"
    echo -e "You'll need: A cloud provider account, Anthropic or OpenAI API key"
    echo ""

    if ! prompt_confirm "Ready to begin?"; then
        echo "Cancelled."
        exit 0
    fi

    select_provider
    check_requirements
    check_provider_auth
    gather_all_config
    clone_repo
    create_cloud_resources
    configure_secrets
    deploy_app
    configure_gateway
    print_success

    # Cleanup temp installer if used
    if [ -n "$TEMP_INSTALL_DIR" ] && [ -d "$TEMP_INSTALL_DIR" ]; then
        rm -rf "$TEMP_INSTALL_DIR"
    fi
}

# Run main function
main "$@"
