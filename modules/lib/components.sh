#!/usr/bin/env bash

# Component Registry for Fedora Hyprland Workstation.
#
# Provides a declarative, machine-oriented registry of workstation components,
# capabilities, roles, dependencies, and lifecycle adapters.
#
# Invariants:
# - No arbitrary eval or dynamic command string execution.
# - Component IDs are unique, machine-oriented, and lowercase alphanumeric with underscores.
# - Registry validates referential integrity (dependencies, conflicts, roles).
# - Deselection in customization never implies removal.
# - Remove never implies purge.

# Registered components list preserving registration order
_COMP_IDS=()

# Structured component metadata mappings
declare -g -A _COMP_DISPLAY_NAME=()
declare -g -A _COMP_CATEGORY=()
declare -g -A _COMP_DESCRIPTION=()
declare -g -A _COMP_SUPPORTED_PROFILES=()
declare -g -A _COMP_RECOMMENDED=()
declare -g -A _COMP_REQUIRED=()
declare -g -A _COMP_REMOVABLE=()
declare -g -A _COMP_DEPENDENCIES=()
declare -g -A _COMP_CONFLICTS=()
declare -g -A _COMP_PROVIDES=()
declare -g -A _COMP_REQUIRES=()
declare -g -A _COMP_ROLES=()
declare -g -A _COMP_DETECT_FN=()
declare -g -A _COMP_INSTALL_FN=()
declare -g -A _COMP_CONFIGURE_FN=()
declare -g -A _COMP_VALIDATE_FN=()
declare -g -A _COMP_REMOVE_FN=()

# Supported capability roles
SUPPORTED_ROLES=(
    "browser"
    "terminal"
    "login-shell"
    "text-editor"
    "file-manager"
)

# Supported machine profiles
SUPPORTED_PROFILES=(
    "workstation"
    "vm"
)

# Registry for executable role default adapters and state detectors
declare -g -A _ROLE_DEFAULT_ADAPTERS=()
declare -g -A _ROLE_DEFAULT_DETECTORS=()

# Check if a role has an executable system-default adapter
role_has_default_adapter() {
    local role="$1"
    [[ -n "${_ROLE_DEFAULT_ADAPTERS[$role]:-}" ]]
}

# Register an executable default adapter for a role
register_role_default_adapter() {
    local role="$1"
    local adapter_fn="$2"
    local detect_fn="${3:-}"

    _ROLE_DEFAULT_ADAPTERS["$role"]="$adapter_fn"
    if [[ -n "$detect_fn" ]]; then
        _ROLE_DEFAULT_DETECTORS["$role"]="$detect_fn"
    fi
}

# Reset role default adapters (used for test isolation)
reset_role_default_adapters() {
    _ROLE_DEFAULT_ADAPTERS=()
    _ROLE_DEFAULT_DETECTORS=()
}

# Register default role adapters for the workstation
init_default_role_adapters() {
    reset_role_default_adapters
    register_role_default_adapter "browser" "set_browser_default_adapter" "detect_browser_default_adapter"
    register_role_default_adapter "file-manager" "set_file_manager_default_adapter" "detect_file_manager_default_adapter"
}

# Reset registry state (essential for test isolation)
reset_component_registry() {
    _COMP_IDS=()
    _COMP_DISPLAY_NAME=()
    _COMP_CATEGORY=()
    _COMP_DESCRIPTION=()
    _COMP_SUPPORTED_PROFILES=()
    _COMP_RECOMMENDED=()
    _COMP_REQUIRED=()
    _COMP_REMOVABLE=()
    _COMP_DEPENDENCIES=()
    _COMP_CONFLICTS=()
    _COMP_PROVIDES=()
    _COMP_REQUIRES=()
    _COMP_ROLES=()
    _COMP_DETECT_FN=()
    _COMP_INSTALL_FN=()
    _COMP_CONFIGURE_FN=()
    _COMP_VALIDATE_FN=()
    _COMP_REMOVE_FN=()
    reset_role_default_adapters
    if declare -F init_default_role_adapters >/dev/null 2>&1; then
        init_default_role_adapters
    fi
}

# Check if a component is registered
component_exists() {
    local id="$1"
    [[ -n "${_COMP_DISPLAY_NAME[$id]:-}" ]]
}

# Register a single workstation component
# Usage:
#   register_component \
#       id "firefox" \
#       display_name "Firefox" \
#       category "Browsers" \
#       description "Mozilla Firefox" \
#       ...
register_component() {
    local id=""
    local display_name=""
    local category=""
    local description=""
    local supported_profiles="workstation vm"
    local recommended="false"
    local required="false"
    local removable="true"
    local dependencies=""
    local conflicts=""
    local provides=""
    local requires=""
    local roles=""
    local detect_fn=""
    local install_fn=""
    local configure_fn=""
    local validate_fn=""
    local remove_fn=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            id) id="$2"; shift 2 ;;
            display_name) display_name="$2"; shift 2 ;;
            category) category="$2"; shift 2 ;;
            description) description="$2"; shift 2 ;;
            supported_profiles) supported_profiles="$2"; shift 2 ;;
            recommended) recommended="$2"; shift 2 ;;
            required) required="$2"; shift 2 ;;
            removable) removable="$2"; shift 2 ;;
            dependencies) dependencies="$2"; shift 2 ;;
            conflicts) conflicts="$2"; shift 2 ;;
            provides) provides="$2"; shift 2 ;;
            requires) requires="$2"; shift 2 ;;
            roles) roles="$2"; shift 2 ;;
            detect_fn) detect_fn="$2"; shift 2 ;;
            install_fn) install_fn="$2"; shift 2 ;;
            configure_fn) configure_fn="$2"; shift 2 ;;
            validate_fn) validate_fn="$2"; shift 2 ;;
            remove_fn) remove_fn="$2"; shift 2 ;;
            *)
                printf 'ERROR: Unknown component property: %s\n' "$1" >&2
                return 1
                ;;
        esac
    done

    # Validate ID
    if [[ -z "$id" ]]; then
        printf 'ERROR: Component id must not be empty\n' >&2
        return 1
    fi
    if [[ ! "$id" =~ ^[a-z0-9_.]+$ ]]; then
        printf 'ERROR: Invalid component id: %s (must be lowercase alphanumeric, underscore, or period)\n' "$id" >&2
        return 1
    fi
    if component_exists "$id"; then
        printf 'ERROR: Duplicate component id: %s\n' "$id" >&2
        return 1
    fi

    # Validate required metadata
    if [[ -z "$display_name" ]]; then
        printf 'ERROR: Component %s missing display_name\n' "$id" >&2
        return 1
    fi
    if [[ -z "$category" ]]; then
        printf 'ERROR: Component %s missing category\n' "$id" >&2
        return 1
    fi

    # Validate booleans
    [[ "$recommended" != "true" ]] && recommended="false"
    [[ "$required" != "true" ]] && required="false"
    [[ "$removable" != "true" ]] && removable="false"

    # Required component cannot be removable
    if [[ "$required" == "true" && "$removable" == "true" ]]; then
        printf 'ERROR: Component %s is required and cannot be marked removable\n' "$id" >&2
        return 1
    fi

    # Validate supported profiles
    for p in $supported_profiles; do
        local matched=0
        for sp in "${SUPPORTED_PROFILES[@]}"; do
            if [[ "$sp" == "$p" ]]; then matched=1; break; fi
        done
        if [[ "$matched" -eq 0 ]]; then
            printf 'ERROR: Component %s specifies invalid profile: %s\n' "$id" "$p" >&2
            return 1
        fi
    done

    _COMP_IDS+=("$id")
    _COMP_DISPLAY_NAME["$id"]="$display_name"
    _COMP_CATEGORY["$id"]="$category"
    _COMP_DESCRIPTION["$id"]="$description"
    _COMP_SUPPORTED_PROFILES["$id"]="$supported_profiles"
    _COMP_RECOMMENDED["$id"]="$recommended"
    _COMP_REQUIRED["$id"]="$required"
    _COMP_REMOVABLE["$id"]="$removable"
    _COMP_DEPENDENCIES["$id"]="$dependencies"
    _COMP_CONFLICTS["$id"]="$conflicts"
    _COMP_PROVIDES["$id"]="$provides"
    _COMP_REQUIRES["$id"]="$requires"
    _COMP_ROLES["$id"]="$roles"
    _COMP_DETECT_FN["$id"]="$detect_fn"
    _COMP_INSTALL_FN["$id"]="$install_fn"
    _COMP_CONFIGURE_FN["$id"]="$configure_fn"
    _COMP_VALIDATE_FN["$id"]="$validate_fn"
    _COMP_REMOVE_FN["$id"]="$remove_fn"

    return 0
}

# Retrieve attribute for a component
get_component_attr() {
    local id="$1"
    local attr="$2"

    if ! component_exists "$id"; then
        return 1
    fi

    case "$attr" in
        display_name) printf '%s\n' "${_COMP_DISPLAY_NAME[$id]}" ;;
        category) printf '%s\n' "${_COMP_CATEGORY[$id]}" ;;
        description) printf '%s\n' "${_COMP_DESCRIPTION[$id]}" ;;
        supported_profiles) printf '%s\n' "${_COMP_SUPPORTED_PROFILES[$id]}" ;;
        recommended) printf '%s\n' "${_COMP_RECOMMENDED[$id]}" ;;
        required) printf '%s\n' "${_COMP_REQUIRED[$id]}" ;;
        removable) printf '%s\n' "${_COMP_REMOVABLE[$id]}" ;;
        dependencies) printf '%s\n' "${_COMP_DEPENDENCIES[$id]}" ;;
        conflicts) printf '%s\n' "${_COMP_CONFLICTS[$id]}" ;;
        provides) printf '%s\n' "${_COMP_PROVIDES[$id]}" ;;
        requires) printf '%s\n' "${_COMP_REQUIRES[$id]}" ;;
        roles) printf '%s\n' "${_COMP_ROLES[$id]}" ;;
        detect_fn) printf '%s\n' "${_COMP_DETECT_FN[$id]}" ;;
        install_fn) printf '%s\n' "${_COMP_INSTALL_FN[$id]}" ;;
        configure_fn) printf '%s\n' "${_COMP_CONFIGURE_FN[$id]}" ;;
        validate_fn) printf '%s\n' "${_COMP_VALIDATE_FN[$id]}" ;;
        remove_fn) printf '%s\n' "${_COMP_REMOVE_FN[$id]}" ;;
        *) return 1 ;;
    esac
}

# List all component IDs
list_component_ids() {
    printf '%s\n' "${_COMP_IDS[@]}"
}

# List all categories in order of appearance
list_component_categories() {
    local seen=()
    for id in "${_COMP_IDS[@]}"; do
        local cat="${_COMP_CATEGORY[$id]}"
        local found=0
        for s in "${seen[@]}"; do
            if [[ "$s" == "$cat" ]]; then found=1; break; fi
        done
        if [[ "$found" -eq 0 ]]; then
            seen+=("$cat")
            printf '%s\n' "$cat"
        fi
    done
}

# List components in a category
list_components_by_category() {
    local target_cat="$1"
    for id in "${_COMP_IDS[@]}"; do
        if [[ "${_COMP_CATEGORY[$id]}" == "$target_cat" ]]; then
            printf '%s\n' "$id"
        fi
    done
}

# Check if component supports a profile
component_supports_profile() {
    local id="$1"
    local profile="$2"

    local supported="${_COMP_SUPPORTED_PROFILES[$id]:-}"
    for p in $supported; do
        if [[ "$p" == "$profile" ]]; then return 0; fi
    done
    return 1
}

# Get list of components that can fulfill a role
get_role_providers() {
    local role="$1"
    local profile="${2:-}"

    for id in "${_COMP_IDS[@]}"; do
        if [[ -n "$profile" ]] && ! component_supports_profile "$id" "$profile"; then
            continue
        fi

        local comp_roles="${_COMP_ROLES[$id]:-}"
        for r in $comp_roles; do
            if [[ "$r" == "$role" ]]; then
                printf '%s\n' "$id"
                break
            fi
        done
    done
}

# Check if a component is migrated to and managed by the Component Registry
is_component_migrated() {
    local id="$1"
    component_exists "$id"
}

# Check if a capability role is migrated to and managed by the Component Registry
is_role_migrated() {
    local role="$1"
    local found=0
    for r in "${SUPPORTED_ROLES[@]}"; do
        if [[ "$r" == "$role" ]]; then
            found=1
            break
        fi
    done
    [[ "$found" -eq 1 ]]
}

# Get list of components that provide a capability token
get_capability_providers() {
    local cap="$1"
    local profile="${2:-}"

    for id in "${_COMP_IDS[@]}"; do
        if [[ -n "$profile" ]] && ! component_supports_profile "$id" "$profile"; then
            continue
        fi

        local provs="${_COMP_PROVIDES[$id]:-}"
        for p in $provs; do
            if [[ "$p" == "$cap" ]]; then
                printf '%s\n' "$id"
                break
            fi
        done
    done
}

# Validate full referential integrity of the registry
validate_component_registry() {
    if [[ "${#_COMP_IDS[@]}" -eq 0 ]]; then
        printf 'ERROR: Component registry is empty\n' >&2
        return 1
    fi

    for id in "${_COMP_IDS[@]}"; do
        # 1. Check dependencies referential integrity
        local deps="${_COMP_DEPENDENCIES[$id]:-}"
        for dep in $deps; do
            if [[ "$dep" == "$id" ]]; then
                printf 'ERROR: Component %s cannot depend on itself\n' "$id" >&2
                return 1
            fi
            if ! component_exists "$dep"; then
                printf 'ERROR: Component %s has unknown dependency: %s\n' "$id" "$dep" >&2
                return 1
            fi
        done

        # 2. Check conflicts referential integrity
        local confs="${_COMP_CONFLICTS[$id]:-}"
        for conf in $confs; do
            if [[ "$conf" == "$id" ]]; then
                printf 'ERROR: Component %s cannot conflict with itself\n' "$id" >&2
                return 1
            fi
            if ! component_exists "$conf"; then
                printf 'ERROR: Component %s has unknown conflict target: %s\n' "$id" "$conf" >&2
                return 1
            fi
            # Required components cannot conflict with other required components
            if [[ "${_COMP_REQUIRED[$id]}" == "true" && "${_COMP_REQUIRED[$conf]}" == "true" ]]; then
                printf 'ERROR: Required component %s conflicts with required component %s\n' "$id" "$conf" >&2
                return 1
            fi
        done

        # 3. Check required vs removable invariant
        if [[ "${_COMP_REQUIRED[$id]}" == "true" && "${_COMP_REMOVABLE[$id]}" == "true" ]]; then
            printf 'ERROR: Required component %s cannot be marked removable\n' "$id" >&2
            return 1
        fi

        # 4. Check capability requirements referential integrity
        local reqs="${_COMP_REQUIRES[$id]:-}"
        for req in $reqs; do
            local prov_count=0
            for other in "${_COMP_IDS[@]}"; do
                local provs="${_COMP_PROVIDES[$other]:-}"
                for p in $provs; do
                    if [[ "$p" == "$req" ]]; then
                        prov_count=$(( prov_count + 1 ))
                        break
                    fi
                done
            done
            if [[ "$prov_count" -eq 0 ]]; then
                printf 'ERROR: Component %s requires unknown capability: %s (no registered provider)\n' "$id" "$req" >&2
                return 1
            fi
        done

        # 5. Check roles declarations
        local comp_roles="${_COMP_ROLES[$id]:-}"
        for r in $comp_roles; do
            local matched_role=0
            for sr in "${SUPPORTED_ROLES[@]}"; do
                if [[ "$sr" == "$r" ]]; then matched_role=1; break; fi
            done
            if [[ "$matched_role" -eq 0 ]]; then
                printf 'ERROR: Component %s declares unsupported role: %s\n' "$id" "$r" >&2
                return 1
            fi
        done
    done

    return 0
}

###############################################################################
# Representative Component Adapters
###############################################################################

# Chromium
detect_chromium() {
    package_installed chromium || command_exists chromium
}
install_chromium_adapter() {
    if type perform_install_chromium >/dev/null 2>&1; then
        perform_install_chromium
    else
        install_dnf_packages chromium
    fi
}
remove_chromium_adapter() {
    if package_installed chromium; then
        sudo dnf remove -y chromium
    fi
}

# Firefox
detect_firefox() {
    package_installed firefox || command_exists firefox
}
install_firefox_adapter() {
    if type perform_install_firefox >/dev/null 2>&1; then
        perform_install_firefox
    else
        install_dnf_packages firefox
    fi
}
remove_firefox_adapter() {
    if package_installed firefox; then
        sudo dnf remove -y firefox
    fi
}

# Foot terminal
detect_foot() {
    command_exists foot || package_installed foot
}
install_foot_adapter() {
    install_dnf_packages foot
}

# Neovim text editor
detect_neovim() {
    command_exists nvim || package_installed neovim
}
install_neovim_adapter() {
    install_dnf_packages neovim
}
remove_neovim_adapter() {
    if package_installed neovim; then
        sudo dnf remove -y neovim
    fi
}

# Nix package manager
detect_nix() {
    if type nix_installed >/dev/null 2>&1; then
        nix_installed
    else
        package_installed nix && command_exists nix
    fi
}
install_nix_adapter() {
    if type perform_install_nix >/dev/null 2>&1; then
        perform_install_nix
    else
        install_dnf_packages nix nix-daemon
    fi
}

# devenv
detect_devenv() {
    command_exists devenv
}
install_devenv_adapter() {
    if type perform_install_devenv >/dev/null 2>&1; then
        perform_install_devenv
    elif type install_devenv >/dev/null 2>&1; then
        install_devenv
    else
        command_exists devenv
    fi
}
remove_devenv_adapter() {
    if command_exists nix; then
        nix profile remove devenv 2>/dev/null || true
    fi
}

# htop
detect_htop() {
    package_installed htop || command_exists htop
}
install_htop_adapter() {
    install_dnf_packages htop
}
remove_htop_adapter() {
    if package_installed htop; then
        sudo dnf remove -y htop
    fi
}

# quickshell
detect_quickshell() {
    # Verify the installed package satisfies:
    # 1. Exact package identity ('quickshell', not 'quickshell-git')
    # 2. Expected host architecture
    # 3. Stable release policy (reject git snapshots, carets, and prereleases)
    # 4. Approved provenance rules (reject unapproved repositories/vendors such as lionheartp)
    if command -v rpm >/dev/null 2>&1; then
        local pkg_name
        pkg_name="$(rpm -q --qf '%{NAME}\n' quickshell 2>/dev/null || true)"
        if [[ "$pkg_name" != "quickshell" ]]; then
            return 1
        fi

        local pkg_arch
        pkg_arch="$(rpm -q --qf '%{ARCH}\n' quickshell 2>/dev/null || true)"
        local exp_arch
        exp_arch="$(uname -m 2>/dev/null || echo "x86_64")"
        if [[ -n "$pkg_arch" && "$pkg_arch" != "$exp_arch" && "$pkg_arch" != "noarch" ]]; then
            return 1
        fi

        local pkg_ver
        pkg_ver="$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' quickshell 2>/dev/null || true)"
        if [[ -z "$pkg_ver" ]]; then
            return 1
        fi

        local tag_class="stable"
        if declare -F classify_release_tag >/dev/null; then
            tag_class="$(classify_release_tag "$pkg_ver")"
        elif [[ "$pkg_ver" =~ (\^|\.git|snapshot|nightly|alpha|beta|rc|preview|pre|dev) ]]; then
            tag_class="prerelease"
        fi

        if [[ "$tag_class" != "stable" ]]; then
            return 1
        fi

        # Approved provenance: check vendor if available
        local pkg_vendor
        pkg_vendor="$(rpm -q --qf '%{VENDOR}\n' quickshell 2>/dev/null || true)"
        if [[ "$pkg_vendor" == *"lionheartp"* ]]; then
            return 1
        fi

        # Check from_repo if inspectable via dnf cache
        if command -v dnf >/dev/null 2>&1; then
            local from_repo
            from_repo="$(dnf -q repoquery -C --installed quickshell --queryformat '%{from_repo}' 2>/dev/null || true)"
            if [[ -n "$from_repo" && "$from_repo" == *"lionheartp"* ]]; then
                return 1
            fi
        fi

        return 0
    fi
    command_exists qs && command_exists quickshell
}

install_quickshell_adapter() {
    install_approved_quickshell
}

validate_quickshell_adapter() {
    detect_quickshell
}

remove_quickshell_adapter() {
    if package_installed quickshell; then
        sudo dnf remove -y quickshell
    fi
}

# desktop environments
detect_noctalia() {
    command_exists noctalia || package_installed noctalia
}
install_noctalia_adapter() {
    if declare -F install_noctalia_shell >/dev/null 2>&1; then
        install_noctalia_shell
    fi
}

detect_aurelia() {
    [[ -f "${TARGET_HOME:-$HOME}/.config/aurelia/shell.qml" ]]
}
install_aurelia_adapter() {
    if declare -F deploy_aurelia_config >/dev/null 2>&1; then
        deploy_aurelia_config
    fi
}

# hotkeys providers
detect_legacy_hotkeys() {
    command_exists workstation-hotkeys
}
configure_legacy_hotkeys() {
    if declare -F set_workstation_hotkeys_provider >/dev/null 2>&1; then
        set_workstation_hotkeys_provider "legacy"
    fi
}

detect_aurelia_hotkeys() {
    [[ -f "${TARGET_HOME:-$HOME}/.config/aurelia/components/hotkeys/HotkeysWindow.qml" ]]
}
configure_aurelia_hotkeys() {
    if declare -F set_workstation_hotkeys_provider >/dev/null 2>&1; then
        set_workstation_hotkeys_provider "aurelia"
    fi
}

# file managers
detect_nautilus() {
    package_installed nautilus || command_exists nautilus
}
install_nautilus_adapter() {
    install_dnf_packages nautilus
}
remove_nautilus_adapter() {
    if package_installed nautilus; then
        sudo dnf remove -y nautilus
    fi
}

detect_thunar() {
    package_installed Thunar || command_exists thunar
}
install_thunar_adapter() {
    install_dnf_packages Thunar
}

# Register the representative components
init_default_components() {
    init_default_role_adapters

    register_component \
        id "chromium" \
        display_name "Chromium" \
        category "Browsers" \
        description "Open-source web browser" \
        supported_profiles "workstation vm" \
        recommended true \
        required false \
        removable true \
        roles "browser" \
        detect_fn "detect_chromium" \
        install_fn "install_chromium_adapter" \
        remove_fn "remove_chromium_adapter"

    register_component \
        id "firefox" \
        display_name "Firefox" \
        category "Browsers" \
        description "Mozilla Firefox web browser" \
        supported_profiles "workstation vm" \
        recommended true \
        required false \
        removable true \
        roles "browser" \
        detect_fn "detect_firefox" \
        install_fn "install_firefox_adapter" \
        remove_fn "remove_firefox_adapter"

    register_component \
        id "foot" \
        display_name "Foot" \
        category "Desktop" \
        description "Fast, lightweight Wayland terminal emulator" \
        supported_profiles "workstation vm" \
        recommended true \
        required true \
        removable false \
        roles "terminal" \
        detect_fn "detect_foot" \
        install_fn "install_foot_adapter"

    register_component \
        id "neovim" \
        display_name "Neovim" \
        category "Development" \
        description "Vim-fork focused on extensibility and usability" \
        supported_profiles "workstation vm" \
        recommended true \
        required false \
        removable true \
        roles "text-editor" \
        detect_fn "detect_neovim" \
        install_fn "install_neovim_adapter" \
        remove_fn "remove_neovim_adapter"

    register_component \
        id "nix" \
        display_name "Nix Package Manager" \
        category "Development" \
        description "Nix package manager and daemon for reproducible development" \
        supported_profiles "workstation vm" \
        recommended true \
        required false \
        removable false \
        detect_fn "detect_nix" \
        install_fn "install_nix_adapter"

    register_component \
        id "devenv" \
        display_name "devenv" \
        category "Development" \
        description "Developer environments powered by Nix" \
        supported_profiles "workstation vm" \
        recommended true \
        required false \
        removable true \
        dependencies "nix" \
        detect_fn "detect_devenv" \
        install_fn "install_devenv_adapter" \
        remove_fn "remove_devenv_adapter"

    register_component \
        id "htop" \
        display_name "htop" \
        category "Diagnostics" \
        description "Interactive process viewer and system monitor" \
        supported_profiles "workstation vm" \
        recommended true \
        required false \
        removable true \
        detect_fn "detect_htop" \
        install_fn "install_htop_adapter" \
        remove_fn "remove_htop_adapter"

    register_component \
        id "quickshell" \
        display_name "Quickshell Toolkit" \
        category "Desktop" \
        description "Flexible QtQuick desktop shell toolkit from COPR" \
        supported_profiles "workstation vm" \
        recommended false \
        required false \
        removable true \
        detect_fn "detect_quickshell" \
        install_fn "install_quickshell_adapter" \
        validate_fn "validate_quickshell_adapter" \
        remove_fn "remove_quickshell_adapter"

    register_component \
        id "desktop.environment.noctalia" \
        display_name "Noctalia Desktop Environment" \
        category "Desktop" \
        description "Wayland desktop shell powered by Noctalia" \
        supported_profiles "workstation vm" \
        recommended true \
        required false \
        removable true \
        conflicts "desktop.environment.aurelia" \
        provides "desktop_environment" \
        detect_fn "detect_noctalia" \
        install_fn "install_noctalia_adapter"

    register_component \
        id "desktop.environment.aurelia" \
        display_name "Aurelia Desktop Environment" \
        category "Desktop" \
        description "Quickshell-native modular desktop environment (Preview)" \
        supported_profiles "workstation vm" \
        recommended false \
        required false \
        removable true \
        conflicts "desktop.environment.noctalia" \
        provides "desktop_environment" \
        dependencies "quickshell" \
        detect_fn "detect_aurelia" \
        install_fn "install_aurelia_adapter"

    register_component \
        id "desktop.hotkeys.legacy" \
        display_name "Legacy Hotkeys Manager (fzf)" \
        category "Desktop" \
        description "Terminal-based shortcuts manager using fzf" \
        supported_profiles "workstation vm" \
        recommended false \
        required false \
        removable true \
        conflicts "desktop.hotkeys.aurelia" \
        provides "hotkeys_provider" \
        detect_fn "detect_legacy_hotkeys" \
        configure_fn "configure_legacy_hotkeys"

    register_component \
        id "desktop.hotkeys.aurelia" \
        display_name "Aurelia Hotkeys (Quickshell)" \
        category "Desktop" \
        description "Native graphical hotkeys component powered by Quickshell" \
        supported_profiles "workstation vm" \
        recommended true \
        required false \
        removable true \
        conflicts "desktop.hotkeys.legacy" \
        provides "hotkeys_provider" \
        dependencies "quickshell" \
        detect_fn "detect_aurelia_hotkeys" \
        configure_fn "configure_aurelia_hotkeys"

    register_component \
        id "nautilus" \
        display_name "GNOME Files (Nautilus)" \
        category "Applications" \
        description "Default file manager for GNOME" \
        supported_profiles "workstation vm" \
        recommended true \
        required false \
        removable true \
        roles "file-manager" \
        detect_fn "detect_nautilus" \
        install_fn "install_nautilus_adapter" \
        remove_fn "remove_nautilus_adapter"

    register_component \
        id "thunar" \
        display_name "Thunar File Manager" \
        category "Applications" \
        description "Lightweight file manager from XFCE" \
        supported_profiles "workstation vm" \
        recommended false \
        required false \
        removable false \
        roles "file-manager" \
        detect_fn "detect_thunar" \
        install_fn "install_thunar_adapter"
}
