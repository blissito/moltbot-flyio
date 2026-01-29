#!/bin/bash
# MoltBot CLI - Manage your MoltBot deployment on Fly.io or DigitalOcean
# Usage: ./moltbot-cli.sh <command> [options]

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library modules
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/config.sh"

# Provider (detected or specified)
CLOUD_PROVIDER=""
APP_NAME=""

# ============================================================================
# Help
# ============================================================================

print_help() {
    print_banner
    echo -e "${WHITE}Usage:${NC}"
    echo "  moltbot-cli.sh <command> [options]"
    echo ""
    echo -e "${WHITE}Commands:${NC}"
    echo -e "  ${CYAN}status${NC}              Show app status and info"
    echo -e "  ${CYAN}logs${NC}                View live logs (Ctrl+C to exit)"
    echo -e "  ${CYAN}restart${NC}             Restart the bot"
    echo -e "  ${CYAN}channels${NC}            List enabled channels"
    echo -e "  ${CYAN}add-whatsapp${NC}        Enable WhatsApp channel"
    echo -e "  ${CYAN}add-telegram${NC}        Enable Telegram channel"
    echo -e "  ${CYAN}add-discord${NC}         Enable Discord channel"
    echo -e "  ${CYAN}add-slack${NC}           Enable Slack channel"
    echo -e "  ${CYAN}remove-channel${NC} <n>  Disable a channel (whatsapp|telegram|discord|slack)"
    echo -e "  ${CYAN}config${NC}              Show current configuration"
    echo -e "  ${CYAN}update${NC}              Update MoltBot to latest version"
    echo ""
    echo -e "${WHITE}Options:${NC}"
    echo -e "  ${CYAN}--app${NC} <name>        Specify app name (auto-detects from config files)"
    echo -e "  ${CYAN}--provider${NC} <name>   Specify provider (flyio|digitalocean)"
    echo ""
    echo -e "${WHITE}Examples:${NC}"
    echo "  moltbot-cli.sh status"
    echo "  moltbot-cli.sh add-telegram --app my-moltbot"
    echo "  moltbot-cli.sh logs --provider digitalocean"
    echo ""
}

# ============================================================================
# Provider Detection
# ============================================================================

detect_provider() {
    if [ -n "$CLOUD_PROVIDER" ]; then
        source "$SCRIPT_DIR/lib/provider-${CLOUD_PROVIDER}.sh"
        return 0
    fi

    # Try to detect from config files
    if [ -f "fly.toml" ]; then
        CLOUD_PROVIDER="flyio"
        source "$SCRIPT_DIR/lib/provider-flyio.sh"
        log_info "Detected provider: ${WHITE}Fly.io${NC}"
        return 0
    fi

    if [ -f "app-spec.yaml" ] || [ -f ".do/app.yaml" ]; then
        CLOUD_PROVIDER="digitalocean"
        source "$SCRIPT_DIR/lib/provider-digitalocean.sh"
        log_info "Detected provider: ${WHITE}DigitalOcean${NC}"
        return 0
    fi

    # Try Fly.io first (most common)
    if check_command fly && fly auth whoami &> /dev/null; then
        CLOUD_PROVIDER="flyio"
        source "$SCRIPT_DIR/lib/provider-flyio.sh"
        return 0
    fi

    # Try DigitalOcean
    if check_command doctl && doctl account get &> /dev/null; then
        CLOUD_PROVIDER="digitalocean"
        source "$SCRIPT_DIR/lib/provider-digitalocean.sh"
        return 0
    fi

    log_error "Could not detect provider. Use --provider flag."
    exit 1
}

detect_app() {
    if [ -n "$APP_NAME" ]; then
        return 0
    fi

    # Try provider-specific detection
    APP_NAME=$(provider_get_app_name)

    if [ -n "$APP_NAME" ] && [ "$APP_NAME" != "your-app-name" ]; then
        log_info "Detected app: ${WHITE}${APP_NAME}${NC}"
        return 0
    fi

    # Ask user to select
    echo -e "${WHITE}Available MoltBot apps:${NC}"

    if [ "$CLOUD_PROVIDER" = "flyio" ]; then
        local apps
        apps=$(fly apps list 2>/dev/null | grep -E "moltbot|molt" | awk '{print $1}' || true)

        if [ -z "$apps" ]; then
            log_error "No MoltBot apps found. Use --app <name> to specify."
            exit 1
        fi

        echo "$apps" | nl -w2 -s") "
        echo ""
        read -p "Select app number (or enter name): " SELECTION

        if [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
            APP_NAME=$(echo "$apps" | sed -n "${SELECTION}p")
        else
            APP_NAME="$SELECTION"
        fi
    elif [ "$CLOUD_PROVIDER" = "digitalocean" ]; then
        local apps
        apps=$(doctl apps list --format Spec.Name --no-header 2>/dev/null | grep -E "moltbot|molt" || true)

        if [ -z "$apps" ]; then
            log_error "No MoltBot apps found. Use --app <name> to specify."
            exit 1
        fi

        echo "$apps" | nl -w2 -s") "
        echo ""
        read -p "Select app number (or enter name): " SELECTION

        if [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
            APP_NAME=$(echo "$apps" | sed -n "${SELECTION}p")
        else
            APP_NAME="$SELECTION"
        fi
    fi

    if [ -z "$APP_NAME" ]; then
        log_error "No app selected"
        exit 1
    fi
}

check_provider_cli() {
    if ! provider_check_cli > /dev/null 2>&1; then
        provider_check_cli
        exit 1
    fi

    if ! provider_check_auth > /dev/null 2>&1; then
        log_error "Not authenticated. Run the provider's login command first."
        exit 1
    fi
}

# ============================================================================
# Commands
# ============================================================================

cmd_status() {
    detect_app
    echo ""
    log_info "Fetching status for ${WHITE}${APP_NAME}${NC}..."
    echo ""

    provider_status "$APP_NAME"

    echo ""
    echo -e "${WHITE}Dashboard:${NC} $(provider_get_url "$APP_NAME")"
    echo ""
}

cmd_logs() {
    detect_app
    log_info "Streaming logs for ${WHITE}${APP_NAME}${NC} (Ctrl+C to exit)..."
    echo ""
    provider_logs "$APP_NAME"
}

cmd_restart() {
    detect_app
    provider_restart "$APP_NAME"
    echo ""
    log_info "View logs with: ${CYAN}./moltbot-cli.sh logs${NC}"
}

cmd_channels() {
    detect_app
    log_info "Fetching channels for ${WHITE}${APP_NAME}${NC}..."
    echo ""

    local config
    config=$(provider_read_config "$APP_NAME")

    if [ "$config" = "{}" ] || [ -z "$config" ]; then
        log_warn "No configuration found"
        return
    fi

    echo -e "${WHITE}Enabled channels:${NC}"

    # Parse channels (simple grep approach, works without jq)
    if echo "$config" | grep -q '"whatsapp"'; then
        local enabled
        enabled=$(echo "$config" | grep -A2 '"whatsapp"' | grep '"enabled"' | grep -q 'true' && echo "yes" || echo "no")
        [ "$enabled" = "yes" ] && echo -e "  ${GREEN}✓${NC} WhatsApp" || echo -e "  ${DIM}✗ WhatsApp${NC}"
    fi

    if echo "$config" | grep -q '"telegram"'; then
        local enabled
        enabled=$(echo "$config" | grep -A2 '"telegram"' | grep '"enabled"' | grep -q 'true' && echo "yes" || echo "no")
        [ "$enabled" = "yes" ] && echo -e "  ${GREEN}✓${NC} Telegram" || echo -e "  ${DIM}✗ Telegram${NC}"
    fi

    if echo "$config" | grep -q '"discord"'; then
        local enabled
        enabled=$(echo "$config" | grep -A2 '"discord"' | grep '"enabled"' | grep -q 'true' && echo "yes" || echo "no")
        [ "$enabled" = "yes" ] && echo -e "  ${GREEN}✓${NC} Discord" || echo -e "  ${DIM}✗ Discord${NC}"
    fi

    if echo "$config" | grep -q '"slack"'; then
        local enabled
        enabled=$(echo "$config" | grep -A2 '"slack"' | grep '"enabled"' | grep -q 'true' && echo "yes" || echo "no")
        [ "$enabled" = "yes" ] && echo -e "  ${GREEN}✓${NC} Slack" || echo -e "  ${DIM}✗ Slack${NC}"
    fi

    echo ""
}

cmd_config() {
    detect_app
    log_info "Fetching config for ${WHITE}${APP_NAME}${NC}..."
    echo ""

    local config
    config=$(provider_read_config "$APP_NAME")

    if [ "$config" = "{}" ] || [ -z "$config" ]; then
        log_warn "No configuration found"
    else
        echo "$config"
    fi
    echo ""
}

cmd_add_channel() {
    local channel="$1"
    local token_prompt="$2"

    detect_app

    log_info "Adding ${WHITE}${channel}${NC} to ${WHITE}${APP_NAME}${NC}..."

    local token=""
    # Get token if needed
    if [ -n "$token_prompt" ]; then
        echo ""
        log_info "$token_prompt"
        read -sp "Token (hidden): " token
        echo ""

        if [ -z "$token" ]; then
            log_warn "No token provided. Channel will be enabled but may not work until configured."
        fi
    fi

    # Read current config
    local config
    config=$(provider_read_config "$APP_NAME")

    if [ "$config" = "{}" ] || [ -z "$config" ]; then
        log_error "No configuration found. Run the installer first."
        exit 1
    fi

    # Ensure jq is available
    ensure_jq

    local new_config
    # Add channel based on type
    case "$channel" in
        whatsapp)
            new_config=$(echo "$config" | jq '.channels.whatsapp = {"enabled": true, "dmPolicy": "pairing", "sendReadReceipts": true, "textChunkLimit": 4000}')
            new_config=$(echo "$new_config" | jq '.plugins.entries.whatsapp = {"enabled": true}')
            ;;
        telegram)
            if [ -n "$token" ]; then
                new_config=$(echo "$config" | jq --arg token "$token" '.channels.telegram = {"enabled": true, "botToken": $token, "dmPolicy": "pairing"}')
            else
                new_config=$(echo "$config" | jq '.channels.telegram = {"enabled": true, "dmPolicy": "pairing"}')
            fi
            new_config=$(echo "$new_config" | jq '.plugins.entries.telegram = {"enabled": true}')
            ;;
        discord)
            if [ -n "$token" ]; then
                new_config=$(echo "$config" | jq --arg token "$token" '.channels.discord = {"enabled": true, "token": $token, "dm": {"dmPolicy": "pairing"}}')
            else
                new_config=$(echo "$config" | jq '.channels.discord = {"enabled": true, "dm": {"dmPolicy": "pairing"}}')
            fi
            new_config=$(echo "$new_config" | jq '.plugins.entries.discord = {"enabled": true}')
            ;;
        slack)
            if [ -n "$token" ]; then
                new_config=$(echo "$config" | jq --arg token "$token" '.channels.slack = {"enabled": true, "botToken": $token, "dmPolicy": "pairing"}')
            else
                new_config=$(echo "$config" | jq '.channels.slack = {"enabled": true, "dmPolicy": "pairing"}')
            fi
            new_config=$(echo "$new_config" | jq '.plugins.entries.slack = {"enabled": true}')
            ;;
    esac

    # Write new config
    if ! provider_write_config "$APP_NAME" "$new_config"; then
        log_error "Failed to write config"
        exit 1
    fi

    log_success "Channel ${channel} added!"

    # Restart
    log_info "Restarting to apply changes..."
    if provider_restart "$APP_NAME" > /dev/null 2>&1; then
        log_success "Done! Channel ${channel} is now enabled."
    else
        log_warn "Could not restart automatically. Run: ./moltbot-cli.sh restart"
    fi
    echo ""
}

cmd_remove_channel() {
    local channel="$1"

    if [ -z "$channel" ]; then
        log_error "Usage: ./moltbot-cli.sh remove-channel <whatsapp|telegram|discord|slack>"
        exit 1
    fi

    detect_app

    log_info "Removing ${WHITE}${channel}${NC} from ${WHITE}${APP_NAME}${NC}..."

    # Read current config
    local config
    config=$(provider_read_config "$APP_NAME")

    if [ "$config" = "{}" ] || [ -z "$config" ]; then
        log_error "No configuration found"
        exit 1
    fi

    # Ensure jq is available
    ensure_jq

    # Remove channel
    local new_config
    new_config=$(echo "$config" | jq "del(.channels.${channel}) | del(.plugins.entries.${channel})")

    # Write new config
    if ! provider_write_config "$APP_NAME" "$new_config"; then
        log_error "Failed to write config"
        exit 1
    fi

    log_success "Channel ${channel} removed!"

    # Restart
    log_info "Restarting to apply changes..."
    if provider_restart "$APP_NAME" > /dev/null 2>&1; then
        log_success "Done!"
    else
        log_warn "Could not restart automatically. Run: ./moltbot-cli.sh restart"
    fi
    echo ""
}

cmd_update() {
    detect_app

    log_info "Updating ${WHITE}${APP_NAME}${NC} to latest MoltBot version..."
    echo ""

    # Check if we're in a moltbot directory
    if [ ! -f "fly.toml" ] && [ ! -f "app-spec.yaml" ]; then
        log_error "Run this command from your moltbot deployment directory"
        exit 1
    fi

    # Pull latest changes
    log_info "Pulling latest changes..."
    git pull origin main

    # Deploy
    log_info "Deploying update..."
    provider_deploy "$APP_NAME"

    log_success "Update complete!"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Parse arguments
    local command=""
    local extra_arg=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --app)
                APP_NAME="$2"
                shift 2
                ;;
            --provider)
                CLOUD_PROVIDER="$2"
                shift 2
                ;;
            --help|-h)
                print_help
                exit 0
                ;;
            *)
                if [ -z "$command" ]; then
                    command="$1"
                else
                    extra_arg="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$command" ]; then
        print_help
        exit 0
    fi

    detect_provider
    check_provider_cli

    case "$command" in
        status)
            cmd_status
            ;;
        logs)
            cmd_logs
            ;;
        restart)
            cmd_restart
            ;;
        channels)
            cmd_channels
            ;;
        config)
            cmd_config
            ;;
        add-whatsapp)
            cmd_add_channel "whatsapp" ""
            ;;
        add-telegram)
            cmd_add_channel "telegram" "Get your bot token from @BotFather on Telegram"
            ;;
        add-discord)
            cmd_add_channel "discord" "Get your bot token from https://discord.com/developers/applications"
            ;;
        add-slack)
            cmd_add_channel "slack" "Get your bot token from https://api.slack.com/apps"
            ;;
        remove-channel)
            cmd_remove_channel "$extra_arg"
            ;;
        update)
            cmd_update
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            print_help
            exit 1
            ;;
    esac
}

main "$@"
