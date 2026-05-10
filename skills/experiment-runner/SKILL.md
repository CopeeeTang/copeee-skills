---
name: experiment-runner
description: "Run, monitor, recover, and babysit ML evaluation experiments end-to-end. Covers the full lifecycle: intent alignment, dry-run validation, auto-launch, checkpoint recovery, real-time/cron-based self-healing monitoring, and post-completion validation. TRIGGER when: user wants to run/start/launch/rerun experiments or evaluations, monitor running experiments or check experiment logs, recover from failures like 429 quota errors or process death, set up monitoring for long-running tasks, or do a dry-run before committing to a full run. Also trigger for 'babysit', 'experiment-runner', and when user provides monitor CLI args like 'monitor experiments/X.json --log Y --expected N'. DO NOT trigger for: analyzing/comparing existing results (tables, charts, LaTeX), writing scripts to parse result files, code review or code modification, dataset creation or preprocessing, GPU/system monitoring, training job submission (use amlt-run-job), or autonomous development tasks."
---
> **Environment placeholders** (replace these in your shell/env, or override per-call):
> - `${PROJECT_ROOT}` — your repo root containing the eval scripts and `experiments/` dir
> - `${VENV_DIR}` — your Python virtualenv directory (must contain `bin/activate`)
> - `${ML_PROXY_BASE}` — your Azure / OpenAI-compatible proxy base URL (e.g. `http://your-proxy:9999`)
> - `${USER_HOME}` — typically `$HOME`
>
> This skill was generalized from a streaming-video-agent project; commands and `phase0c_regression.py` style script names are illustrative — substitute your own.



# Experiment Runner

Manages the full experiment lifecycle in a single flow. Four modes:

- **Setup** (interactive): Align -> Dry-run -> Launch -> Monitor
- **Monitor-Realtime** (default after launch): Use Monitor tool to stream stdout in real-time, react instantly to errors
- **Monitor-Loop** (for long/multi experiments): Periodic cron-based checking via `/loop`
- **Validate** (post-completion): Check results for data quality issues before declaring success
- **Ablation** (P0 add, 2026-04-15): Multi-experiment ablation series with config-drift preflight, plan-conformance check, and baseline-variance verdicts

---

## Core Principles (read first — all modes)

These are distilled from the D-mode refactor 2026-04-14 failure and Anthropic's multi-agent guidance. Violate at your peril.

### P1. Config drift is the #1 failure mode for ablation
Any field that affects Phase A cache key (`fps`, `resize_mode`, `clip_delta thresholds`, `summary_prompt_variant`, `cache_version`) MUST match the baseline unless intentionally changed. A single silent drift → `cache_hit_rate = 0%` → 2h+ wasted. Always run Preflight Config Drift Check before launching an ablation experiment.

### P2. Plan conformance != metric pass
Metric-only evaluators miss "code was changed but plan was not realized" (e.g. `observe()` stub not wired into agent_loop). Before judging a Δmacro, verify the code diff against the plan: does the specific function referenced in the plan actually contain the intended logic? `grep -n` + short targeted unit test beats reading a 1000-line PR.

### P3. Do not delegate decisions to subagents
Subagents are stateless per invocation. They cannot hold "E0-rerun showed 1.3pp is noise, so 2pp is our floor" across turns. Decisions that require cross-file/cross-session context (go/halt, verdict thresholds, root-cause diagnosis) belong to the main agent or the human. Subagents should run **narrow, assertion-backed tasks**: run-this-config, parse-this-log, grep-this-function. Input/output types should be JSON-serializable.

### P4. Multi-agent fits parallel exploration, not serial decision chains
Anthropic's own multi-agent research system parallelizes **independent search/exploration**; the lead agent synthesizes and decides. An ablation pipeline (E0→E1→E2…) is serial with cross-phase memory — spawning Executor/Evaluator/Orchestrator loops for it is an antipattern. For ablation: single main agent + preflight scripts + checkpoint reviews.

### P5. Plan is static; code HEAD is dynamic — reconcile before executing
The plan doc was correct at write time. Before starting any phase, run: `git log -5`, verify referenced files still exist at the assumed paths, read the actual `Segment`/`config.py` signatures. Do NOT code from plan alone. Survey → reconcile → implement.

### P6. Long-running processes must survive worktree/session churn
`nohup python3 ...` inside `.claude/worktrees/<branch>/` dies when the worktree is cleaned or the session ends. Use `setsid nohup ... < /dev/null & disown` with log paths **outside** the worktree. Or use `tmux`/`screen` for >1h jobs.

### P7. Fix the root cause, don't re-launch
If an experiment crashed, a second launch with the same config is almost always wrong. Diagnose first: log tail, `ps`, `du` on cache dir, process kill reason (`dmesg | tail`, OOM killer, SIGTERM). Rule: **same error 2 times in a row → stop and investigate, do not attempt a third run**.

## 默认值与极简 CLI (2026-04-22 起)

**所有默认值由分层 YAML 管理**，不再允许每个实验 yaml 手抄字段。真源：`streaming-agent/experiments/configs/_defaults/`

合并顺序（低→高优先级）：
```
global.yaml::mode_defaults[MODE]
  → _defaults/{benchmark}.yaml
  → _defaults/models/{model}.yaml   # qwen 特例 → online
  → 用户 yaml (可选)
  → CLI flags (--protocol 等 / --set)
```

### 默认值速查表（用户确认 2026-04-22）

| Mode | 采样 | 帧数 | tools |
|------|------|------|-------|
| A (raw_frames) | uniform | **48** (硬上限) | — |
| B (clip_keyframes) | CLIP 关键帧 (每 segment 全注入) | 动态 | — |
| C (segment) | 1 fps, 提问点往前退 5 秒 | **5** | — |
| D (segment_tools) | 同 C | **5** | **recall+diff+timeline, max_rounds=5** |

| Benchmark | 默认 protocol | 备注 |
|-----------|---------------|------|
| OVO | offline | online 需显式 `--protocol online` |
| RTV | offline | 修复 2026-04-21 误跑 online 的 bug |
| LV  | offline | — |

| Model | 覆盖 | 原因 |
|-------|------|------|
| qwen | protocol=online, workers=1 | 本地 GPU 推理 |

### 极简 CLI（推荐用法）

```bash
# 最小命令：benchmark + mode + model + n
python3 streaming-agent/scripts/run_experiment.py \
  --benchmark rtv --mode D --model gpt4o --n 140

# 显式覆盖 protocol
python3 streaming-agent/scripts/run_experiment.py \
  --benchmark ovo --mode D --model qwen --protocol offline --n 100

# 仅校验（打印合并后 config，不跑 API）
python3 streaming-agent/scripts/run_experiment.py \
  --benchmark rtv --mode D --model gpt4o --n 3 --validate-only
```

### 启动前纪律

1. **先 `--validate-only`**：主 agent 必须先跑一次 validate-only，grep 确认 `protocol` / `max_context_frames` / `max_tool_calls` 等关键字段等于预期（匹配上表）
2. **不允许在 yaml 里硬写默认值**：新写用户 yaml 只覆盖差异字段（实验名、数据集切片、特殊 prompt），默认值全部继承
3. **修改默认值 = 改 `_defaults/*.yaml`**：禁止在实验 yaml 里漂移默认值，否则下次对比实验会中毒
4. **输出目录强制 benchmark 前缀**：`output.root` 必须以 `experiments/{ovo,rtv,lv}/` 开头，不得散落到顶层（2026-04-22 之前的漂移已归档）

## Detecting Mode

- **Setup**: Arguments describe an experiment -- `"Run Gemini D on RTV"`, `"run segment_tools on OVO"`
- **Monitor**: Arguments start with `monitor` -- `"monitor experiments/X.json --log experiments/X.log --expected 140"`
- **Validate**: Arguments start with `validate` -- `"validate experiments/result.json"`
- **Ablation**: Arguments describe a multi-experiment series, or reference a phase plan -- `"run E3 from phase-L1a.md"`, `"run ablation E1→E5"`, `"launch next phase of d-mode refactor"`. See Mode 5 below.

---

## Mode 1: Setup

Create a task list at the start to track progress:

```
Tasks:
- [ ] Phase 1: Align experiment intent
- [ ] Phase 2: Dry-run validation
- [ ] Phase 3: Launch experiment
- [ ] Phase 4: Real-time monitoring (or hand off to /loop for long runs)
- [ ] Phase 5: Post-completion validation
```

### Phase 1 -- Align Intent

Extract from user's description:
- **Backend**: qwen / gpt4o / claude / gemini / o4mini / o3 / gpt52
- **Ablation mode**: raw_frames(A) / clip_only(B) / clip_keyframes(B') / segment(C) / segment_images(C') / segment_tools(D)
- **Benchmark**: ovo-bench / rtv-bench / lv-bench / video-mme
- **Dataset**: which subset JSON + expected item count
- **Output path**: result file + log file
- **API path**: proxy (default), TRAPI (`GPT4O_USE_TRAPI=1`), or **dual** (proxy+TRAPI parallel, `dual_backend: true`) -- check proxy health first


#### Claude backend (`vlm_backend=claude`)

- Uses local Copilot reverse proxy at `http://127.0.0.1:4142`
- Default model: `claude-sonnet-4.6`
- Payload format for images is **OpenAI chat-completions image_url blocks**, not Anthropic `image` blocks and not Copilot SDK `attachments`
- Verified 2026-04-21: visual requests work and multi-image requests succeeded up to **64 images/request**
- Recommended experiment cap: `max_context_frames <= 64`

If ambiguous, ask one clarifying question. Then confirm:

```
Experiment Plan:
  Gemini + segment_tools on RTV-Bench
  Items: 140 | Script: rtv_bench_eval.py
  Output: experiments/phase2_rtv_D_segment_tools_gemini.json
  Log:    experiments/gemini_D_rtv.log
  API:    proxy (default) | TRAPI fallback: GPT4O_USE_TRAPI=1 | dual: execution.dual_backend=true
-> Proceed with dry-run?
```

#### Pre-flight: Proxy Health Check (gpt4o/claude/o4mini/o3/gpt52 backends)

Before launching any experiment using Azure proxy backends, verify the proxy is alive:

```bash
curl -s -o /dev/null -w "%{http_code}" --max-time 5 ${ML_PROXY_BASE}/v1/models 2>/dev/null || echo "TIMEOUT"
```

- `200`: Proxy healthy, proceed normally
  - **Recommended**: Use `dual_backend: true` in YAML (or `GPT4O_DUAL_BACKEND=1`) to run proxy+TRAPI in parallel for ~1.5x Phase A throughput
  - With dual: increase `max_concurrent_vlm` to 30 (auto-splits: proxy=20, TRAPI=10)
- `TIMEOUT` / non-200: Proxy down. Options:
  - `GPT4O_USE_TRAPI=1` — single TRAPI endpoint (lower burst limit, run serially)
  - `dual_backend: true` — still works, auto circuit-breaks proxy and routes all to TRAPI
  - TRAPI uses Azure AD auth via `AzureCliCredential`, model remapped to `gpt-4o_2024-11-20`

### Phase 2 -- Dry-Run

Run the exact command with `--limit 2` to a temp file:

```bash
cd ${PROJECT_ROOT}
source ml_env/bin/activate

# 推荐（2026-04-22 起）：极简 CLI
python3 streaming-agent/scripts/run_experiment.py \
    --benchmark BENCH --mode MODE --model BACKEND \
    --n 2 --validate-only

# Legacy shim 仍可用
python3 streaming-agent/scripts/SCRIPT.py \
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

#### Backward max_time Verification (OVO-Bench only)

After dry-run, verify backward tasks use `realtime` as max_time (data leak fix from commit 44d4924):

```bash
python3 -c "
import json, glob
f = sorted(glob.glob('/tmp/dryrun_*.json'))[-1]
d = json.load(open(f))
BACKWARD = {'EPM', 'ASI', 'HLD'}
for it in d.get('per_item', []):
    task = it.get('task_type', '')
    if task in BACKWARD:
        mt = it.get('max_time')
        rt = it.get('realtime')
        if mt is None or (rt is not None and abs(mt - rt) > 0.1):
            print(f'FAIL: Backward task {task} id={it.get(\"id\")} max_time={mt} realtime={rt}')
            break
else:
    print('PASS: All backward tasks use realtime as max_time')
"
```

If this check fails, ensure you are running code from commit `44d4924` or later.

If dry-run fails -> diagnose, fix, re-run. Do not proceed until it passes.

### Phase 3 -- Launch

**Use `setsid` + log outside worktree** so the process survives worktree cleanup and session close:

```bash
# Log path MUST be outside any .claude/worktrees/ directory
LOG_PATH=${PROJECT_ROOT}/logs/experiment_$(date +%Y%m%d_%H%M%S).log

setsid nohup python3 scripts/SCRIPT.py \
    --vlm-backend BACKEND --ablation-mode MODE \
    DATASET_FLAGS \
    --output OUTPUT_PATH --verbose \
    >> $LOG_PATH 2>&1 < /dev/null &
PID=$!
disown $PID
echo "PID: $PID  LOG: $LOG_PATH"
```

Verify: `sleep 3 && ps -p $PID -o pid,ppid,pgid,sid,stat,cmd`
The `SID != parent-shell-SID` proves setsid worked — the process won't die with the shell/worktree.

> **Why**: `nohup` alone detaches from the controlling tty but keeps the same session. When a `.claude/worktrees/<branch>/` is cleaned up or Claude Code session ends, its process group gets SIGTERM. `setsid` moves the process into its own session so this doesn't propagate. Burned 2h on this in d-mode refactor 2026-04-14.

**Workers recommendation** (updated Round 15):

| Backend | precompute_workers | qa_workers | Notes |
|---------|:-----------------:|:----------:|-------|
| gpt4o   | **20** (not 50!)  | 8-12       | Actual concurrency = precompute_workers x segment_parallel_workers(8) |
| gpt4o (dual) | **25-30**   | 12-15      | With `dual_backend: true` + `max_concurrent_vlm: 30` |
| o4mini  | 10-20             | 5-10       | Reasoning model, keep qa_workers <= 10 |
| o4mini (dual) | **20-25** | 5-10       | Phase A dual, Phase B TRAPI-only (keeps thinking_log) |
| o3      | 5                 | 1-5        | High cost |
| gpt52   | 10-20             | 5-10       | Latest reasoning model |
| gemini  | 10-20             | 10-30      | Flash/Pro |
| qwen    | **1**             | **1**      | GPU-bound, forced serial |

### Phase 4 -- Monitor (choose strategy based on experiment scale)

#### Strategy A: Real-time Monitor (DEFAULT -- for single experiments)

Use the **Monitor tool** to stream the background process stdout in real-time.
This is the preferred approach for most experiments because:
- Errors are detected **immediately** (not 5 minutes later)
- No token waste from periodic polling
- Claude can react to problems as they happen

```
1. Launch experiment with Bash(run_in_background: true):
   python3 scripts/SCRIPT.py ... 2>&1 | tee LOG_PATH

2. Immediately use Monitor tool on the background process
   -> Each stdout line streams as an event
   -> Watch for errors, progress updates, completion

3. On error -> diagnose, fix, restart (same as Mode 2 recovery logic)
4. On completion -> run Phase 5 validation, then report results
```

When to use: Single experiment, expected runtime < 60 minutes, user is present.

#### Strategy B: Loop Monitoring (for long/multi/unattended experiments)

Hand off to `/loop` for periodic cron-based monitoring. Use this when:
- Experiment runs **> 1 hour** (user may leave or switch tasks)
- Running **multiple experiments** in parallel
- User explicitly asks for unattended monitoring
- User plans to **close the session** and check back later

```
Experiment launched (PID XXXXX).

Set up monitoring:
  /loop 5m /experiment-runner monitor OUTPUT_PATH --log LOG_PATH --expected N
```

**Decision rule**: Default to Strategy A. Only suggest Strategy B if the user says
"I'll do something else", "babysit it for me", "unattended", or if estimated runtime > 60 min.

### Phase 5 -- Post-Completion Validation

**CRITICAL: Always run this after experiment completes, before declaring success.**

This phase catches silent data quality issues that caused wrong conclusions in the past (Round 4/5: null pollution; Round 13: backward data leak; Round 14: cache stale warnings).

```bash
python3 -c "
import json, sys

f = 'RESULT_FILE'
d = json.load(open(f))
items = d.get('per_item', [])
total = len(items)

# 1. Null rate check (with null_reason breakdown)
nulls = [i for i in items if i.get('response') is None]
null_rate = len(nulls) / max(1, total) * 100
print(f'[Validate] null_rate = {len(nulls)}/{total} ({null_rate:.1f}%)')
if nulls:
    from collections import Counter
    reasons = Counter(i.get('null_reason', 'unknown') for i in nulls)
    for reason, count in reasons.most_common():
        print(f'  {reason}: {count}')
if null_rate > 5:
    print('  WARNING: null_rate > 5% -- results may be unreliable!')
    print('  Must distinguish Raw Acc vs Valid Acc in any report.')

# 2. Accuracy (raw and valid)
correct_raw = sum(1 for i in items if i.get('correct'))
valid_items = [i for i in items if i.get('response') is not None]
correct_valid = sum(1 for i in valid_items if i.get('correct'))
raw_acc = correct_raw / max(1, total) * 100
valid_acc = correct_valid / max(1, len(valid_items)) * 100
print(f'[Validate] Raw Acc = {correct_raw}/{total} ({raw_acc:.1f}%)')
print(f'[Validate] Valid Acc = {correct_valid}/{len(valid_items)} ({valid_acc:.1f}%)')
if null_rate > 5:
    print(f'  Delta: {valid_acc - raw_acc:.1f}pp (Valid - Raw)')

# 3. Backward max_time verification (OVO-Bench)
BACKWARD = {'EPM', 'ASI', 'HLD'}
backward_items = [i for i in items if i.get('task_type', '') in BACKWARD]
if backward_items:
    leaked = [i for i in backward_items if i.get('max_time') is None]
    if leaked:
        print(f'[Validate] CRITICAL: {len(leaked)} backward items have max_time=None (DATA LEAK!)')
    else:
        print(f'[Validate] Backward max_time: {len(backward_items)} items all using realtime cutoff')

# 4. Per-task-type accuracy breakdown
from collections import defaultdict
task_acc = defaultdict(lambda: [0, 0])
for i in valid_items:
    t = i.get('task_type', 'unknown')
    task_acc[t][1] += 1
    if i.get('correct'): task_acc[t][0] += 1
print('[Validate] Per-task accuracy:')
for t, (c, n) in sorted(task_acc.items()):
    print(f'  {t}: {c}/{n} ({c/max(1,n)*100:.1f}%)')
"
```

```bash
# 5. Cache stale warnings (from log)
echo "[Validate] Cache stale warnings:"
grep -c "v2 cache stale\|cache miss\|stale" LOG_FILE 2>/dev/null || echo "  0 warnings"

# 6. 429 / rate limit errors
echo "[Validate] 429 errors:"
grep -c "429\|rate.limit\|RateLimitError" LOG_FILE 2>/dev/null || echo "  0 errors"

# 7. Content policy errors
echo "[Validate] Content policy errors:"
grep -c "content_policy\|ContentPolicyError\|CONTENT_POLICY_BLOCKED" LOG_FILE 2>/dev/null || echo "  0 errors"

# 8. VLM rate limiter stats (if present)
echo "[Validate] Rate limiter activity:"
grep -c "VLM rate limiter\|semaphore\|backoff" LOG_FILE 2>/dev/null || echo "  0 entries"
```

**Validation criteria**:
- null_rate <= 5%: PASS
- null_rate 5-20%: WARNING -- report both Raw/Valid Acc, mark as potentially unreliable
- null_rate > 20%: FAIL -- results are unreliable, investigate root cause before using
- backward max_time=None: **CRITICAL** -- data leak, must re-run with commit 44d4924+
- cache_stale > 0: WARNING -- check if backward max_time or parameter mismatch
- 429_rate > 2% of total API calls: WARNING -- reduce workers for next run
- content_policy > 0: Expected for some datasets -- note in report, check if affecting accuracy

Update task list, report completion of setup.

---

## Mode 2: Monitor (cron-invoked via /loop, or manual check)

This runs inside `/loop` via cron OR when user manually asks to check status. Be fast when healthy, thorough when not.

### Step 1: Gather Raw Data

Run these bash commands to collect experiment state:

```bash
# 1. Progress -- count completed items
python3 -c "
import json, os
for f in ['RESULT_FILE', 'CHECKPOINT_FILE']:
    if os.path.exists(f):
        d = json.load(open(f))
        items = d.get('per_item', [])
        correct = sum(1 for i in items if i.get('correct'))
        nulls = sum(1 for i in items if i.get('response') is None)
        null_reasons = {}
        for i in items:
            if i.get('response') is None:
                r = i.get('null_reason', 'unknown')
                null_reasons[r] = null_reasons.get(r, 0) + 1
        nr_str = ', '.join(f'{k}={v}' for k,v in null_reasons.items()) if null_reasons else 'none'
        print(f'Progress: {len(items)}/EXPECTED | Accuracy: {correct}/{len(items)} ({correct/max(1,len(items))*100:.1f}%) | Nulls: {nulls} ({nr_str})')
        break
else:
    print('No result file yet')
"

# 2. Process alive?
ps aux | grep -E "(phase0c_regression|rtv_bench_eval|run_experiment)" | grep -v grep | head -3

# 3. Log freshness + recent content
stat -c 'Log modified: %Y' LOG_FILE 2>/dev/null
echo "Now: $(date +%s)"
tail -30 LOG_FILE

# 4. Cache hit ratio (CRITICAL for ablation — if <80% in first 5min, config drifted)
HITS=$(grep -c 'Cache HIT' LOG_FILE 2>/dev/null || echo 0)
MISS=$(grep -c 'Cache MISS\|v2 cache stale' LOG_FILE 2>/dev/null || echo 0)
TOTAL=$((HITS+MISS))
[ $TOTAL -gt 0 ] && echo "Cache: HIT=$HITS MISS=$MISS ratio=$((100*HITS/TOTAL))%"
```

**Cache ratio rule (ablation only)**: If after 5 minutes the ratio is <80% and this is an incremental phase that should reuse baseline cache → **kill process + diff config vs baseline + fix + restart**. Do not let it run 2h to find out.

### Step 2: Read and Judge

Read the raw data above. **Use your intelligence to classify** -- don't rely on regex patterns. Consider:

- Is progress advancing since last check?
- Does the log tail show normal processing or errors?
- Is the process alive?
- Are there patterns that LOOK like errors but aren't? (HTTP library debug output, retries that succeed, forced answers after round exhaustion)
- Are there subtle issues? (all answers are the same letter, accuracy dropping suspiciously, items being skipped)
- Is null count rising abnormally? (may indicate Content Safety or API issues)
- Are there `null_reason` fields? (content_policy vs retry_exhausted vs unknown -- different recovery strategies)

### Step 3: Act Based on Classification

**HEALTHY** -- Progress advancing, no errors, process alive.
```
[Monitor] HEALTHY | 85/140 (60.7%) | Acc: 55.3% | Nulls: 0 | Log: 30s ago
```
Done. Exit. Cron will invoke again in N minutes.

**COMPLETE** -- Items reached expected count.
```
[Monitor] COMPLETE | 140/140 | Accuracy: 65.7%
Run Phase 5 validation before declaring success.
Stop the monitoring loop -- experiment is done.
```

**STALE** -- Log not updated >20 min, process still alive (likely hung).
-> Kill process, restart from checkpoint.

**DEAD** -- Process gone, items < expected.
-> Restart from checkpoint. The checkpoint mechanism auto-skips completed items.

**API QUOTA/RATE LIMIT** -- 429, quota exhausted, rate limit errors in log.
-> The VLM rate limiter (added Round 14) handles most 429s automatically with jittered backoff.
-> If rate limiter is overwhelmed (429 count still rising fast), reduce workers and restart.
-> Wait 120 seconds, then restart from checkpoint.

**PROXY DOWN** -- TCP closed, connection refused, or massive 403 errors from proxy.
-> Check proxy health: `curl -s -o /dev/null -w "%{http_code}" --max-time 5 ${ML_PROXY_BASE}/v1/models`
-> If proxy down: kill experiment, set `GPT4O_USE_TRAPI=1`, restart from checkpoint.
-> TRAPI caution: run ONE experiment at a time (low burst limit).

**CODE BUG** -- Traceback in log.
-> This is the expensive path. Read the traceback, find the source file, understand the bug, fix it minimally, verify with `py_compile`, restart.
-> Constraints: fix ONLY the crash bug. Do NOT refactor, change logic, or "improve" code.

**OOM** -- CUDA out of memory, killed by OOM killer.
-> Kill GPU processes (`nvidia-smi` -> find PID -> kill), wait 30s, restart.

**HIGH NULL RATE** -- Nulls rising faster than 5% of total.
-> Check `null_reason` field in results:
   - `content_policy`: Expected for certain datasets (Ego4D). VLM rate limiter uses placeholder summaries. Log and continue.
   - `retry_exhausted`: VLM backend failures after max retries. Check API health, reduce workers.
   - `unknown` / missing: Legacy code path. Check log for actual error.
-> If Azure Content Policy, this is expected -- will need Valid Acc analysis post-completion.

**UNKNOWN** -- Something you don't recognize.
-> Print the relevant log snippet. Ask the user for guidance. Do not guess.

### Restart Procedure

To reconstruct the restart command, read the `config` field in the result JSON or the first lines of the log -- they contain the original parameters.

```bash
cd ${PROJECT_ROOT}/streaming-agent
source ${PROJECT_ROOT}/ml_env/bin/activate
kill PID 2>/dev/null; sleep 2

# Checkpoint auto-resumes -- just rerun the same command
nohup python3 scripts/SCRIPT.py ORIGINAL_ARGS >> LOG_PATH 2>&1 &
echo "[Monitor] Restarted PID $! from checkpoint (DONE/EXPECTED)"
```

### Monitoring Guidelines

1. **Be fast when healthy** -- one-line output, exit immediately. Cron will call again.
2. **Be thorough when unhealthy** -- read code, fix bugs, restart. Take the time needed.
3. **Never delete checkpoints or result files** -- they are precious data.
4. **Never change experiment logic** -- only fix crashes, not behavior.
5. **Track restart count** -- if same error recurs 3+ times, stop and escalate to user.
6. **Log your actions** -- append a line to the log when you restart or fix something, so the user sees what happened.
7. **Monitor null rate** -- if nulls exceed 5% during run, note it in the status line. Check `null_reason` for triage.
8. **Distinguish proxy vs TRAPI failures** -- proxy down needs TRAPI fallback; TRAPI burst limit needs serial execution.

---

## Mode 3: Validate (post-completion data quality check)

Run this on any completed experiment result to check for known data quality issues.

```bash
python3 -c "
import json, sys
from collections import Counter, defaultdict

f = sys.argv[1]
d = json.load(open(f))
items = d.get('per_item', [])
total = len(items)
issues = []

# 1. Null rate (with reason breakdown)
nulls = [i for i in items if i.get('response') is None]
null_rate = len(nulls) / max(1, total) * 100
if null_rate > 5: issues.append(f'HIGH null_rate={null_rate:.1f}%')
if nulls:
    reasons = Counter(i.get('null_reason', 'unknown') for i in nulls)
    reason_str = ', '.join(f'{k}={v}' for k,v in reasons.most_common())
else:
    reason_str = 'none'

# 2. Accuracy
correct_raw = sum(1 for i in items if i.get('correct'))
valid = [i for i in items if i.get('response') is not None]
correct_valid = sum(1 for i in valid if i.get('correct'))
raw_acc = correct_raw / max(1, total) * 100
valid_acc = correct_valid / max(1, len(valid)) * 100

# 3. Answer distribution (detect answer bias)
answers = Counter(i.get('response', '') for i in items if i.get('response'))
if answers:
    most_common = answers.most_common(1)[0]
    if most_common[1] / max(1, len(valid)) > 0.6:
        issues.append(f'Answer bias: {most_common[0]} appears {most_common[1]}/{len(valid)} ({most_common[1]/len(valid)*100:.0f}%)')

# 4. Backward data leak check (OVO-Bench)
BACKWARD = {'EPM', 'ASI', 'HLD'}
backward_items = [i for i in items if i.get('task_type', '') in BACKWARD]
if backward_items:
    leaked = [i for i in backward_items if i.get('max_time') is None]
    if leaked:
        issues.append(f'DATA LEAK: {len(leaked)} backward items have max_time=None')

# 5. Per-task-type accuracy
task_acc = defaultdict(lambda: [0, 0])
for i in valid:
    t = i.get('task_type', 'unknown')
    task_acc[t][1] += 1
    if i.get('correct'): task_acc[t][0] += 1

print(f'Items: {total} | Nulls: {len(nulls)} ({null_rate:.1f}%) [{reason_str}]')
print(f'Raw Acc: {raw_acc:.1f}% | Valid Acc: {valid_acc:.1f}%')
if task_acc:
    print('Per-task:')
    for t, (c, n) in sorted(task_acc.items()):
        print(f'  {t}: {c}/{n} ({c/max(1,n)*100:.1f}%)')
if issues:
    print(f'ISSUES:')
    for iss in issues:
        print(f'  - {iss}')
else:
    print('PASS: No data quality issues detected')
" RESULT_FILE
```

---

## Mode 5: Ablation (multi-experiment series)

Use this mode when the user is running a **phase-based ablation** (e.g. d-mode refactor E0→E5, any series inheriting from a baseline config). Serial, cross-phase memory required.

### Required inputs
- `plan_doc`: path to the phase plan (e.g. `docs/plans/d-mode-refactor/phase-L1a.md`)
- `baseline_config`: YAML of the E0/baseline run
- `baseline_result`: result JSON of the baseline (for Δ computation)
- `criteria_file`: path to a persistent `verdict-criteria.md` with the Δmacro threshold and noise floor

### Phase A1: Plan vs State Reconciliation (CRITICAL)
**Before writing any code**, verify the plan is still valid against current HEAD:

```bash
# 1. Commits since plan was written
git log --since="$(stat -c %y PLAN_DOC)" --oneline

# 2. Files referenced in plan — do they exist at assumed paths?
grep -oE '(src|streaming-agent)/[a-zA-Z_./]+\.py' PLAN_DOC | sort -u | while read p; do
  [ -f "$p" ] && echo "OK: $p" || echo "MISSING: $p"
done

# 3. Assumed signatures — did the function the plan wants to modify still exist?
grep -n 'def observe\|def recall\|class Segment' REFERENCED_FILES
```

If anything is MISSING or changed, **STOP, update the plan, re-confirm with user**. Do not "adapt silently" — that's how drift starts.

### Phase A2: Preflight Config Drift Check
Compare the new experiment's config against baseline, listing every field that affects cache key:

```bash
python3 -c "
import yaml, sys
cur = yaml.safe_load(open('CURRENT_CONFIG.yaml'))
base = yaml.safe_load(open('BASELINE_CONFIG.yaml'))
CACHE_KEY_FIELDS = ['model.backend','pipeline.fps','pipeline.resize_mode',
    'pipeline.clip_delta_high','pipeline.clip_delta_low',
    'mode.summary_prompt_variant']  # execution.cache_version 已弃用 (2026-04-21)
def get(d,p):
    for k in p.split('.'): d = (d or {}).get(k)
    return d
diffs = [(f, get(base,f), get(cur,f)) for f in CACHE_KEY_FIELDS if get(base,f) != get(cur,f)]
if diffs:
    print('CACHE-KEY DRIFT (Phase A will re-run):')
    for f,b,c in diffs: print(f'  {f}: {b!r} -> {c!r}')
    print('\\nIntentional? If yes, explicitly accept the cache miss. If no, revert.')
else:
    print('PASS: cache keys match baseline. Phase A should hit cache 100%.')
"
```

Any diff → user must confirm it's intentional. Cache 现按 benchmark 分目录 (`cache/{benchmark}/segments/`)，不再通过 `cache_version` 前缀隔离。

### Phase A3: Plan Conformance Check (after Executor codes)
Before running the 581-item experiment, verify the code actually realizes the plan:

```bash
# Pick 2-3 key claims from the plan, grep for them in the diff
git diff BASELINE_COMMIT..HEAD -- STREAMING_AGENT_SRC | grep -A5 -B2 'observe\|num_frames\|dedup'

# Run the plan's stated behavior on ONE item (smoke)
python3 scripts/run_experiment.py --config NEW_CONFIG.yaml --limit 1 --verbose 2>&1 \
  | grep -iE 'observe|num_frames|tool_call' | head -20
```

If the diff doesn't show the plan's claimed changes, or the smoke log shows unchanged behavior → **executor work is incomplete**, send back. Metric pass alone is not proof.

### Phase A4: Baseline Variance (once per ablation series)
Before trusting any Δ, run baseline twice with identical code/config. Record variance:

```
baseline_variance.json:
  E0: macro=0.626
  E0-rerun: macro=0.613
  variance_pp: 1.3
  noise_floor: 2.0  # conservative — any Δ < 2pp is noise
```

Save to `experiments/metadata/baseline_variance_<study>.json`. Subsequent verdicts MUST read this file; never re-derive threshold.

### Phase A5: Run + Verdict
- Run the experiment via normal Setup (Phase 1-5 above)
- After completion, compute Δ vs baseline
- Read `criteria_file` for threshold. Decision table:

| |Δ| < noise_floor | `noise — not a signal, log and continue or halt by policy` |
| |Δ| >= noise_floor positive | `signal gain — proceed to next phase` |
| |Δ| >= noise_floor negative | `regression — investigate before continuing` |

### Antipatterns for ablation — DO NOT do these
- ❌ Spawning Executor/Evaluator/Orchestrator as 3 parallel `/loop` agents. Ablation is serial; loops don't share memory. See Core Principle P4.
- ❌ Letting the Evaluator subagent set its own Δ threshold. Thresholds live in `verdict-criteria.md`, committed to git.
- ❌ Re-launching a crashed experiment with identical config. Diagnose first (P7).
- ❌ Changing a cache-key field without bumping `cache_version`. Silent cache miss will waste hours.
- ❌ Trusting metric-pass alone. Always run Plan Conformance Check first (A3).

---

## Project Context (streaming-agent specific)

Working directory: `${PROJECT_ROOT}/streaming-agent`
Virtual env: `source ${PROJECT_ROOT}/ml_env/bin/activate`
Python: `python3`

Checkpoint files: `{output_stem}_checkpoint.json`, auto-skip via `completed_ids` set.

### API Endpoints

| Endpoint | Usage | Env var |
|----------|-------|---------|
| `${ML_PROXY_BASE}` | Default Azure proxy (gpt4o/o4mini/o3/gpt52) | None (default) |
| TRAPI (`trapi.research.microsoft.com`) | Fallback when proxy down | `GPT4O_USE_TRAPI=1` |
| **Dual** (proxy + TRAPI parallel) | Phase A throughput boost (~1.5x) | `GPT4O_DUAL_BACKEND=1` or YAML `execution.dual_backend: true` |

**TRAPI notes**: Uses AzureCliCredential (run `az login` first), model remapped to `gpt-4o_2024-11-20`. Lower burst limit -- run experiments serially.

**Dual-backend notes** (added Round 15):
- proxy + TRAPI run simultaneously; semaphore budget auto-splits (65/35 weighted)
- GPT-4o: both Phase A and Phase B use dual dispatch
- o4-mini/o3: Phase A dual dispatch, Phase B locks to TRAPI only (preserves Responses API + thinking_log)
- gpt52: Phase A dual only if proxy supports model, otherwise auto-disables proxy side
- Circuit breaker: if one endpoint fails, 60s cooldown then retry; during cooldown all traffic routes to surviving endpoint
- Recommended: `max_concurrent_vlm: 30` with dual (vs default 20) to leverage both endpoints
- YAML config example:
  ```yaml
  execution:
    dual_backend: true
    max_concurrent_vlm: 30
  ```

### VLM Rate Limiter (updated Round 15)

The system has a 5-layer defense against API failures:
1. **VLM backend rate limiter** (`src/common/rate_limiter.py`): Semaphore + jittered backoff, max_retries=6, 429 gets 3x backoff
2. **Dual-endpoint dispatch** (`src/vlm/base.py` DualEndpointMixin): proxy+TRAPI parallel with least-loaded routing, circuit breaker (60s recovery), auto-fallback when one endpoint dies
3. **Agent loop graceful degradation**: VLM failures -> text placeholders (scores as wrong, not null)
4. **OVO evaluator per-item retry**: `_execute_with_retry()`, ContentPolicyError -> immediate (None, "content_policy")
5. **ExecutionConfig knobs**: `max_concurrent_vlm=20`, `vlm_max_retries=6`, `vlm_retry_base_delay=2.0`, `vlm_retry_max_delay=60`, `dual_backend=false`

Qwen backend auto-clamps `max_concurrent_vlm=1` (GPU-bound).
o4-mini/o3 dual mode: Phase A uses both endpoints, Phase B locks to TRAPI (preserves thinking_log via Responses API).

### Experiment Scripts

- **Unified runner (推荐, 2026-04-22 起)**: `scripts/run_experiment.py --benchmark {ovo,rtv,lv} --mode {A,B,C,D} --model BACKEND --n N`
- **Unified runner (YAML)**: `scripts/run_experiment.py --config YAML_FILE`（legacy yaml 兼容路径，不触发 benchmark 前缀强制注入）
- **Legacy shims** (内部委托给 unified runner): `scripts/phase0c_regression.py`, `scripts/rtv_bench_eval.py` (接受 `--vlm-backend --ablation-mode` 等旧 flag)
- All support `--limit N` / `--n N` for dry-run, `--verbose` for detailed logging.

默认值由 `streaming-agent/experiments/configs/_defaults/{global,ovo,rtv,lv,models/<model>}.yaml` 分层合并；禁止在用户 yaml 里硬写默认字段。

## Historical Error Patterns (Quick Reference)

When diagnosing issues, check `/experiment-guide` skill for the full 35+ error case library. Top patterns:

| Pattern | Symptom | Fix | Round |
|---------|---------|-----|-------|
| Backward data leak | backward acc too high; "v2 cache stale" warnings | Use code after commit 44d4924; backward uses realtime as max_time | R13-14 |
| Null pollution | C/D mode accuracy << A mode | Check null_rate; report Valid Acc; VLM rate limiter now handles most cases | R4-5 |
| Workers too high | Massive 429 errors in log | precompute_workers <= 20 for gpt4o (actual = workers x 8) | R12-13 |
| Cache key mismatch | Phase A success but Phase B re-processes | Check if pipeline params changed (resize_mode, fps, summary_prompt_variant) | R13 |
| as_completed trap | Phase A hangs indefinitely | Use wait() + cancel (already fixed R12) | R8-12 |
| Proxy down | TCP closed, massive 403 | Use `dual_backend: true` (auto circuit-breaks proxy); or `GPT4O_USE_TRAPI=1` (serial) | R14-15 |
| Content policy abort | Single segment kills entire video | ContentPolicyError + placeholder summary (fixed R12) | R12-13 |
| Cross-backend cache miss | Qwen online C re-runs Phase A | Cross-backend exclusive key lookup (fixed R14) | R14 |
| Appearance serialization loss | Entity appearance always None | Fixed R11; must regenerate Phase A cache with new code | R4-11 |
| Phase A fixed timeout | Large video sets always timeout | Dynamic timeout: ceil(n/w) x per_video_timeout + 120s (fixed R12) | R12 |
| TRAPI burst limit | 12,000+ 403 errors from TRAPI | Use `dual_backend: true` (auto-limits TRAPI share to 35%); or run ONE experiment at a time | R14-15 |


## Claude Backend Reminder

- Use backend name `claude`.
- Keep implementation in `streaming-agent/src/vlm/claude.py` aligned with GPT-4o-style OpenAI chat-completions payloads against localhost:4142.
- D-mode runs require both image injection and tool calling support.
