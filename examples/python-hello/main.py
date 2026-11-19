"""Tiny test experiment: counts to N, one step per second, and can resume after a restart.

Uses only plain folders; it knows nothing about AWS.
"""
import json
import os
import sys
import time

out_dir = os.environ.get("OUTPUT_DIR", "./output")
ckpt_dir = os.environ.get("CHECKPOINT_DIR", "./checkpoint")
os.makedirs(out_dir, exist_ok=True)
os.makedirs(ckpt_dir, exist_ok=True)

total = int(sys.argv[1]) if len(sys.argv) > 1 else 20
ckpt_file = os.path.join(ckpt_dir, "state.json")

start = 0
if os.path.exists(ckpt_file):
    start = json.load(open(ckpt_file))["step"]
    print(f"resuming from step {start} (attempt {os.environ.get('ATTEMPT', '0')})", flush=True)

for step in range(start, total):
    time.sleep(1)
    print(f"step {step + 1}/{total}", flush=True)
    # write to a temp file, then rename: a half-written checkpoint is never uploaded
    json.dump({"step": step + 1}, open(ckpt_file + ".tmp", "w"))
    os.replace(ckpt_file + ".tmp", ckpt_file)

with open(os.path.join(out_dir, "result.json"), "w") as f:
    json.dump({"steps": total, "done": True}, f)
print("done", flush=True)
