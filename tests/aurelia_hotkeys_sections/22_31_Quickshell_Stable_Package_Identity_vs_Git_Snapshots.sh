section "31. Quickshell Stable Package Identity vs Git Snapshots"

# Test 31: detect_quickshell must strictly reject quickshell-git and git snapshots
(
    rpm() {
        if [[ "$*" == *"%{NAME}"* ]]; then
            printf '%s\n' "quickshell-git"
        elif [[ "$*" == *"%{VERSION}-%{RELEASE}"* ]]; then
            printf '%s\n' "0.3.1^856.git2d3b3e9-2.fc44"
        fi
    }
    if detect_quickshell; then
        fail "31. detect_quickshell accepted quickshell-git"
    else
        pass "31. stable Quickshell package identity cannot resolve to quickshell-git"
    fi
)
