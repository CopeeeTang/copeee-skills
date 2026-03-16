---
name: experiment-runner
description: "Run, monitor, recover, and babysit ML evaluation experiments end-to-end. Covers the full lifecycle: intent alignment, dry-run validation, auto-launch, checkpoint recovery, and cron-based self-healing monitoring. TRIGGER when: user wants to run/start/launch/rerun experiments or evaluations ('跑实验', '启动评测', '重跑实验'), monitor running experiments or check experiment logs ('监控实验', '看看日志', '实验卡住了'), recover from failures like 429 quota errors or process death ('从checkpoint恢复', '实验挂了', '进程死了'), set up cron/loop monitoring for long-running tasks, or do a dry-run before committing to a full run. Also trigger for 'babysit', 'experiment-runner', and when user provides monitor CLI args like 'monitor experiments/X.json --log Y --expected N'. DO NOT trigger for: analyzing/comparing existing results (tables, charts, LaTeX), writing scripts to parse result files, code review or code modification, dataset creation or preprocessing, GPU/system monitoring, training job submission (use amlt-run-job), or autonomous development tasks."
---

# Experiment Runner

Manages the full experiment lifecycle in a single flow. Two modes:

- **Setup** (interactive): Align → Dry-run → Launch → Hand off to cron monitoring
- **Monitor** (cron-invoked): Read logs with intelligence → Act if needed

## Detecting Mode

- **Setup**: Arguments describe an experiment — `"Run Gemini D on RTV"`, `"跑segment_tools在OVO上"`
- **Monitor**: Arguments start with `monitor` — `"monitor experiments/X.json --log experiments/X.log --expected 140"`

---

## Mode 1: Setup

Create a task list at the start to track progress:

```
Tasks:
- [ ] Phase 1: Align experiment intent
- [ ] Phase 2: Dry-run validation
- [ ] Phase 3: Launch experiment
- [ ] Phase 4: Set up cron monitoring
```

### Phase 1 — Align Intent

Extract from user's description:
- **Backend**: qwen / gpt4o / gemini
- **Ablation mode**: raw_frames(A) / clip_only(B) / clip_keyframes(B') / segment(C) / segment_images(C') / segment_tools(D)
- **Benchmark**: ovo-bench → `phase0c_regression.py` / rtv-bench → `rtv_bench_eval.py`
- **Dataset**: which subset JSON + expected item count
- **Output path**: result file + log file

If ambiguous, ask one clarifying question. Then confirm:

```
Experiment Plan:
  Gemini + segment_tools on RTV-Bench
  Items: 140 | Script: rtv_bench_eval.py
  Output: experiments/phase2_rtv_D_segment_tools_gemini.json
  Log:    experiments/gemini_D_rtv.log
→ Proceed with dry-run?
```

### Phase 2 — Dry-Run

Run the exact command with `--limit 2` to a temp file:

```bash
cd /home/v-tangxin/GUI/.claude/worktrees/memory/streaming-agent
source /home/v-tangxin/GUI/ml_env/bin/activate

python3 scripts/SCRIPT.py \
    --vlm-backend BACKEND --ablation-mode MODE \
    DATASET_FLAGS \
    --output /tmp/dryrun_$(date +%s).json \
    --limit 2 --verbose 2>&1 | tail -30
```

Validate output:
```bash
python3 -c "
import json, sys, glob
f = sorted(glob.glob('/tmp/dryrun_*.json'))[-1]
d = json.load(open(f))
items = d.get('per_item', [])
if not items: print('FAIL: no items'); sys.exit(1)
for it in items:
    if it.get('response') is None: print(f'FAIL: null response id={it.get(\"id\")}'); sys.exit(1)
print(f'PASS: {len(items)} items OK. Sample: {items[0].get(\"response\",\"?\")[:80]}')
"
```

If dry-run fails → diagnose, fix, re-run. Do not proceed until it passes.

### Phase 3 — Launch

```bash
nohup python3 scripts/SCRIPT.py \
    --vlm-backend BACKEND --ablation-mode MODE \
    DATASET_FLAGS \
    --output OUTPUT_PATH --verbose \
    >> LOG_PATH 2>&1 &
echo "PID: $!"
```

Verify: `sleep 3 && ps aux | grep SCRIPT | grep -v grep`

### Phase 4 — Hand Off to Cron Monitoring

Tell the user the exact loop command:

```
Experiment launched (PID XXXXX).

Set up monitoring:
  /loop 5m /experiment-runner monitor OUTPUT_PATH --log LOG_PATH --expected N
```

Update task list, report completion of setup.

---

## Mode 2: Monitor (cron-invoked)

This runs inside `/loop` via cron. Be fast when healthy, thorough when not.

### Step 1: Gather Raw Data

Run these bash commands to collect experiment state:

```bash
# 1. Progress — count completed items
python3 -c "
import json, os
for f in ['RESULT_FILE', 'CHECKPOINT_FILE']:
    if os.path.exists(f):
        d = json.load(open(f))
        items = d.get('per_item', [])
        correct = sum(1 for i in items if i.get('correct'))
        print(f'Progress: {len(items)}/EXPECTED | Accuracy: {correct}/{len(items)} ({correct/max(1,len(items))*100:.1f}%)')
        break
else:
    print('No result file yet')
"

# 2. Process alive?
ps aux | grep -E "(phase0c_regression|rtv_bench_eval)" | grep -v grep | head -3

# 3. Log freshness + recent content
stat -c 'Log modified: %Y' LOG_FILE 2>/dev/null
echo "Now: $(date +%s)"
tail -30 LOG_FILE
```

### Step 2: Read and Judge

Read the raw data above. **Use your intelligence to classify** — don't rely on regex patterns. Consider:

- Is progress advancing since last check?
- Does the log tail show normal processing or errors?
- Is the process alive?
- Are there patterns that LOOK like errors but aren't? (HTTP library debug output, retries that succeed, forced answers after round exhaustion)
- Are there subtle issues? (all answers are the same letter, accuracy dropping suspiciously, items being skipped)

### Step 3: Act Based on Classification

**HEALTHY** — Progress advancing, no errors, process alive.
```
[Monitor] HEALTHY | 85/140 (60.7%) | Acc: 55.3% | Log: 30s ago
```
Done. Exit. Cron will invoke again in N minutes.

**COMPLETE** — Items reached expected count.
```
[Monitor] ✅ COMPLETE | 140/140 | Accuracy: 65.7%
Stop the monitoring loop — experiment is done.
```

**STALE** — Log not updated >20 min, process still alive (likely hung).
→ Kill process, restart from checkpoint.

**DEAD** — Process gone, items < expected.
→ Restart from checkpoint. The checkpoint mechanism auto-skips completed items.

**API QUOTA/RATE LIMIT** — 429, quota exhausted, rate limit errors in log.
→ Wait 120 seconds, then restart from checkpoint.

**CODE BUG** — Traceback in log.
→ This is the expensive path. Read the traceback, find the source file, understand the bug, fix it minimally, verify with `py_compile`, restart.
→ Constraints: fix ONLY the crash bug. Do NOT refactor, change logic, or "improve" code.

**OOM** — CUDA out of memory, killed by OOM killer.
→ Kill GPU processes (`nvidia-smi` → find PID → kill), wait 30s, restart.

**UNKNOWN** — Something you don't recognize.
→ Print the relevant log snippet. Ask the user for guidance. Do not guess.

### Restart Procedure

To reconstruct the restart command, read the `config` field in the result JSON or the first lines of the log — they contain the original parameters.

```bash
cd /home/v-tangxin/GUI/.claude/worktrees/memory/streaming-agent
source /home/v-tangxin/GUI/ml_env/bin/activate
kill PID 2>/dev/null; sleep 2

# Checkpoint auto-resumes — just rerun the same command
nohup python3 scripts/SCRIPT.py ORIGINAL_ARGS >> LOG_PATH 2>&1 &
echo "[Monitor] Restarted PID $! from checkpoint (DONE/EXPECTED)"
```

### Monitoring Guidelines

1. **Be fast when healthy** — one-line output, exit immediately. Cron will call again.
2. **Be thorough when unhealthy** — read code, fix bugs, restart. Take the time needed.
3. **Never delete checkpoints or result files** — they are precious data.
4. **Never change experiment logic** — only fix crashes, not behavior.
5. **Track restart count** — if same error recurs 3+ times, stop and escalate to user.
6. **Log your actions** — append a line to the log when you restart or fix something, so the user sees what happened.

---

## Project Context (streaming-agent specific)

Working directory: `/home/v-tangxin/GUI/.claude/worktrees/memory/streaming-agent`
Virtual env: `source /home/v-tangxin/GUI/ml_env/bin/activate`
Python: `python3`

Checkpoint files: `{output_stem}_checkpoint.json`, auto-skip via `completed_ids` set.

Experiment scripts:
- OVO-Bench: `scripts/phase0c_regression.py --subset --video-dir --vlm-backend --ablation-mode --output`
- RTV-Bench: `scripts/rtv_bench_eval.py --anno --video-dir --vlm-backend --ablation-mode --output`
- Both support `--limit N` for dry-run, `--verbose` for detailed logging.
