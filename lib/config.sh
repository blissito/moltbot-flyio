#!/bin/bash
# ============================================================================
# MoltBot Configuration Module
# Handles gathering user configuration and generating JSON config
# ============================================================================

# Configuration variables (set by gather_* functions)
APP_NAME=""
REGION=""
AI_PROVIDER=""
API_KEY=""
API_KEY_NAME=""
MODEL=""
FALLBACK_MODEL=""
GATEWAY_TOKEN=""

# Channel configuration
WHATSAPP_ENABLED="false"
TELEGRAM_ENABLED="false"
DISCORD_ENABLED="false"
SLACK_ENABLED="false"
TELEGRAM_TOKEN=""
DISCORD_TOKEN=""
SLACK_BOT_TOKEN=""
SLACK_APP_TOKEN=""

# ============================================================================
# App Name Configuration
# ============================================================================

gather_app_name() {
    local default_name="${1:-mymoltbot}"

    while true; do
        APP_NAME=$(prompt_input "App name (must be unique globally)" "$default_name")

        if [[ ! "$APP_NAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] && [[ ! "$APP_NAME" =~ ^[a-z0-9]$ ]]; then
            log_warn "App name must be lowercase, alphanumeric, and can contain hyphens"
            continue
        fi

        break
    done
}

# ============================================================================
# AI Provider Configuration
# ============================================================================

gather_ai_provider() {
    echo ""
    echo -e "${WHITE}Select AI provider:${NC}"
    echo "  1. Anthropic (Claude) - Recommended"
    echo "  2. OpenAI (GPT)"
    echo ""

    local provider_choice=$(prompt_input "Select provider (1-2)" "1")

    case "$provider_choice" in
        2) AI_PROVIDER="openai" ;;
        *) AI_PROVIDER="anthropic" ;;
    esac

    # API Key based on provider
    echo ""
    if [ "$AI_PROVIDER" = "anthropic" ]; then
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
    if [ "$AI_PROVIDER" = "anthropic" ]; then
        echo -e "${WHITE}Select Claude model:${NC}"
        echo "  1. claude-haiku-4-5    - Fastest, cheapest"
        echo "  2. claude-sonnet-4-5   - Balanced (recommended)"
        echo "  3. claude-opus-4-5     - Most capable"
        echo ""

        local model_choice=$(prompt_input "Select model (1-3)" "2")

        case "$model_choice" in
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

        local model_choice=$(prompt_input "Select model (1-3)" "2")

        case "$model_choice" in
            1) MODEL="openai/gpt-4o-mini" ;;
            2) MODEL="openai/gpt-4o" ;;
            3) MODEL="openai/o1" ;;
            *) MODEL="openai/gpt-4o" ;;
        esac
        FALLBACK_MODEL="openai/gpt-4o-mini"
    fi
}

# ============================================================================
# Channel Configuration
# ============================================================================

gather_channels() {
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

    # Show selected channels summary
    echo ""
    local selected_channels=""
    [ "$WHATSAPP_ENABLED" = "true" ] && selected_channels="${selected_channels}WhatsApp "
    [ "$TELEGRAM_ENABLED" = "true" ] && selected_channels="${selected_channels}Telegram "
    [ "$DISCORD_ENABLED" = "true" ] && selected_channels="${selected_channels}Discord "
    [ "$SLACK_ENABLED" = "true" ] && selected_channels="${selected_channels}Slack "
    log_success "Configuration complete!"
    log_info "Channels selected: ${WHITE}${selected_channels:-None}${NC}"
}

# ============================================================================
# JSON Configuration Generation
# ============================================================================

generate_config_json() {
    local gateway_token="${1:-$GATEWAY_TOKEN}"

    # Set auth profile based on provider
    local auth_profile
    if [ "$AI_PROVIDER" = "anthropic" ]; then
        auth_profile='"anthropic:default": { "mode": "token", "provider": "anthropic" }'
    else
        auth_profile='"openai:default": { "mode": "token", "provider": "openai" }'
    fi

    # Build channels config dynamically
    local channels_config=""

    if [ "$WHATSAPP_ENABLED" = "true" ]; then
        channels_config="${channels_config}\"whatsapp\": { \"enabled\": true, \"dmPolicy\": \"pairing\", \"sendReadReceipts\": true, \"textChunkLimit\": 4000 },"
    fi

    if [ "$TELEGRAM_ENABLED" = "true" ]; then
        if [ -n "$TELEGRAM_TOKEN" ]; then
            channels_config="${channels_config}\"telegram\": { \"enabled\": true, \"botToken\": \"${TELEGRAM_TOKEN}\", \"dmPolicy\": \"pairing\" },"
        else
            channels_config="${channels_config}\"telegram\": { \"enabled\": true, \"dmPolicy\": \"pairing\" },"
        fi
    fi

    if [ "$DISCORD_ENABLED" = "true" ]; then
        if [ -n "$DISCORD_TOKEN" ]; then
            channels_config="${channels_config}\"discord\": { \"enabled\": true, \"token\": \"${DISCORD_TOKEN}\", \"dm\": { \"dmPolicy\": \"pairing\" } },"
        else
            channels_config="${channels_config}\"discord\": { \"enabled\": true, \"dm\": { \"dmPolicy\": \"pairing\" } },"
        fi
    fi

    if [ "$SLACK_ENABLED" = "true" ]; then
        local slack_tokens=""
        [ -n "$SLACK_BOT_TOKEN" ] && slack_tokens="\"botToken\": \"${SLACK_BOT_TOKEN}\", "
        [ -n "$SLACK_APP_TOKEN" ] && slack_tokens="${slack_tokens}\"appToken\": \"${SLACK_APP_TOKEN}\", "
        channels_config="${channels_config}\"slack\": { \"enabled\": true, ${slack_tokens}\"dmPolicy\": \"pairing\" },"
    fi

    # Remove trailing comma
    channels_config=$(echo "$channels_config" | sed 's/,$//')

    # Build plugins entries
    local plugins_entries=""
    [ "$WHATSAPP_ENABLED" = "true" ] && plugins_entries="${plugins_entries}\"whatsapp\": { \"enabled\": true },"
    [ "$TELEGRAM_ENABLED" = "true" ] && plugins_entries="${plugins_entries}\"telegram\": { \"enabled\": true },"
    [ "$DISCORD_ENABLED" = "true" ] && plugins_entries="${plugins_entries}\"discord\": { \"enabled\": true },"
    [ "$SLACK_ENABLED" = "true" ] && plugins_entries="${plugins_entries}\"slack\": { \"enabled\": true },"
    plugins_entries=$(echo "$plugins_entries" | sed 's/,$//')

    # Generate the JSON config
    cat << EOF
{
  "gateway": {
    "port": 3000,
    "trustedProxies": ["172.16.7.18"],
    "auth": {
      "mode": "token",
      "token": "${gateway_token}"
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
      ${auth_profile}
    }
  },
  "channels": {
    ${channels_config}
  },
  "plugins": {
    "entries": {
      ${plugins_entries}
    }
  }
}
EOF
}

# ============================================================================
# Enabled Channels Summary
# ============================================================================

get_enabled_channels() {
    local channels=""
    [ "$WHATSAPP_ENABLED" = "true" ] && channels="${channels}WhatsApp, "
    [ "$TELEGRAM_ENABLED" = "true" ] && channels="${channels}Telegram, "
    [ "$DISCORD_ENABLED" = "true" ] && channels="${channels}Discord, "
    [ "$SLACK_ENABLED" = "true" ] && channels="${channels}Slack, "
    echo "$channels" | sed 's/, $//'
}
