#!/bin/bash
# ============================================================================
# MoltBot Common Utilities
# Shared functions for colors, logging, prompts, and utilities
# ============================================================================

VERSION="2.1.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m' # No Color

# Symbols
CHECK="${GREEN}✓${NC}"
CROSS="${RED}✗${NC}"
ARROW="${CYAN}→${NC}"
WARN="${YELLOW}⚠${NC}"

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo -e "${ARROW} $1"
}

log_success() {
    echo -e "${CHECK} $1"
}

log_warn() {
    echo -e "${WARN} ${YELLOW}$1${NC}"
}

log_error() {
    echo -e "${CROSS} ${RED}$1${NC}"
}

log_step() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ============================================================================
# Prompt Functions
# ============================================================================

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
        printf "${CYAN}?${NC} ${prompt} ${DIM}(Y/n, enter: Yes)${NC} " > /dev/tty
    else
        printf "${CYAN}?${NC} ${prompt} ${DIM}(y/N, enter: No)${NC} " > /dev/tty
    fi
    read -r result < /dev/tty

    result="${result:-$default}"

    # Show what was selected
    if [[ "$result" =~ ^[Yy]$ ]]; then
        echo -e "  ${GREEN}✓${NC} Yes" > /dev/tty
        return 0
    else
        echo -e "  ${DIM}✗ No${NC}" > /dev/tty
        return 1
    fi
}

# ============================================================================
# Utility Functions
# ============================================================================

check_command() {
    command -v "$1" &> /dev/null
}

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

# ============================================================================
# Dependency Management
# ============================================================================

ensure_jq() {
    if command -v jq &> /dev/null; then
        return 0
    fi

    log_warn "jq not found. It's required for configuration management."
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
# Script Directory Detection
# ============================================================================

# Get the directory where this script is located
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [ -h "$source" ]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    echo "$(cd -P "$(dirname "$source")" && pwd)"
}
