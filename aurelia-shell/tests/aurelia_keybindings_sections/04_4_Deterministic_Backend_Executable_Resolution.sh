section "4. Deterministic Backend Executable Resolution"

# 4.1: KeybindingsModel prefers canonical and supports the fixed upgrade bridge
qml_model="$ROOT/components/keybindings/KeybindingsModel.qml"
if [[ -f "$qml_model" ]] &&
   grep -q '/usr/local/bin/aurelia-shell-keybindings' "$qml_model" &&
   grep -q '/usr/local/bin/workstation-keybindings' "$qml_model" &&
   grep -q 'canonicalBackendCheck' "$qml_model" &&
   grep -q 'compatibilityBackendCheck' "$qml_model"; then
    pass "4.1 KeybindingsModel prefers canonical backend with fixed legacy migration bridge"
else
    fail "4.1 KeybindingsModel missing canonical-to-legacy migration resolution"
fi

# 4.2: Stale ~/.local/bin cannot shadow managed backend; canonical wins over legacy
res_order="$(python3 -c '
with open("'"$qml_model"'") as f:
    content = f.read()
# Production QML has fixed system paths only; canonical is checked first.
idx_usr = content.find("/usr/local/bin/aurelia-shell-keybindings")
idx_legacy = content.find("/usr/local/bin/workstation-keybindings")
idx_home = content.find(".local/bin/aurelia-shell-keybindings")
if idx_usr != -1 and idx_legacy != -1 and idx_usr < idx_legacy and idx_home == -1 and "command -v" not in content:
    print("RESOLUTION_OK")
else:
    print("SHADOW_RISK")
')"
if [[ "$res_order" == "RESOLUTION_OK" ]]; then
    pass "4.2 canonical system backend wins; only fixed legacy bridge is permitted"
else
    fail "4.2 production QML backend resolution has an unsafe or unordered shadow path"
fi
