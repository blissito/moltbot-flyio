#!/bin/bash
# MoltBot CLI - Manage your MoltBot deployment on Fly.io
# Usage: curl -fsSL https://raw.githubusercontent.com/blissito/moltbot-flyio/main/moltbot-cli.sh | bash -s -- <command>

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'

# Symbols
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
ARROW="${CYAN}→${NC}"
WARN="${YELLOW}⚠${NC}"

# ============================================================================
# Helper Functions
# ============================================================================

log_info() { echo -e "${ARROW} $1"; }
log_success() { echo -e "${CHECK} $1"; }
log_error() { echo -e "${CROSS} ${RED}$1${NC}"; }
log_warn() { echo -e "${WARN} ${YELLOW}$1${NC}"; }

print_banner() {
    echo -e "${CYAN}"
    echo "  MoltBot CLI v1.0.0"
    echo -e "${NC}"
}

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
    echo -e "  ${CYAN}--app${NC} <name>        Specify app name (auto-detects from fly.toml)"
    echo ""
    echo -e "${WHITE}Examples:${NC}"
    echo "  moltbot-cli.sh status"
    echo "  moltbot-cli.sh add-telegram --app my-moltbot"
    echo "  moltbot-cli.sh logs"
    echo ""
}

# ============================================================================
# Dependency Management
# ============================================================================

ensure_jq() {
    if command -v jq &> /dev/null; then
        return 0
    fi

    log_warn "jq not found. It's required for channel management."
    echo ""

    # Detect OS and offer auto-install
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew &> /dev/null; then
            read -p "Install jq with Homebrew? (Y/n) " INSTALL_JQ
            if [[ "${INSTALL_JQ:-y}" =~ ^[Yy]$ ]]; then
                log_info "Installing jq..."
                brew install jq
                if command -v jq &> /dev/null; then
                    log_success "jq installed!"
                    return 0
                fi
            fi
        else
            log_info "Install jq manually:"
            echo "  brew install jq"
            echo "  # or download from https://stedolan.github.io/jq/download/"
        fi
    elif [[ -f /etc/debian_version ]]; then
        read -p "Install jq with apt? (requires sudo) (Y/n) " INSTALL_JQ
        if [[ "${INSTALL_JQ:-y}" =~ ^[Yy]$ ]]; then
            log_info "Installing jq..."
            sudo apt-get update && sudo apt-get install -y jq
            if command -v jq &> /dev/null; then
                log_success "jq installed!"
                return 0
            fi
        fi
    elif [[ -f /etc/redhat-release ]]; then
        read -p "Install jq with yum? (requires sudo) (Y/n) " INSTALL_JQ
        if [[ "${INSTALL_JQ:-y}" =~ ^[Yy]$ ]]; then
            log_info "Installing jq..."
            sudo yum install -y jq
            if command -v jq &> /dev/null; then
                log_success "jq installed!"
                return 0
            fi
        fi
    else
        log_info "Install jq manually:"
        echo "  # Debian/Ubuntu: sudo apt install jq"
        echo "  # RHEL/CentOS:   sudo yum install jq"
        echo "  # macOS:         brew install jq"
        echo "  # Download:      https://stedolan.github.io/jq/download/"
    fi

    log_error "jq is required but not installed"
    exit 1
}

# ============================================================================
# App Detection
# ============================================================================

detect_app() {
    if [ -n "$APP_NAME" ]; then
        return 0
    fi

    # Try to get from fly.toml in current directory
    if [ -f "fly.toml" ]; then
        APP_NAME=$(grep "^app = " fly.toml | sed 's/app = "\(.*\)"/\1/')
        if [ -n "$APP_NAME" ] && [ "$APP_NAME" != "your-app-name" ]; then
            log_info "Detected app: ${WHITE}${APP_NAME}${NC}"
            return 0
        fi
    fi

    # Try to list fly apps and let user choose
    echo -e "${WHITE}Available MoltBot apps:${NC}"
    APPS=$(fly apps list 2>/dev/null | grep -E "moltbot|molt" | awk '{print $1}' || true)

    if [ -z "$APPS" ]; then
        log_error "No MoltBot apps found. Use --app <name> to specify."
        exit 1
    fi

    echo "$APPS" | nl -w2 -s") "
    echo ""
    read -p "Select app number (or enter name): " SELECTION

    if [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
        APP_NAME=$(echo "$APPS" | sed -n "${SELECTION}p")
    else
        APP_NAME="$SELECTION"
    fi

    if [ -z "$APP_NAME" ]; then
        log_error "No app selected"
        exit 1
    fi
}

check_fly() {
    if ! command -v fly &> /dev/null; then
        log_error "Fly CLI not found. Install it first:"
        echo "  curl -L https://fly.io/install.sh | sh"
        exit 1
    fi

    if ! fly auth whoami &> /dev/null; then
        log_error "Not logged in to Fly.io. Run: fly auth login"
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

    fly status --app "$APP_NAME"

    echo ""
    echo -e "${WHITE}Dashboard:${NC} https://${APP_NAME}.fly.dev"
    echo ""
}

cmd_logs() {
    detect_app
    log_info "Streaming logs for ${WHITE}${APP_NAME}${NC} (Ctrl+C to exit)..."
    echo ""
    fly logs --app "$APP_NAME"
}

cmd_restart() {
    detect_app
    log_info "Restarting ${WHITE}${APP_NAME}${NC}..."

    MACHINE_ID=$(fly machines list --app "$APP_NAME" --json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$MACHINE_ID" ]; then
        log_error "Could not find machine ID"
        exit 1
    fi

    fly machines restart "$MACHINE_ID" --app "$APP_NAME"
    log_success "Restart initiated!"
    echo ""
    log_info "View logs with: ${CYAN}moltbot-cli.sh logs${NC}"
}

cmd_channels() {
    detect_app
    log_info "Fetching channels for ${WHITE}${APP_NAME}${NC}..."
    echo ""

    CONFIG=$(fly ssh console --app "$APP_NAME" -C "cat /data/moltbot.json 2>/dev/null" 2>/dev/null || echo "{}")

    if [ "$CONFIG" = "{}" ] || [ -z "$CONFIG" ]; then
        log_warn "No configuration found"
        return
    fi

    echo -e "${WHITE}Enabled channels:${NC}"

    # Parse channels (simple grep approach, works without jq)
    if echo "$CONFIG" | grep -q '"whatsapp"'; then
        ENABLED=$(echo "$CONFIG" | grep -A2 '"whatsapp"' | grep '"enabled"' | grep -q 'true' && echo "yes" || echo "no")
        [ "$ENABLED" = "yes" ] && echo -e "  ${GREEN}✓${NC} WhatsApp" || echo -e "  ${DIM}✗ WhatsApp${NC}"
    fi

    if echo "$CONFIG" | grep -q '"telegram"'; then
        ENABLED=$(echo "$CONFIG" | grep -A2 '"telegram"' | grep '"enabled"' | grep -q 'true' && echo "yes" || echo "no")
        [ "$ENABLED" = "yes" ] && echo -e "  ${GREEN}✓${NC} Telegram" || echo -e "  ${DIM}✗ Telegram${NC}"
    fi

    if echo "$CONFIG" | grep -q '"discord"'; then
        ENABLED=$(echo "$CONFIG" | grep -A2 '"discord"' | grep '"enabled"' | grep -q 'true' && echo "yes" || echo "no")
        [ "$ENABLED" = "yes" ] && echo -e "  ${GREEN}✓${NC} Discord" || echo -e "  ${DIM}✗ Discord${NC}"
    fi

    if echo "$CONFIG" | grep -q '"slack"'; then
        ENABLED=$(echo "$CONFIG" | grep -A2 '"slack"' | grep '"enabled"' | grep -q 'true' && echo "yes" || echo "no")
        [ "$ENABLED" = "yes" ] && echo -e "  ${GREEN}✓${NC} Slack" || echo -e "  ${DIM}✗ Slack${NC}"
    fi

    echo ""
}

cmd_config() {
    detect_app
    log_info "Fetching config for ${WHITE}${APP_NAME}${NC}..."
    echo ""

    fly ssh console --app "$APP_NAME" -C "cat /data/moltbot.json 2>/dev/null" 2>/dev/null || log_warn "No configuration found"
    echo ""
}

cmd_add_channel() {
    local CHANNEL="$1"
    local TOKEN_VAR="$2"
    local TOKEN_PROMPT="$3"

    detect_app

    log_info "Adding ${WHITE}${CHANNEL}${NC} to ${WHITE}${APP_NAME}${NC}..."

    # Get token if needed
    if [ -n "$TOKEN_PROMPT" ]; then
        echo ""
        log_info "$TOKEN_PROMPT"
        read -sp "Token (hidden): " TOKEN
        echo ""

        if [ -z "$TOKEN" ]; then
            log_warn "No token provided. Channel will be enabled but may not work until configured."
        fi
    fi

    # Read current config
    CONFIG=$(fly ssh console --app "$APP_NAME" -C "cat /data/moltbot.json 2>/dev/null" 2>/dev/null || echo "{}")

    if [ "$CONFIG" = "{}" ] || [ -z "$CONFIG" ]; then
        log_error "No configuration found. Run the installer first."
        exit 1
    fi

    # Ensure jq is available (auto-install if needed)
    ensure_jq

    # Add channel based on type
    case "$CHANNEL" in
        whatsapp)
            NEW_CONFIG=$(echo "$CONFIG" | jq '.channels.whatsapp = {"enabled": true, "dmPolicy": "pairing", "sendReadReceipts": true, "textChunkLimit": 4000}')
            NEW_CONFIG=$(echo "$NEW_CONFIG" | jq '.plugins.entries.whatsapp = {"enabled": true}')
            ;;
        telegram)
            if [ -n "$TOKEN" ]; then
                NEW_CONFIG=$(echo "$CONFIG" | jq --arg token "$TOKEN" '.channels.telegram = {"enabled": true, "botToken": $token, "dmPolicy": "pairing"}')
            else
                NEW_CONFIG=$(echo "$CONFIG" | jq '.channels.telegram = {"enabled": true, "dmPolicy": "pairing"}')
            fi
            NEW_CONFIG=$(echo "$NEW_CONFIG" | jq '.plugins.entries.telegram = {"enabled": true}')
            ;;
        discord)
            if [ -n "$TOKEN" ]; then
                NEW_CONFIG=$(echo "$CONFIG" | jq --arg token "$TOKEN" '.channels.discord = {"enabled": true, "token": $token, "dm": {"dmPolicy": "pairing"}}')
            else
                NEW_CONFIG=$(echo "$CONFIG" | jq '.channels.discord = {"enabled": true, "dm": {"dmPolicy": "pairing"}}')
            fi
            NEW_CONFIG=$(echo "$NEW_CONFIG" | jq '.plugins.entries.discord = {"enabled": true}')
            ;;
        slack)
            if [ -n "$TOKEN" ]; then
                NEW_CONFIG=$(echo "$CONFIG" | jq --arg token "$TOKEN" '.channels.slack = {"enabled": true, "botToken": $token, "dmPolicy": "pairing"}')
            else
                NEW_CONFIG=$(echo "$CONFIG" | jq '.channels.slack = {"enabled": true, "dmPolicy": "pairing"}')
            fi
            NEW_CONFIG=$(echo "$NEW_CONFIG" | jq '.plugins.entries.slack = {"enabled": true}')
            ;;
    esac

    # Write new config
    if ! echo "$NEW_CONFIG" | fly ssh console --app "$APP_NAME" -C "cat > /data/moltbot.json"; then
        log_error "Failed to write config"
        exit 1
    fi

    log_success "Channel ${CHANNEL} added!"

    # Restart
    log_info "Restarting to apply changes..."
    MACHINE_ID=$(fly machines list --app "$APP_NAME" --json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -n "$MACHINE_ID" ]; then
        fly machines restart "$MACHINE_ID" --app "$APP_NAME" > /dev/null 2>&1
        log_success "Done! Channel ${CHANNEL} is now enabled."
    else
        log_warn "Could not restart automatically. Run: moltbot-cli.sh restart"
    fi
    echo ""
}

cmd_remove_channel() {
    local CHANNEL="$1"

    if [ -z "$CHANNEL" ]; then
        log_error "Usage: moltbot-cli.sh remove-channel <whatsapp|telegram|discord|slack>"
        exit 1
    fi

    detect_app

    log_info "Removing ${WHITE}${CHANNEL}${NC} from ${WHITE}${APP_NAME}${NC}..."

    # Read current config
    CONFIG=$(fly ssh console --app "$APP_NAME" -C "cat /data/moltbot.json 2>/dev/null" 2>/dev/null || echo "{}")

    if [ "$CONFIG" = "{}" ] || [ -z "$CONFIG" ]; then
        log_error "No configuration found"
        exit 1
    fi

    # Ensure jq is available (auto-install if needed)
    ensure_jq

    # Remove channel
    NEW_CONFIG=$(echo "$CONFIG" | jq "del(.channels.${CHANNEL}) | del(.plugins.entries.${CHANNEL})")

    # Write new config
    if ! echo "$NEW_CONFIG" | fly ssh console --app "$APP_NAME" -C "cat > /data/moltbot.json"; then
        log_error "Failed to write config"
        exit 1
    fi

    log_success "Channel ${CHANNEL} removed!"

    # Restart
    log_info "Restarting to apply changes..."
    MACHINE_ID=$(fly machines list --app "$APP_NAME" --json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -n "$MACHINE_ID" ]; then
        fly machines restart "$MACHINE_ID" --app "$APP_NAME" > /dev/null 2>&1
        log_success "Done!"
    else
        log_warn "Could not restart automatically. Run: moltbot-cli.sh restart"
    fi
    echo ""
}

cmd_update() {
    detect_app

    log_info "Updating ${WHITE}${APP_NAME}${NC} to latest MoltBot version..."
    echo ""

    # Check if we're in a moltbot directory
    if [ ! -f "fly.toml" ]; then
        log_error "Run this command from your moltbot-flyio directory"
        exit 1
    fi

    # Pull latest changes
    log_info "Pulling latest changes..."
    git pull origin main

    # Deploy
    log_info "Deploying update..."
    fly deploy --app "$APP_NAME"

    log_success "Update complete!"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Parse arguments
    COMMAND=""
    APP_NAME=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --app)
                APP_NAME="$2"
                shift 2
                ;;
            --help|-h)
                print_help
                exit 0
                ;;
            *)
                if [ -z "$COMMAND" ]; then
                    COMMAND="$1"
                else
                    EXTRA_ARG="$1"
                fi
                shift
                ;;
        esac
    done

    if [ -z "$COMMAND" ]; then
        print_help
        exit 0
    fi

    check_fly

    case "$COMMAND" in
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
            cmd_add_channel "whatsapp" "" ""
            ;;
        add-telegram)
            cmd_add_channel "telegram" "TELEGRAM_TOKEN" "Get your bot token from @BotFather on Telegram"
            ;;
        add-discord)
            cmd_add_channel "discord" "DISCORD_TOKEN" "Get your bot token from https://discord.com/developers/applications"
            ;;
        add-slack)
            cmd_add_channel "slack" "SLACK_TOKEN" "Get your bot token from https://api.slack.com/apps"
            ;;
        remove-channel)
            cmd_remove_channel "$EXTRA_ARG"
            ;;
        update)
            cmd_update
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            echo ""
            print_help
            exit 1
            ;;
    esac
}

main "$@"
