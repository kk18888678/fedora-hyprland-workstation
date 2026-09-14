#!/usr/bin/env bash

# T55 repository-wide diagnostic visibility policy. This suite scans source,
# fixtures, and test code without using a line-removal pipeline of its own.

set -Eeuo pipefail

section "Aurelia Diagnostic Visibility Policy"

policy_root="$ROOT"
repository_root="$(cd -- "$policy_root/.." && pwd -P)"
policy_failure=0
policy_tmp="$(mktemp -d)"
trap 'rm -rf -- "$policy_tmp"' RETURN

false_word="false"
fileview_false_pattern="printErrors: ${false_word}"
if rg -n --hidden --glob '!.git/**' -F "$fileview_false_pattern" "$policy_root" \
    >"$policy_tmp/fileview-false.txt"; then
    cat "$policy_tmp/fileview-false.txt"
    fail "[static] FileView error reporting is disabled somewhere in the Aurelia tree"
    policy_failure=1
else
    pass "[static] every Aurelia FileView keeps error reporting enabled"
fi

fileview_count="$(rg -o 'FileView[[:space:]]*\{' --glob '*.qml' "$policy_root" | wc -l)"
fileview_error_reporting_count="$(rg -o 'printErrors[[:space:]]*:[[:space:]]*true' --glob '*.qml' "$policy_root" | wc -l)"
if [[ "$fileview_count" -eq "$fileview_error_reporting_count" ]]; then
    pass "[static] every Aurelia FileView explicitly enables error reporting"
else
    printf 'FileView blocks: %s; explicit error-reporting settings: %s\n' \
        "$fileview_count" "$fileview_error_reporting_count"
    fail "[static] at least one Aurelia FileView has no explicit error-reporting setting"
    policy_failure=1
fi

filter_prefix='grep -E'
filter_token="${filter_prefix}v"
if rg -n --hidden --glob '!.git/**' -F "$filter_token" "$policy_root" \
    >"$policy_tmp/diagnostic-filters.txt"; then
    cat "$policy_tmp/diagnostic-filters.txt"
    fail "[static] Aurelia tests still delete diagnostics with a line-removal pipeline"
    policy_failure=1
else
    pass "[static] Aurelia runtime tests do not delete diagnostics with a line-removal pipeline"
fi

empty_catch_pattern='catch[[:space:]]*\([^)]*\)[[:space:]]*\{[[:space:]]*\}'
if rg -n -U --hidden --glob '!.git/**' "$empty_catch_pattern" \
    "$policy_root" \
    >"$policy_tmp/empty-catches.txt"; then
    cat "$policy_tmp/empty-catches.txt"
    fail "[static] empty catch blocks discard Aurelia failures"
    policy_failure=1
else
    pass "[static] Aurelia production and test catch blocks are non-empty and observable"
fi

# Non-empty is not enough: a catch that only returns a default still hides the
# failure. This lightweight balanced-brace scan requires each caught block to
# emit a diagnostic or update an explicit failure/result state. It is kept in
# the policy suite so a future fallback cannot silently reintroduce the old
# pattern. The marker set intentionally names observable contracts rather than
# accepting arbitrary local assignments.
catch_observability_file() {
    local source_file="$1"
    awk '
        function delta(text, opens, closes) {
            opens = text
            closes = text
            gsub(/[^\{]/, "", opens)
            gsub(/[^\}]/, "", closes)
            return length(opens) - length(closes)
        }
        function finish(   observable) {
            body_lower = tolower(body)
            observable = body_lower ~ /console\.(info|warn|error)|lasterror|errormessage|actionerror|statusmessage|statuskind|migrationresult|recordfailure|reportfailure|pluginrejected|appendrejectedplugin|pluginloadfailed|writeresult|failed[[:space:]]*=|error[[:space:]]*=|rejected[[:space:]]*=|result\.|available[[:space:]]*=|loaded[[:space:]]*=|return[^\n]*(invalid|error)/
            if (!observable) print FILENAME ":" start ": caught failure has no diagnostic or explicit result state"
            body = ""
            active = 0
            depth = 0
        }
        {
            if (!active) {
                if ($0 ~ /catch[[:space:]]*\([^)]*\)[[:space:]]*\{/) {
                    active = 1
                    start = FNR
                    body = $0
                    tail = $0
                    sub(/^.*catch[[:space:]]*\([^)]*\)[[:space:]]*\{/, "", tail)
                    depth = 1 + delta(tail)
                    if (depth <= 0) finish()
                }
                next
            }
            body = body "\n" $0
            depth += delta($0)
            if (depth <= 0) finish()
        }
        END {
            if (active) print FILENAME ":" start ": unterminated caught failure block"
        }
    ' "$source_file"
}

catch_findings="$policy_tmp/catch-observability.txt"
: >"$catch_findings"
while IFS= read -r -d '' source_file; do
    catch_observability_file "$source_file" >>"$catch_findings"
done < <(find "$repository_root" -type f \( -name '*.qml' -o -name '*.js' \) \
    ! -path '*/.git/*' -print0 | sort -z)
if [[ -s "$catch_findings" ]]; then
    cat "$catch_findings"
    fail "[static] every caught failure records a diagnostic or explicit result state"
    policy_failure=1
else
    pass "[static] every caught failure records a diagnostic or explicit result state"
fi

qt_logging_token="QT_LOGGING_""RULES"
qt_fatal_token="QT_FATAL_""WARNINGS"
if rg -n --hidden --glob '!.git/**' -e "$qt_logging_token" -e "$qt_fatal_token" \
    "$policy_root" \
    >"$policy_tmp/qt-suppression.txt"; then
    cat "$policy_tmp/qt-suppression.txt"
    fail "[static] Qt logging or fatal-warning configuration suppression is present in Aurelia"
    policy_failure=1
else
    pass "[static] Aurelia contains no Qt logging or fatal-warning configuration suppression"
fi

# A diagnostic stream must never be sent to the null device. Ordinary stdout
# may be discarded by a pure status probe, but stderr must remain observable;
# combined stdout/stderr sinks are forbidden because they also hide warnings,
# errors, and fatal process diagnostics. Assemble the tokens so this policy
# test does not contain the forbidden source text it is required to detect.
null_device="/dev/""null"
stderr_null_pattern="2>[[:space:]]*${null_device}"
all_null_pattern="&>[[:space:]]*${null_device}"
ordered_all_null_pattern=">[[:space:]]*${null_device}[[:space:]]+2>&1"
if rg -n --hidden --glob '!.git/**' \
    -e "$stderr_null_pattern" -e "$all_null_pattern" -e "$ordered_all_null_pattern" \
    "$repository_root" >"$policy_tmp/null-device-diagnostics.txt"; then
    cat "$policy_tmp/null-device-diagnostics.txt"
    fail "[static] repository code still discards a diagnostic stream to the null device"
    policy_failure=1
else
    pass "[static] repository code preserves stderr and does not discard combined diagnostics"
fi

# Every test that actually launches QuickShell must classify its complete
# captured runtime log. A capability check for the binary alone is not a
# runtime launch and is intentionally excluded; the benchmark is a separate
# opt-in live tool rather than an aggregate suite.
unchecked_runtime_suites="$policy_tmp/unchecked-runtime-suites.txt"
: >"$unchecked_runtime_suites"
while IFS= read -r -d '' suite_file; do
    suite_name="${suite_file##*/}"
    case "$suite_name" in
        benchmark_aurelia_keybindings.sh|test_command_privilege_boundary.sh)
            continue
            ;;
    esac
    if rg -q '/usr/bin/qs' "$suite_file" &&
       ! rg -q 'runtime_log_is_environment_only|runtime_skip_if_environment_only' "$suite_file"; then
        printf '%s\n' "$suite_file" >>"$unchecked_runtime_suites"
    fi
done < <(find "$policy_root/tests" -maxdepth 1 -type f -name 'test_*.sh' -print0 | sort -z)
if [[ -s "$unchecked_runtime_suites" ]]; then
    cat "$unchecked_runtime_suites"
    fail "[static] every QuickShell-launching test consumes its complete runtime diagnostics"
    policy_failure=1
else
    pass "[static] every QuickShell-launching test consumes its complete runtime diagnostics"
fi

if [[ "$policy_failure" -ne 0 ]]; then
    exit 1
fi
