#!/usr/bin/env bash
# exp-wrapper: makes ANY program checkpoint-safe on Spot, without it knowing about AWS.
#
# Your program only sees two plain folders:
#   $OUTPUT_DIR      (/output)      write results here
#   $CHECKPOINT_DIR  (/checkpoint)  write resumable state here; read it on start
#
# This wrapper:
#   1. on start: downloads both folders from S3 (so a retried job resumes where it stopped)
#   2. runs your command
#   3. every SYNC_INTERVAL seconds: uploads both folders to S3
#   4. on shutdown signal (Spot reclaim) or normal exit: forwards the signal, then uploads a last time
#
# Needs the `aws` CLI in the image. Required env vars: RESULTS_BUCKET, EXPERIMENT, RUN_ID.
# Tip for your program: write checkpoints to a temp name and rename (atomic), so a
# half-written file is never uploaded.
set -uo pipefail

: "${RESULTS_BUCKET:?RESULTS_BUCKET not set}"
: "${EXPERIMENT:?EXPERIMENT not set}"
: "${RUN_ID:?RUN_ID not set}"
SYNC_INTERVAL="${SYNC_INTERVAL:-120}"

export OUTPUT_DIR="${OUTPUT_DIR:-/output}"
export CHECKPOINT_DIR="${CHECKPOINT_DIR:-/checkpoint}"
export ATTEMPT="${AWS_BATCH_JOB_ATTEMPT:-0}"
BASE="s3://${RESULTS_BUCKET}/runs/${EXPERIMENT}/${RUN_ID}"

mkdir -p "$OUTPUT_DIR" "$CHECKPOINT_DIR"

log() { echo "[exp-wrapper] $*" >&2; }

sync_down() {
  aws s3 sync "$BASE/output" "$OUTPUT_DIR" --only-show-errors
  aws s3 sync "$BASE/checkpoint" "$CHECKPOINT_DIR" --only-show-errors
}

sync_up() {
  aws s3 sync "$OUTPUT_DIR" "$BASE/output" --only-show-errors
  aws s3 sync "$CHECKPOINT_DIR" "$BASE/checkpoint" --only-show-errors
}

log "run=$EXPERIMENT/$RUN_ID attempt=$ATTEMPT -> $BASE"
sync_down && log "restored previous state (if any)"

"$@" &
child=$!

( while true; do sleep "$SYNC_INTERVAL"; sync_up; done ) &
loop=$!

# shellcheck disable=SC2317,SC2329  # called via trap (code differs by shellcheck version)
on_signal() {
  log "shutdown signal received, forwarding to your program"
  kill -TERM "$child" 2>/dev/null
}
trap on_signal TERM INT

wait "$child"
code=$?
# `wait` returns early when a signal arrives; keep waiting until the program really exits.
while kill -0 "$child" 2>/dev/null; do
  wait "$child"
  code=$?
done

kill "$loop" 2>/dev/null
wait "$loop" 2>/dev/null

log "program exited with code $code, final upload"
sync_up
exit "$code"
