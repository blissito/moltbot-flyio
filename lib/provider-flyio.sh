#!/bin/bash
# ============================================================================
# MoltBot Fly.io Provider
# Provider implementation for Fly.io deployment
# ============================================================================

PROVIDER_NAME="flyio"
PROVIDER_DISPLAY_NAME="Fly.io"
PROVIDER_COST_ESTIMATE="\$22-25/mo"

# ============================================================================
# Provider Interface Implementation
# ============================================================================

provider_check_cli() {
    if check_command fly || check_command flyctl; then
        log_success "flyctl installed"
        return 0
    fi

    log_warn "flyctl not found. It's required for Fly.io deployments."
    echo ""

    read -p "Install flyctl now? (Y/n) " INSTALL_FLY
    if [[ "${INSTALL_FLY:-y}" =~ ^[Yy]$ ]]; then
        log_info "Installing flyctl..."
        curl -L https://fly.io/install.sh | sh

        # Add to PATH for current session
        export FLYCTL_INSTALL="${FLYCTL_INSTALL:-$HOME/.fly}"
        export PATH="$FLYCTL_INSTALL/bin:$PATH"

        if check_command fly || check_command flyctl; then
            log_success "flyctl installed!"
            return 0
        fi
    fi

    log_error "flyctl is required but not installed"
    echo -e "  Install manually: ${WHITE}curl -L https://fly.io/install.sh | sh${NC}"
    return 1
}

provider_check_auth() {
    if fly auth whoami &> /dev/null; then
        local user=$(fly auth whoami 2>/dev/null)
        log_success "Logged in as: ${WHITE}${user}${NC}"
        return 0
    else
        return 1
    fi
}

provider_login() {
    log_warn "Not logged in to Fly.io"
    log_info "Opening browser for authentication..."
    echo ""

    fly auth login

    if fly auth whoami &> /dev/null; then
        log_success "Authentication successful!"
        return 0
    else
        log_error "Authentication failed"
        return 1
    fi
}

provider_regions() {
    echo -e "${WHITE}Available regions:${NC}"
    echo "  iad - Virginia, USA (East)"
    echo "  sjc - San Jose, USA (West)"
    echo "  lhr - London, Europe"
    echo "  gru - Sao Paulo, Latin America"
    echo "  nrt - Tokyo, Asia"
    echo ""
}

provider_select_region() {
    provider_regions
    REGION=$(prompt_input "Select region" "iad")
}

provider_create_app() {
    local app_name="$1"
    local region="$2"

    # Famous bot names for suggestions
    local bot_names=("r2d2" "c3po" "wall-e" "hal9000" "jarvis" "ultron" "optimus" "bender" "rosie" "johnny5" "data" "bishop" "robby" "gerty" "baymax" "tars" "case" "sonny" "marvin" "ash")
    local bot_index=0

    # Create app with retry on name collision
    while true; do
        # Update fly.toml with app name and region
        log_info "Configuring fly.toml..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^app = .*/app = \"${app_name}\"/" fly.toml
            sed -i '' "s/^primary_region = .*/primary_region = \"${region}\"/" fly.toml
        else
            sed -i "s/^app = .*/app = \"${app_name}\"/" fly.toml
            sed -i "s/^primary_region = .*/primary_region = \"${region}\"/" fly.toml
        fi

        log_info "Creating app ${WHITE}${app_name}${NC}..."
        local create_output
        create_output=$(fly apps create "$app_name" --org personal 2>&1) || true

        if echo "$create_output" | grep -qiE "already been taken|name.*taken|already exists"; then
            log_warn "Name '${app_name}' is already taken"

            # Suggest a new name using famous bot names
            local suggested_name
            if [ $bot_index -lt ${#bot_names[@]} ]; then
                suggested_name="${bot_names[$bot_index]}-moltbot-$(openssl rand -hex 2)"
                bot_index=$((bot_index + 1))
            else
                suggested_name="moltbot-$(openssl rand -hex 4)"
            fi

            echo ""
            local input=$(prompt_input "Try a different name" "$suggested_name")

            # Normalize: lowercase, replace invalid chars with hyphens, collapse multiple hyphens
            app_name=$(echo "$input" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

            # Show if normalization changed the name
            if [ "$input" != "$app_name" ]; then
                log_info "Normalized to: ${WHITE}${app_name}${NC}"
            fi

            # Validate not empty
            if [ -z "$app_name" ]; then
                log_warn "App name cannot be empty"
                continue
            fi
        elif echo "$create_output" | grep -qi "error"; then
            echo -e "  ${RED}${create_output}${NC}"
            log_error "Failed to create app"
            return 1
        else
            log_success "App created!"
            APP_NAME="$app_name"
            break
        fi
    done

    return 0
}

provider_create_storage() {
    local app_name="$1"
    local region="$2"

    log_info "Creating persistent volume..."
    if ! fly volumes create moltbot_data --size 1 --region "$region" --app "$app_name" --yes 2>&1 | while read -r line; do
        echo -e "  ${line}"
    done; then
        log_error "Failed to create volume"
        return 1
    fi

    # Verify volume was created
    log_info "Verifying volume..."
    if fly volumes list --app "$app_name" 2>/dev/null | grep -q "moltbot_data"; then
        log_success "Volume created and verified!"
        return 0
    else
        log_error "Volume verification failed. Please check Fly.io dashboard."
        return 1
    fi
}

provider_set_secrets() {
    local app_name="$1"
    shift
    # Remaining args are KEY=VALUE pairs

    for secret in "$@"; do
        local key="${secret%%=*}"
        log_info "Setting ${key}..."
        fly secrets set "$secret" --app "$app_name" --stage 2>&1
    done

    log_success "Secrets configured!"
    return 0
}

provider_deploy() {
    local app_name="$1"

    log_info "Deploying to Fly.io..."
    echo ""

    if ! fly deploy --app "$app_name" 2>&1 | while read -r line; do
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
        log_error "Deployment failed. Check logs with: fly logs --app ${app_name}"
        return 1
    fi

    log_success "Deployment complete!"

    # Get machine ID for later use
    MACHINE_ID=$(fly machines list --app "$app_name" --json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$MACHINE_ID" ]; then
        log_warn "Could not get machine ID. You may need to manually verify settings."
    else
        log_success "Machine ID: ${MACHINE_ID}"
    fi

    return 0
}

provider_restart() {
    local app_name="$1"

    local machine_id
    machine_id=$(fly machines list --app "$app_name" --json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [ -z "$machine_id" ]; then
        log_error "Could not find machine ID"
        return 1
    fi

    log_info "Restarting ${WHITE}${app_name}${NC}..."
    fly machines restart "$machine_id" --app "$app_name"
    log_success "Restart initiated!"
    return 0
}

provider_ssh_exec() {
    local app_name="$1"
    local command="$2"

    fly ssh console --app "$app_name" -C "$command"
}

provider_write_config() {
    local app_name="$1"
    local config_json="$2"

    # Fix permissions on /data (volume might be root-owned, but container runs as node)
    fly ssh console --app "$app_name" -C "sudo chown -R node:node /data 2>/dev/null || true" > /dev/null 2>&1

    # Write config file using tee (official Fly.io method for piping to remote)
    # See: https://docs.molt.bot/platforms/fly#writing-config-via-ssh
    if ! echo "$config_json" | fly ssh console --app "$app_name" -C "tee /data/moltbot.json" > /dev/null 2>&1; then
        log_error "Failed to write config file"
        return 1
    fi

    # Verify the config was written correctly
    local written_channels
    written_channels=$(fly ssh console --app "$app_name" -C "cat /data/moltbot.json 2>/dev/null" | grep -o '"whatsapp"\|"telegram"\|"discord"\|"slack"' | tr '\n' ' ' || true)
    if [ -n "$written_channels" ]; then
        log_success "Gateway configured with channels: ${written_channels}"
    else
        log_warn "Config written but could not verify channels"
    fi

    return 0
}

provider_read_config() {
    local app_name="$1"

    fly ssh console --app "$app_name" -C "cat /data/moltbot.json 2>/dev/null" 2>/dev/null || echo "{}"
}

provider_logs() {
    local app_name="$1"

    fly logs --app "$app_name"
}

provider_status() {
    local app_name="$1"

    fly status --app "$app_name"
}

provider_get_url() {
    local app_name="$1"

    echo "https://${app_name}.fly.dev"
}

# ============================================================================
# Provider Detection
# ============================================================================

provider_detect() {
    # Check if fly.toml exists
    if [ -f "fly.toml" ]; then
        return 0
    fi
    return 1
}

provider_get_app_name() {
    if [ -f "fly.toml" ]; then
        grep "^app = " fly.toml 2>/dev/null | sed 's/app = "\(.*\)"/\1/' || true
    fi
}
