#!/usr/bin/env bash

# T55 weather failure visibility and graceful degradation contract.

set -Eeuo pipefail

section "Aurelia Weather Failure Contract"

widget_root="$ROOT/plugins/aurelia.weather"
fixture_root="$ROOT/tests/fixtures/weather-runtime"
backend_fixture_root="$ROOT/tests/fixtures/weather-backend"

weather_bin="$ROOT/bin/aurelia-weather"

if [[ -x "$weather_bin" && -f "$backend_fixture_root/fake-curl" &&
      -f "$backend_fixture_root/wttr-auto.json" &&
      -f "$backend_fixture_root/open-meteo.json" &&
      -f "$backend_fixture_root/wttr-invalid.json" ]] &&
   bash -n "$weather_bin" &&
   grep -Fq "request_json 'https://wttr.in/' --data-urlencode 'format=j1'" "$weather_bin" &&
   ! grep -Fq "format=%l" "$weather_bin" &&
   grep -Fq '.nearest_area[0]' "$weather_bin" &&
   grep -Fq 'automatic weather location response was invalid' "$weather_bin" &&
   grep -Fq -- '--connect-timeout 3' "$weather_bin" &&
   grep -Fq -- '--max-time 5' "$weather_bin"; then
    pass "[static] automatic weather follows the Omarchy-shaped full JSON location boundary with bounded transport"
else
    fail "[static] automatic weather request boundary or safety contract is incomplete"
fi

backend_runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$backend_runtime_root"' RETURN
mkdir -p -- "$backend_runtime_root/bin"
cp -- "$backend_fixture_root/fake-curl" "$backend_runtime_root/bin/curl"
chmod 0755 "$backend_runtime_root/bin/curl"

backend_output="$backend_runtime_root/auto.json"
backend_calls="$backend_runtime_root/calls"
backend_log="$backend_runtime_root/auto.log"
backend_status=0
: >"$backend_calls"
PATH="$backend_runtime_root/bin:/usr/bin:/bin" \
WEATHER_CURL_CALLS="$backend_calls" \
WEATHER_WTTR_RESPONSE="$backend_fixture_root/wttr-auto.json" \
WEATHER_FORECAST_RESPONSE="$backend_fixture_root/open-meteo.json" \
    "$weather_bin" fetch --auto --units metric >"$backend_output" 2>"$backend_log" || backend_status=$?

if [[ "$backend_status" -eq 0 ]] &&
   jq -e '.location == "Austin" and .temperature == 21.5 and
          .apparentTemperature == 20.2 and .humidity == 57 and
          .windSpeed == 12.4 and .weatherCode == 1 and
          (.forecast | length) == 3 and .forecast[0].date == "2026-09-14"' \
       "$backend_output" >/dev/null &&
   grep -Fq -- 'format=j1' "$backend_calls" &&
   ! grep -Fq -- 'format=%l' "$backend_calls" &&
   grep -Fq -- 'api.open-meteo.com/v1/forecast' "$backend_calls" &&
   [[ ! -s "$backend_log" ]]; then
    pass "[isolated-runtime] real weather backend executes the full automatic response flow and normalizes the forecast"
else
    details="status=$backend_status output=$(tr '\n' ' ' <"$backend_output") log=$(tr '\n' ' ' <"$backend_log") calls=$(tr '\n' ' ' <"$backend_calls")"
    fail "[isolated-runtime] automatic weather backend fixture failed: $details"
fi

invalid_output="$backend_runtime_root/invalid.out"
invalid_log="$backend_runtime_root/invalid.log"
invalid_status=0
: >"$backend_runtime_root/invalid-calls"
PATH="$backend_runtime_root/bin:/usr/bin:/bin" \
WEATHER_CURL_CALLS="$backend_runtime_root/invalid-calls" \
WEATHER_WTTR_RESPONSE="$backend_fixture_root/wttr-invalid.json" \
WEATHER_FORECAST_RESPONSE="$backend_fixture_root/open-meteo.json" \
    "$weather_bin" fetch --auto >"$invalid_output" 2>"$invalid_log" || invalid_status=$?
if [[ "$invalid_status" -ne 0 ]] &&
   grep -Fq 'Error: automatic weather location response was invalid' "$invalid_log"; then
    printf '%s\n' '  Expected diagnostic: automatic weather location response was invalid'
    pass "[isolated-runtime] malformed automatic weather data fails closed with an explicit diagnostic"
else
    fail "[isolated-runtime] malformed automatic weather fixture did not fail closed (status=$invalid_status log=$(tr '\n' ' ' <"$invalid_log"))"
fi

if [[ -f "$widget_root/WeatherBarWidget.qml" && -f "$fixture_root/shell.qml" ]] &&
   grep -Fq 'console.warn("[WEATHER] fetch_failed code=' "$widget_root/WeatherBarWidget.qml" &&
   grep -Fq 'conditionText = root.configured ? "Weather unavailable"' "$widget_root/WeatherBarWidget.qml" &&
   grep -Fq 'function onBarVisibleChanged' "$widget_root/WeatherBarWidget.qml" &&
   grep -Fq 'property bool refreshQueued: false' "$widget_root/WeatherBarWidget.qml" &&
   grep -Fq 'failureRetryTimer' "$widget_root/WeatherBarWidget.qml" &&
   ! grep -Fq 'function onVisibleChanged' "$widget_root/WeatherBarWidget.qml" &&
   grep -Fq 'weatherReady = true' "$widget_root/WeatherBarWidget.qml"; then
    pass "[static] Weather reports bounded backend failure and does not publish readiness on failure"
else
    fail "[static] Weather failure-state contract is incomplete"
fi

if [[ ! -x /usr/bin/qs || ! -x /usr/bin/timeout ]]; then
    skip "[isolated-runtime] Weather failure QuickShell fixture (qs or timeout unavailable)"
    return 0
fi

runtime_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_root"' RETURN
backend_root="$runtime_root/backend"
mkdir -p -- "$backend_root/bin" "$runtime_root/runtime" "$runtime_root/config" \
    "$runtime_root/state" "$runtime_root/cache"
cat >"$backend_root/bin/aurelia-weather" <<'EOF_WEATHER_FAILURE'
#!/usr/bin/env bash
printf '%s\n' 'weather-attempt' >>"$(dirname -- "$0")/../calls"
printf '%s\n' 'simulated weather timeout' >&2
exit 28
EOF_WEATHER_FAILURE
chmod 0755 "$backend_root/bin/aurelia-weather"

result_path="$runtime_root/result.json"
runtime_log="$runtime_root/runtime.log"
runtime_status=0
expected_weather_diagnostic='\[WEATHER\][[:space:]]fetch_failed[[:space:]]code=28'
: >"$result_path"
AURELIA_WEATHER_WIDGET_SOURCE="file://$widget_root/WeatherBarWidget.qml" \
AURELIA_WEATHER_BACKEND_ROOT="$backend_root" \
AURELIA_WEATHER_FAILURE_RESULT="$result_path" \
QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY="" \
XDG_RUNTIME_DIR="$runtime_root/runtime" XDG_CONFIG_HOME="$runtime_root/config" \
XDG_STATE_HOME="$runtime_root/state" XDG_CACHE_HOME="$runtime_root/cache" \
    /usr/bin/timeout --kill-after=1s 6s /usr/bin/qs --no-duplicate \
    --path "$fixture_root/shell.qml" --no-color \
    >"$runtime_log" 2>&1 || runtime_status=$?

if [[ "$runtime_status" -eq 0 ]] && [[ -s "$result_path" ]] &&
   runtime_log_is_environment_only "$runtime_log" "$expected_weather_diagnostic" &&
   jq -e '.weatherReady == false and
          .conditionText == "Weather unavailable" and
          .visible == false and
          .temperatureText == "" and
          .forecastCount == 0' "$result_path" >/dev/null &&
   [[ -f "$backend_root/calls" ]] &&
   [[ "$(wc -l <"$backend_root/calls")" -le 3 ]]; then
    pass "[isolated-runtime] non-zero Weather backend remains observable and degrades to an unavailable, non-ready widget"
else
    details="$(tr '\n' ' ' <"$runtime_log")"
    if [[ -s "$result_path" ]]; then details="$details result=$(tr '\n' ' ' <"$result_path")"; fi
    fail "[isolated-runtime] Weather failure fixture failed (status=$runtime_status): $details"
fi
