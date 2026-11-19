#!/usr/bin/env bash
# Tests platform/exp-wrapper.sh offline: a fake `aws` maps s3://... to a local folder.
# Covers: normal run, interruption + resume, failing program, missing config.
# Usage: tests/test_wrapper.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$ROOT/platform/exp-wrapper.sh"
EXAMPLE="$ROOT/examples/python-hello/main.py"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/s3"

cat > "$T/bin/aws" <<'EOF'
#!/usr/bin/env bash
# fake: only `aws s3 sync SRC DST`; s3://x/y -> $FAKE_S3/x/y
m() { case "$1" in s3://*) echo "$FAKE_S3/${1#s3://}" ;; *) echo "$1" ;; esac; }
[ "$1 $2" = "s3 sync" ] || exit 0
src="$(m "$3")"; dst="$(m "$4")"; mkdir -p "$dst"
[ -d "$src" ] && cp -r "$src"/. "$dst"/ 2>/dev/null
exit 0
EOF
chmod +x "$T/bin/aws"

export PATH="$T/bin:$PATH" FAKE_S3="$T/s3" RESULTS_BUCKET=b EXPERIMENT=t SYNC_INTERVAL=1
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok: $*"; }
fresh() { rm -rf "$T/o" "$T/c"; export OUTPUT_DIR="$T/o" CHECKPOINT_DIR="$T/c"; }
remote() { echo "$T/s3/b/runs/t/$RUN_ID/$1"; }

# 1) normal run: exit 0, output and checkpoint reach "S3"
export RUN_ID=normal; fresh
"$WRAPPER" python3 "$EXAMPLE" 3 >/dev/null 2>&1 || fail "normal run exited non-zero"
[ -f "$(remote output/result.json)" ] || fail "result.json not uploaded"
[ -f "$(remote checkpoint/state.json)" ] || fail "checkpoint not uploaded"
pass "normal run uploads output and checkpoint"

# 2) interruption (SIGTERM, like a Spot reclaim) then resume with empty local disk
export RUN_ID=resume; fresh
"$WRAPPER" python3 "$EXAMPLE" 8 >/dev/null 2>&1 & pid=$!
sleep 3.5
kill -TERM "$pid"
code=0; wait "$pid" || code=$?
[ "$code" -eq 143 ] || fail "expected exit 143 after SIGTERM, got $code"
[ -f "$(remote checkpoint/state.json)" ] || fail "checkpoint not uploaded on shutdown"
[ ! -f "$(remote output/result.json)" ] || fail "run should not have finished"
fresh # new machine: nothing on local disk
log="$("$WRAPPER" python3 "$EXAMPLE" 8 2>&1)" || fail "resumed run failed"
echo "$log" | grep -q "resuming from step" || fail "did not resume from checkpoint"
[ -f "$(remote output/result.json)" ] || fail "resumed run did not finish"
pass "interrupted run resumes from checkpoint on a fresh disk"

# 3) failing program: exit code propagated, partial output still uploaded
export RUN_ID=failing; fresh
code=0
# shellcheck disable=SC2016  # $OUTPUT_DIR must expand inside the child shell
"$WRAPPER" bash -c 'echo partial > "$OUTPUT_DIR/p.txt"; exit 7' >/dev/null 2>&1 || code=$?
[ "$code" -eq 7 ] || fail "expected exit 7, got $code"
[ -f "$(remote output/p.txt)" ] || fail "partial output not uploaded after failure"
pass "failure exit code propagated and partial output saved"

# 4) missing configuration is an error, not a silent no-op
code=0; env -u RUN_ID "$WRAPPER" true >/dev/null 2>&1 || code=$?
[ "$code" -ne 0 ] || fail "missing RUN_ID should fail"
pass "missing RUN_ID rejected"

echo "all wrapper tests passed"
