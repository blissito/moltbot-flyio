#!/bin/bash
set -e

# ============================================================================
# MoltBot Fly.io Installer
# Deploy your personal AI assistant to Fly.io in minutes
#
# Usage: curl -fsSL https://raw.githubusercontent.com/blissito/moltbot-flyio/main/install.sh | bash
# ============================================================================

VERSION="2.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Symbols
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
ARROW="${CYAN}→${NC}"
WARN="${YELLOW}⚠${NC}"

# ============================================================================
# Helper Functions
# ============================================================================

print_banner() {
    echo -e "${PURPLE}"
    cat << "EOF"
    __  ___      ____  ____        __
   /  |/  /___  / / /_/ __ )____  / /_
  / /|_/ / __ \/ / __/ __  / __ \/ __/
 / /  / / /_/ / / /_/ /_/ / /_/ / /_
/_/  /_/\____/_/\__/_____/\____/\__/
    ___  ____ ___  __   ____ _  _
    |  \ |___ |__] |    |  |  \/
    |__/ |___ |    |___ |__|  /

                 by
   ___ _     _                          _
  | __(_)_ _| |_ ___ _ _ __ _ ___ ___  | |__
  | _|| \ \ /  _/ -_) '_/ _` / -_) -_) | / /
  |_| |_/_\_\\__\___|_| \__, \___\___| |_\_\
                        |___/
EOF
    echo -e "${NC}"
    echo -e "${WHITE}Version ${VERSION}${NC}"
    echo ""
}

log_info() {
    echo -e "${ARROW} $1"
}

log_success() {
    echo -e "${CHECK} $1"
}

log_warn() {
    echo -e "${WARN} $1"
}

log_error() {
    echo -e "${CROSS} $1"
}

log_step() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local result

    if [ -n "$default" ]; then
        printf "${CYAN}?${NC} ${prompt} ${WHITE}(${default})${NC}: " > /dev/tty
    else
        printf "${CYAN}?${NC} ${prompt}: " > /dev/tty
    fi
    read -r result < /dev/tty

    if [ -z "$result" ] && [ -n "$default" ]; then
        result="$default"
    fi

    echo "$result"
}

prompt_secret() {
    local prompt="$1"
    local result

    printf "${CYAN}?${NC} ${prompt}: " > /dev/tty
    read -rs result < /dev/tty
    printf "\n" > /dev/tty

    echo "$result"
}

prompt_confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local result

    if [ "$default" = "y" ]; then
        printf "${CYAN}?${NC} ${prompt} ${WHITE}(Y/n)${NC}: " > /dev/tty
    else
        printf "${CYAN}?${NC} ${prompt} ${WHITE}(y/N)${NC}: " > /dev/tty
    fi
    read -r result < /dev/tty

    result="${result:-$default}"

    [[ "$result" =~ ^[Yy]$ ]]
}

check_command() {
    command -v "$1" &> /dev/null
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

    # Check flyctl
    if check_command fly || check_command flyctl; then
        log_success "flyctl installed"
    else
        log_error "flyctl not found"
        echo ""
        log_info "Install flyctl with:"
        echo -e "  ${WHITE}curl -L https://fly.io/install.sh | sh${NC}"
        echo ""
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
# Fly.io Authentication
# ============================================================================

check_fly_auth() {
    log_step "Step 2/8: Fly.io Authentication"

    # Try to get current user
    if fly auth whoami &> /dev/null; then
        local user=$(fly auth whoami 2>/dev/null)
        log_success "Logged in as: ${WHITE}${user}${NC}"
    else
        log_warn "Not logged in to Fly.io"
        log_info "Opening browser for authentication..."
        echo ""

        fly auth login

        if fly auth whoami &> /dev/null; then
            log_success "Authentication successful!"
        else
            log_error "Authentication failed"
            exit 1
        fi
    fi
}

# ============================================================================
# Gather Configuration
# ============================================================================

gather_config() {
    log_step "Step 3/8: Configuration"

    echo -e "${WHITE}Let's configure your MoltBot deployment${NC}"
    echo ""

    # App name
    while true; do
        APP_NAME=$(prompt_input "App name (must be unique globally)" "blissmoltbot")

        if [[ ! "$APP_NAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] && [[ ! "$APP_NAME" =~ ^[a-z0-9]$ ]]; then
            log_warn "App name must be lowercase, alphanumeric, and can contain hyphens"
            continue
        fi

        break
    done

    # Region
    echo ""
    echo -e "${WHITE}Available regions:${NC}"
    echo "  iad - Virginia, USA (East)"
    echo "  sjc - San Jose, USA (West)"
    echo "  lhr - London, Europe"
    echo "  gru - Sao Paulo, Latin America"
    echo "  nrt - Tokyo, Asia"
    echo ""

    REGION=$(prompt_input "Select region" "iad")

    # Provider selection
    echo ""
    echo -e "${WHITE}Select AI provider:${NC}"
    echo "  1. Anthropic (Claude) - Recommended"
    echo "  2. OpenAI (GPT)"
    echo ""

    PROVIDER_CHOICE=$(prompt_input "Select provider (1-2)" "1")

    case "$PROVIDER_CHOICE" in
        2) PROVIDER="openai" ;;
        *) PROVIDER="anthropic" ;;
    esac

    # API Key based on provider
    echo ""
    if [ "$PROVIDER" = "anthropic" ]; then
        log_info "Get your API key from: ${WHITE}https://console.anthropic.com/settings/keys${NC}"
        API_KEY=$(prompt_secret "Anthropic API Key")
        API_KEY_NAME="ANTHROPIC_API_KEY"
    else
        log_info "Get your API key from: ${WHITE}https://platform.openai.com/api-keys${NC}"
        API_KEY=$(prompt_secret "OpenAI API Key")
        API_KEY_NAME="OPENAI_API_KEY"
    fi

    if [ -z "$API_KEY" ]; then
        log_error "API key is required"
        exit 1
    fi

    # Model selection based on provider
    echo ""
    if [ "$PROVIDER" = "anthropic" ]; then
        echo -e "${WHITE}Select Claude model:${NC}"
        echo "  1. claude-haiku-4-5    - Fastest, cheapest"
        echo "  2. claude-sonnet-4-5   - Balanced (recommended)"
        echo "  3. claude-opus-4-5     - Most capable"
        echo ""

        MODEL_CHOICE=$(prompt_input "Select model (1-3)" "2")

        case "$MODEL_CHOICE" in
            1) MODEL="anthropic/claude-haiku-4-5" ;;
            2) MODEL="anthropic/claude-sonnet-4-5" ;;
            3) MODEL="anthropic/claude-opus-4-5" ;;
            *) MODEL="anthropic/claude-sonnet-4-5" ;;
        esac
        FALLBACK_MODEL="anthropic/claude-haiku-4-5"
    else
        echo -e "${WHITE}Select OpenAI model:${NC}"
        echo "  1. gpt-4o-mini         - Fastest, cheapest"
        echo "  2. gpt-4o              - Balanced (recommended)"
        echo "  3. o1                  - Most capable"
        echo ""

        MODEL_CHOICE=$(prompt_input "Select model (1-3)" "2")

        case "$MODEL_CHOICE" in
            1) MODEL="openai/gpt-4o-mini" ;;
            2) MODEL="openai/gpt-4o" ;;
            3) MODEL="openai/o1" ;;
            *) MODEL="openai/gpt-4o" ;;
        esac
        FALLBACK_MODEL="openai/gpt-4o-mini"
    fi

    # Channel configuration
    echo ""
    echo -e "${WHITE}Select channels to enable:${NC}"
    echo ""

    WHATSAPP_ENABLED="false"
    TELEGRAM_ENABLED="false"
    DISCORD_ENABLED="false"
    SLACK_ENABLED="false"

    if prompt_confirm "Enable WhatsApp?" "y"; then
        WHATSAPP_ENABLED="true"
    fi

    if prompt_confirm "Enable Telegram?" "n"; then
        TELEGRAM_ENABLED="true"
        echo ""
        log_info "Get your bot token from: ${WHITE}@BotFather on Telegram${NC}"
        TELEGRAM_TOKEN=$(prompt_secret "Telegram Bot Token (or leave empty to configure later)")
    fi

    if prompt_confirm "Enable Discord?" "n"; then
        DISCORD_ENABLED="true"
        echo ""
        log_info "Get your bot token from: ${WHITE}https://discord.com/developers/applications${NC}"
        DISCORD_TOKEN=$(prompt_secret "Discord Bot Token (or leave empty to configure later)")
    fi

    if prompt_confirm "Enable Slack?" "n"; then
        SLACK_ENABLED="true"
        echo ""
        log_info "Get tokens from: ${WHITE}https://api.slack.com/apps${NC}"
        SLACK_BOT_TOKEN=$(prompt_secret "Slack Bot Token (xoxb-..., or leave empty)")
        SLACK_APP_TOKEN=$(prompt_secret "Slack App Token (xapp-..., or leave empty)")
    fi

    # Generate gateway token
    GATEWAY_TOKEN=$(openssl rand -hex 32)

    echo ""
    log_success "Configuration complete!"
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
# Create Fly.io Resources
# ============================================================================

create_fly_resources() {
    log_step "Step 5/8: Creating Fly.io resources"

    # Famous bot names for suggestions
    BOT_NAMES=("r2d2" "c3po" "wall-e" "hal9000" "jarvis" "ultron" "optimus" "bender" "rosie" "johnny5" "data" "bishop" "robby" "gerty" "baymax" "tars" "case" "sonny" "marvin" "ash")
    BOT_INDEX=0

    # Create app with retry on name collision
    while true; do
        # Update fly.toml with app name and region
        log_info "Configuring fly.toml..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^app = .*/app = \"${APP_NAME}\"/" fly.toml
            sed -i '' "s/^primary_region = .*/primary_region = \"${REGION}\"/" fly.toml
        else
            sed -i "s/^app = .*/app = \"${APP_NAME}\"/" fly.toml
            sed -i "s/^primary_region = .*/primary_region = \"${REGION}\"/" fly.toml
        fi

        log_info "Creating app ${WHITE}${APP_NAME}${NC}..."
        CREATE_OUTPUT=$(fly apps create "$APP_NAME" --org personal 2>&1)
        CREATE_EXIT=$?

        if [ $CREATE_EXIT -eq 0 ]; then
            log_success "App created!"
            break
        fi

        # Check if it's a name collision error
        if echo "$CREATE_OUTPUT" | grep -q "Name has already been taken"; then
            log_warn "Name '${APP_NAME}' is already taken"

            # Suggest a new name using famous bot names
            if [ $BOT_INDEX -lt ${#BOT_NAMES[@]} ]; then
                SUGGESTED_NAME="${BOT_NAMES[$BOT_INDEX]}-moltbot-$(openssl rand -hex 2)"
                BOT_INDEX=$((BOT_INDEX + 1))
            else
                SUGGESTED_NAME="moltbot-$(openssl rand -hex 4)"
            fi

            echo ""
            APP_NAME=$(prompt_input "Try a different name" "$SUGGESTED_NAME")

            if [[ ! "$APP_NAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] && [[ ! "$APP_NAME" =~ ^[a-z0-9]$ ]]; then
                log_warn "App name must be lowercase, alphanumeric, and can contain hyphens"
                continue
            fi
        else
            # Different error, show it and exit
            echo "$CREATE_OUTPUT"
            log_error "Failed to create app"
            exit 1
        fi
    done

    # Create volume
    log_info "Creating persistent volume..."
    if ! fly volumes create moltbot_data --size 1 --region "$REGION" --app "$APP_NAME" --yes 2>&1 | while read -r line; do
        echo -e "  ${line}"
    done; then
        log_error "Failed to create volume"
        exit 1
    fi

    # Verify volume was created
    log_info "Verifying volume..."
    if fly volumes list --app "$APP_NAME" 2>/dev/null | grep -q "moltbot_data"; then
        log_success "Volume created and verified!"
    else
        log_error "Volume verification failed. Please check Fly.io dashboard."
        exit 1
    fi
}

# ============================================================================
# Configure Secrets
# ============================================================================

configure_secrets() {
    log_step "Step 6/8: Configuring secrets"

    log_info "Setting ${API_KEY_NAME}..."
    fly secrets set "${API_KEY_NAME}=${API_KEY}" --app "$APP_NAME" --stage 2>&1
    log_success "API key configured!"

    log_info "Setting CLAWDBOT_GATEWAY_TOKEN..."
    fly secrets set "CLAWDBOT_GATEWAY_TOKEN=${GATEWAY_TOKEN}" --app "$APP_NAME" --stage 2>&1
    log_success "Gateway token configured!"
}

# ============================================================================
# Deploy
# ============================================================================

deploy_app() {
    log_step "Step 7/8: Deploying to Fly.io"

    log_info "This may take 2-3 minutes..."
    echo ""

    if ! fly deploy --app "$APP_NAME" 2>&1 | while read -r line; do
        # Filter and colorize output
        if [[ "$line" == *"error"* ]] || [[ "$line" == *"Error"* ]]; then
            echo -e "  ${RED}${line}${NC}"
        elif [[ "$line" == *"success"* ]] || [[ "$line" == *"Success"* ]]; then
            echo -e "  ${GREEN}${line}${NC}"
        elif [[ "$line" == *"WARNING"* ]]; then
            echo -e "  ${YELLOW}${line}${NC}"
        else
            echo -e "  ${line}"
        fi
    done; then
        log_error "Deployment failed. Check logs with: fly logs --app ${APP_NAME}"
        exit 1
    fi

    log_success "Deployment complete!"

    # Get machine ID
    MACHINE_ID=$(fly machines list --app "$APP_NAME" --json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$MACHINE_ID" ]; then
        log_warn "Could not get machine ID. You may need to manually verify memory settings."
    else
        log_success "Machine ID: ${MACHINE_ID}"
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

    # Set auth profile based on provider
    if [ "$PROVIDER" = "anthropic" ]; then
        AUTH_PROFILE='"anthropic:default": { "mode": "token", "provider": "anthropic" }'
    else
        AUTH_PROFILE='"openai:default": { "mode": "token", "provider": "openai" }'
    fi

    # Build channels config dynamically
    CHANNELS_CONFIG=""

    if [ "$WHATSAPP_ENABLED" = "true" ]; then
        CHANNELS_CONFIG="${CHANNELS_CONFIG}\"whatsapp\": { \"enabled\": true, \"dmPolicy\": \"pairing\", \"sendReadReceipts\": true, \"textChunkLimit\": 4000 },"
    fi

    if [ "$TELEGRAM_ENABLED" = "true" ]; then
        if [ -n "$TELEGRAM_TOKEN" ]; then
            CHANNELS_CONFIG="${CHANNELS_CONFIG}\"telegram\": { \"enabled\": true, \"botToken\": \"${TELEGRAM_TOKEN}\", \"dmPolicy\": \"pairing\" },"
        else
            CHANNELS_CONFIG="${CHANNELS_CONFIG}\"telegram\": { \"enabled\": true, \"dmPolicy\": \"pairing\" },"
        fi
    fi

    if [ "$DISCORD_ENABLED" = "true" ]; then
        if [ -n "$DISCORD_TOKEN" ]; then
            CHANNELS_CONFIG="${CHANNELS_CONFIG}\"discord\": { \"enabled\": true, \"token\": \"${DISCORD_TOKEN}\", \"dm\": { \"dmPolicy\": \"pairing\" } },"
        else
            CHANNELS_CONFIG="${CHANNELS_CONFIG}\"discord\": { \"enabled\": true, \"dm\": { \"dmPolicy\": \"pairing\" } },"
        fi
    fi

    if [ "$SLACK_ENABLED" = "true" ]; then
        SLACK_TOKENS=""
        [ -n "$SLACK_BOT_TOKEN" ] && SLACK_TOKENS="\"botToken\": \"${SLACK_BOT_TOKEN}\", "
        [ -n "$SLACK_APP_TOKEN" ] && SLACK_TOKENS="${SLACK_TOKENS}\"appToken\": \"${SLACK_APP_TOKEN}\", "
        CHANNELS_CONFIG="${CHANNELS_CONFIG}\"slack\": { \"enabled\": true, ${SLACK_TOKENS}\"dmPolicy\": \"pairing\" },"
    fi

    # Remove trailing comma
    CHANNELS_CONFIG=$(echo "$CHANNELS_CONFIG" | sed 's/,$//')

    # Build plugins entries
    PLUGINS_ENTRIES=""
    [ "$WHATSAPP_ENABLED" = "true" ] && PLUGINS_ENTRIES="${PLUGINS_ENTRIES}\"whatsapp\": { \"enabled\": true },"
    [ "$TELEGRAM_ENABLED" = "true" ] && PLUGINS_ENTRIES="${PLUGINS_ENTRIES}\"telegram\": { \"enabled\": true },"
    [ "$DISCORD_ENABLED" = "true" ] && PLUGINS_ENTRIES="${PLUGINS_ENTRIES}\"discord\": { \"enabled\": true },"
    [ "$SLACK_ENABLED" = "true" ] && PLUGINS_ENTRIES="${PLUGINS_ENTRIES}\"slack\": { \"enabled\": true },"
    PLUGINS_ENTRIES=$(echo "$PLUGINS_ENTRIES" | sed 's/,$//')

    # Modern config structure with agents and auth.profiles
    CONFIG_JSON=$(cat << EOF
{
  "gateway": {
    "port": 3000,
    "trustedProxies": ["172.16.7.18"],
    "auth": {
      "mode": "token",
      "token": "${GATEWAY_TOKEN}"
    },
    "controlUi": {
      "allowInsecureAuth": true
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "${MODEL}",
        "fallbacks": ["${FALLBACK_MODEL}"]
      }
    },
    "list": [{ "id": "main", "default": true }]
  },
  "auth": {
    "profiles": {
      ${AUTH_PROFILE}
    }
  },
  "channels": {
    ${CHANNELS_CONFIG}
  },
  "plugins": {
    "entries": {
      ${PLUGINS_ENTRIES}
    }
  }
}
EOF
)

    echo "$CONFIG_JSON" | fly ssh console --app "$APP_NAME" -C "tee /data/moltbot.json" > /dev/null 2>&1

    log_success "Gateway configured!"

    # Restart to apply config
    if [ -n "$MACHINE_ID" ]; then
        log_info "Restarting to apply configuration..."
        fly machines restart "$MACHINE_ID" --app "$APP_NAME" 2>&1 | tail -3

        log_info "Waiting for restart (30 seconds)..."
        sleep 30

        log_success "Configuration applied!"
    else
        log_warn "Please manually restart the machine to apply configuration"
    fi
}

# ============================================================================
# Success Message
# ============================================================================

print_success() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}                    DEPLOYMENT SUCCESSFUL!                    ${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${WHITE}Your MoltBot is ready!${NC}"
    echo ""
    echo -e "${CYAN}Dashboard URL:${NC}"
    echo -e "  ${WHITE}https://${APP_NAME}.fly.dev/?token=${GATEWAY_TOKEN}${NC}"
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
    # Build enabled channels list
    ENABLED_CHANNELS=""
    [ "$WHATSAPP_ENABLED" = "true" ] && ENABLED_CHANNELS="${ENABLED_CHANNELS}WhatsApp, "
    [ "$TELEGRAM_ENABLED" = "true" ] && ENABLED_CHANNELS="${ENABLED_CHANNELS}Telegram, "
    [ "$DISCORD_ENABLED" = "true" ] && ENABLED_CHANNELS="${ENABLED_CHANNELS}Discord, "
    [ "$SLACK_ENABLED" = "true" ] && ENABLED_CHANNELS="${ENABLED_CHANNELS}Slack, "
    ENABLED_CHANNELS=$(echo "$ENABLED_CHANNELS" | sed 's/, $//')

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
    echo -e "  - Review paired devices: ${CYAN}fly ssh console --app ${APP_NAME} -C 'cat /data/devices/paired.json'${NC}"
    echo -e "  - Rotate token if compromised: ${CYAN}fly secrets set CLAWDBOT_GATEWAY_TOKEN=\$(openssl rand -hex 32) --app ${APP_NAME}${NC}"
    echo ""
    echo -e "${WHITE}Provider: ${GREEN}${PROVIDER}${NC}"
    echo -e "${WHITE}Model: ${GREEN}${MODEL}${NC}"
    echo -e "${WHITE}Channels: ${GREEN}${ENABLED_CHANNELS:-None}${NC}"
    echo -e "${WHITE}Memory: ${GREEN}4GB${NC} (prevents OOM errors)"
    echo -e "${WHITE}Estimated monthly cost: ${GREEN}\$22-25 USD${NC} (hosting only, API usage extra)"
    echo ""
    echo -e "${WHITE}Useful commands:${NC}"
    echo -e "  ${CYAN}fly logs --app ${APP_NAME}${NC}        # View logs"
    echo -e "  ${CYAN}fly status --app ${APP_NAME}${NC}      # Check status"
    echo -e "  ${CYAN}fly ssh console --app ${APP_NAME}${NC} # SSH access"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    print_banner

    echo -e "${WHITE}This script will deploy MoltBot to Fly.io.${NC}"
    echo -e "You'll need: Fly.io account, Anthropic or OpenAI API key"
    echo ""

    if ! prompt_confirm "Ready to begin?"; then
        echo "Cancelled."
        exit 0
    fi

    check_requirements
    check_fly_auth
    gather_config
    clone_repo
    create_fly_resources
    configure_secrets
    deploy_app
    configure_gateway
    print_success
}

# Run main function
main "$@"
