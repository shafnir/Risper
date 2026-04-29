#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PHRASE="שלום, זה מבחן קצר בעברית."
EXPECTED_WORDS=("שלום" "מבחן" "עברית")

RISPER_ASR_HOST="${RISPER_ASR_HOST:-127.0.0.1}"
RISPER_ASR_PORT="${RISPER_ASR_PORT:-8178}"
RISPER_MODEL_PATH="${RISPER_MODEL_PATH:-$HOME/Library/Application Support/Risper/Models/ivrit-large-v3-turbo/ggml-model.bin}"
RISPER_WHISPER_SERVER="${RISPER_WHISPER_SERVER:-$ROOT_DIR/third_party/whisper.cpp/build/bin/whisper-server}"
RISPER_KEEP_SERVER="${RISPER_KEEP_SERVER:-0}"

RECORDINGS_DIR="$ROOT_DIR/recordings/asr-harness"
LOG_DIR="$ROOT_DIR/logs"
AIFF_FILE="$RECORDINGS_DIR/hebrew-known.aiff"
WAV_FILE="$RECORDINGS_DIR/hebrew-known.wav"
RESPONSE_FILE="$RECORDINGS_DIR/response.json"
SERVER_LOG="$LOG_DIR/asr-harness-whisper-server.log"
BASE_URL="http://$RISPER_ASR_HOST:$RISPER_ASR_PORT"
SERVER_PID=""
STARTED_SERVER=0

fail() {
  echo "asr_harness: $*" >&2
  exit 1
}

cleanup() {
  if [[ "$STARTED_SERVER" == "1" && -n "$SERVER_PID" && "$RISPER_KEEP_SERVER" != "1" ]]; then
    if kill -0 "$SERVER_PID" >/dev/null 2>&1; then
      kill "$SERVER_PID" >/dev/null 2>&1 || true
      wait "$SERVER_PID" >/dev/null 2>&1 || true
    fi
  fi
}

trap cleanup EXIT
trap 'trap - EXIT; cleanup; exit 130' INT
trap 'trap - EXIT; cleanup; exit 143' TERM

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || fail "missing required command: $command_name"
}

server_is_healthy() {
  local health_response
  health_response="$(curl --silent --show-error --max-time 2 "$BASE_URL/health" 2>/dev/null || true)"
  [[ "$(printf '%s' "$health_response" | jq -r '.status // empty' 2>/dev/null)" == "ok" ]]
}

port_has_listener() {
  lsof -nP -iTCP:"$RISPER_ASR_PORT" -sTCP:LISTEN -t >/dev/null 2>&1
}

wait_for_server() {
  local attempt
  for attempt in $(seq 1 120); do
    if server_is_healthy; then
      return 0
    fi

    if [[ "$STARTED_SERVER" == "1" && -n "$SERVER_PID" ]] && ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
      echo "asr_harness: whisper-server exited before becoming healthy" >&2
      tail -n 80 "$SERVER_LOG" >&2 || true
      return 1
    fi

    sleep 1
  done

  echo "asr_harness: timed out waiting for $BASE_URL/health" >&2
  tail -n 80 "$SERVER_LOG" >&2 || true
  return 1
}

generate_wav() {
  mkdir -p "$RECORDINGS_DIR"

  echo "asr_harness: generating Hebrew fixture at $WAV_FILE"
  say -v Carmit -o "$AIFF_FILE" "$PHRASE"
  ffmpeg -hide_banner -loglevel error -y -i "$AIFF_FILE" -ar 16000 -ac 1 -c:a pcm_s16le "$WAV_FILE"
}

start_server_if_needed() {
  if server_is_healthy; then
    echo "asr_harness: using existing healthy server at $BASE_URL"
    return 0
  fi

  if port_has_listener; then
    fail "port $RISPER_ASR_PORT has a listener, but $BASE_URL/health is not healthy"
  fi

  mkdir -p "$LOG_DIR"
  : > "$SERVER_LOG"

  echo "asr_harness: starting whisper-server at $BASE_URL"
  if [[ "$RISPER_KEEP_SERVER" == "1" ]]; then
    nohup "$RISPER_WHISPER_SERVER" \
      --host "$RISPER_ASR_HOST" \
      --port "$RISPER_ASR_PORT" \
      --model "$RISPER_MODEL_PATH" \
      --language he \
      > "$SERVER_LOG" 2>&1 &
  else
    "$RISPER_WHISPER_SERVER" \
      --host "$RISPER_ASR_HOST" \
      --port "$RISPER_ASR_PORT" \
      --model "$RISPER_MODEL_PATH" \
      --language he \
      > "$SERVER_LOG" 2>&1 &
  fi

  SERVER_PID="$!"
  STARTED_SERVER=1

  wait_for_server || fail "whisper-server did not become healthy"
}

transcribe() {
  local http_status

  echo "asr_harness: posting Hebrew WAV to $BASE_URL/inference"
  http_status="$(
    curl --silent --show-error \
      --max-time 180 \
      --output "$RESPONSE_FILE" \
      --write-out "%{http_code}" \
      --form "file=@$WAV_FILE" \
      --form "language=he" \
      --form "translate=false" \
      --form "no_timestamps=true" \
      --form "temperature=0.0" \
      --form "temperature_inc=0.2" \
      --form "response_format=json" \
      "$BASE_URL/inference"
  )"

  if [[ "$http_status" != "200" ]]; then
    echo "asr_harness: response body:" >&2
    cat "$RESPONSE_FILE" >&2 || true
    fail "unexpected HTTP status from /inference: $http_status"
  fi
}

validate_transcript() {
  local transcript
  local expected_word
  local matches=0

  jq empty "$RESPONSE_FILE" >/dev/null || fail "invalid JSON response in $RESPONSE_FILE"
  transcript="$(jq -r '.text // empty' "$RESPONSE_FILE" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"

  [[ -n "$transcript" ]] || fail "empty transcript in ASR response"
  [[ "$transcript" =~ [א-ת] ]] || fail "transcript does not contain Hebrew characters: $transcript"

  for expected_word in "${EXPECTED_WORDS[@]}"; do
    if [[ "$transcript" == *"$expected_word"* ]]; then
      matches=$((matches + 1))
    fi
  done

  if (( matches < 2 )); then
    fail "transcript did not contain at least two expected words (${EXPECTED_WORDS[*]}): $transcript"
  fi

  echo "asr_harness: transcript: $transcript"
  echo "asr_harness: PASS"
}

main() {
  require_command say
  require_command ffmpeg
  require_command curl
  require_command jq
  require_command lsof
  if [[ "$RISPER_KEEP_SERVER" == "1" ]]; then
    require_command nohup
  fi

  [[ -x "$RISPER_WHISPER_SERVER" ]] || fail "whisper-server is missing or not executable: $RISPER_WHISPER_SERVER"
  [[ -f "$RISPER_MODEL_PATH" ]] || fail "model file is missing: $RISPER_MODEL_PATH"

  generate_wav
  start_server_if_needed
  transcribe
  validate_transcript
}

main "$@"
