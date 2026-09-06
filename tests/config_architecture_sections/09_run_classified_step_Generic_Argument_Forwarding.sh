section "run_classified_step Generic Argument Forwarding"

# 48a: zero-argument function still works
mock_zero_called=0
mock_zero_arg() { mock_zero_called=1; return 0; }
run_classified_step workstation "Test zero arg" mock_zero_arg
if [[ "$mock_zero_called" -eq 1 ]]; then
    pass "48a. zero-argument function works with run_classified_step"
else
    fail "48a. zero-argument function was not executed"
fi

# 48b: one argument is forwarded
mock_one_val=""
mock_one_arg() { mock_one_val="$1"; return 0; }
run_classified_step workstation "Test one arg" mock_one_arg "arg1"
if [[ "$mock_one_val" == "arg1" ]]; then
    pass "48b. single argument is forwarded cleanly"
else
    fail "48b. single argument forwarding failed: got '$mock_one_val'"
fi

# 48c: multiple arguments forwarded in exact order
mock_multi_args=()
mock_multi_arg() { mock_multi_args=("$@"); return 0; }
run_classified_step workstation "Test multi arg" mock_multi_arg "first" "second" "third"
if [[ "${#mock_multi_args[@]}" -eq 3 && "${mock_multi_args[0]}" == "first" && "${mock_multi_args[1]}" == "second" && "${mock_multi_args[2]}" == "third" ]]; then
    pass "48c. multiple arguments are forwarded in exact order"
else
    fail "48c. multiple arguments forwarding failed: ${mock_multi_args[*]}"
fi

# 48d: argument containing spaces remains one single argv element
mock_space_args=()
mock_space_func() { mock_space_args=("$@"); return 0; }
run_classified_step workstation "Test space arg" mock_space_func "hello world" "foo bar baz"
if [[ "${#mock_space_args[@]}" -eq 2 && "${mock_space_args[0]}" == "hello world" && "${mock_space_args[1]}" == "foo bar baz" ]]; then
    pass "48d. arguments containing spaces remain individual argv elements"
else
    fail "48d. whitespace splitting occurred in arguments"
fi

# 48e: empty string argument remains one single argv element
mock_empty_args=()
mock_empty_func() { mock_empty_args=("$@"); return 0; }
run_classified_step workstation "Test empty arg" mock_empty_func "" "non-empty"
if [[ "${#mock_empty_args[@]}" -eq 2 && "${mock_empty_args[0]}" == "" && "${mock_empty_args[1]}" == "non-empty" ]]; then
    pass "48e. empty-string argument is preserved as an argv element"
else
    fail "48e. empty-string argument was dropped or mishandled"
fi

# 48f: argument forwarding works for abort-class stage
mock_abort_val=""
mock_abort_func() { mock_abort_val="$1"; return 0; }
run_classified_step abort "Test abort arg" mock_abort_func "abort_target"
if [[ "$mock_abort_val" == "abort_target" ]]; then
    pass "48f. argument forwarding works for abort-class stage"
else
    fail "48f. abort-class argument forwarding failed"
fi

# 48g: argument forwarding works for workstation stage
mock_work_val=""
mock_work_func() { mock_work_val="$1"; return 0; }
run_classified_step workstation "Test workstation arg" mock_work_func "workstation_target"
if [[ "$mock_work_val" == "workstation_target" ]]; then
    pass "48g. argument forwarding works for workstation stage"
else
    fail "48g. workstation-class argument forwarding failed"
fi

# 48h: mocked execute_plan receives exact plan prefix
mock_exec_plan_prefix=""
mock_reconciler_plan() { mock_exec_plan_prefix="$1"; return 0; }
run_classified_step workstation "Reconciling configured components" mock_reconciler_plan "MY_CUSTOM_PLAN"
if [[ "$mock_exec_plan_prefix" == "MY_CUSTOM_PLAN" ]]; then
    pass "48h. mocked execute_plan receives exact plan prefix argument"
else
    fail "48h. plan prefix was not received by execute_plan: '$mock_exec_plan_prefix'"
fi

# 48i: regression test reproducing real integration call
real_plan_arg=""
real_mock_exec() { real_plan_arg="$1"; return 0; }
run_classified_step workstation "Reconciling configured components" real_mock_exec "MAIN_INSTALLER_PLAN"
if [[ "$real_plan_arg" == "MAIN_INSTALLER_PLAN" ]]; then
    pass "48i. real integration invocation forwards MAIN_INSTALLER_PLAN to execute_plan"
else
    fail "48i. real integration invocation dropped plan argument"
fi
