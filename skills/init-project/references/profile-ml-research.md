# Profile: ML Research / 模型训练 / 评估

## 信号识别

满足任一即匹配 ML 研究 profile：
- `requirements*.txt` / `pyproject.toml` 含 `torch`, `tensorflow`, `transformers`, `accelerate`, `vllm`, `xformers`
- 顶层有 `experiments/`, `notebooks/`, `models/`, `eval/`, `benchmarks/` 目录
- 有 `*.ipynb` 文件
- README 含 "fine-tune", "evaluation", "benchmark", "ablation" 关键词
- 有 GPU 相关脚本（`run_train.sh`, `submit_amlt.yaml` 等）

---

## Phase 4 额外提问

```
ML-Q1: 数据在哪？
  [a] 本地 (data/)
  [b] Azure Blob (设置 container/path)
  [c] HuggingFace Hub (datasets.load_dataset)
  [d] AWS S3 / GCS
  [e] 多源混合

ML-Q2: 主要计算资源？
  [a] 单卡本地（A100 / 4090 / RTX）
  [b] 多卡本地
  [c] 集群提交（AMLT / Slurm / Kubernetes）
  [d] CPU only

ML-Q3: 性能/质量目标？（自由填写）
  - latency budget? throughput? accuracy floor?

ML-Q4: 实验归档结构？
  [a] experiments/{phase}/         (按 phase 分)
  [b] experiments/{model}/         (按模型分)
  [c] experiments/{benchmark}/     (按 benchmark 分)
  [d] runs/{date}_{description}/   (按时间)
```

---

## 推荐 plugins（enabled）

```json
{
  "copeee-skills@copeee-skills": true,         // 通用 workflow（experiment-runner generalized 等）
  "superpowers@superpowers-marketplace": true, // brainstorming / TDD / verification
  "context7@claude-plugins-official": true,    // 库文档查询
  "code-simplifier@claude-plugins-official": true,
  "code-review@claude-plugins-official": true
}
```

**禁用**（明确避免噪音）：
- `frontend-design` / `ui-ux-pro-max` / `obsidian` —— ML 项目无关

> **私有/项目专属 ML skill plugin（可选）**：很多 ML 团队会单独维护一个私有 plugin（比如内部的 experiment indexer / data path registry / cluster job submitter / proxy tunnel），那些 skill 通常含内部 endpoint 或数据路径，不适合公开。如果你有这种 plugin，在 `extraKnownMarketplaces` 里挂上并 enable 即可——init-project 不会强制依赖它。

---

## 推荐 skills（从已装 plugin 挑哪些主动调用）

| Skill | 来源 | 用途 |
|-------|------|------|
| `experiment-runner` | copeee-skills | 跑/监控/恢复实验生命周期（含 P1–P7 核心原则）|
| `superpowers:brainstorming` | superpowers | 新研究点开问之前 |
| `superpowers:verification-before-completion` | superpowers | 实验完成前的严格校验（防 null_rate 虚高、cache miss 等） |
| `superpowers:test-driven-development` | superpowers | 写新 evaluator / metric 前 |

**项目专属候选**（如果你或团队有私有 ML plugin，建议补上同类 skill）：
- 实验结果索引 + 主表生成（避免手写主表幻觉）
- 实验配置 schema + 历史错误案例库（减少配置漂移）
- 数据路径 / 覆盖率 registry（Cloud blob 场景）
- 集群 job 提交（AMLT / Slurm / Kubeflow）
- 数据下载 → 上传 pipeline（HuggingFace / S3 → 内部 blob）

---

## 推荐 .claude/commands/

```
.claude/commands/
├── run-smoke.md       # 跑 N 题 smoke test（N 由用户在 Phase 4 给）
├── profile-latency.md # 测端到端 latency（如有 latency 目标）
└── compare-runs.md    # 比对两次实验的关键指标差异
```

各 command 的 description 都应明确：
- 参数（args）
- 实际跑的命令
- 预期输出位置

例（`run-smoke.md`）：
```markdown
---
description: "跑 smoke test 验证实验 pipeline。$ARGUMENTS 可指定模型/模式/数据切片。"
---

Run a smoke test using the smallest dataset (mini_subset / N=5):
$ARGUMENTS

Default behavior:
- benchmark: rtv (or what's in the user's first arg)
- mode: D
- model: gpt4o
- subset: mini_subset.json
- output: /tmp/smoke_$(date +%s).json

Verify before declaring success: null_rate < 5%, no Phase A timeouts.
```

---

## 推荐 hooks

```json
"hooks": {
  "PostToolUse": [
    {
      "matcher": "Edit|Write",
      "hooks": [
        {"type": "command", "command": "bash ~/.claude/hooks/python-syntax-check.sh"}
      ]
    }
  ],
  "Stop": [
    {
      "matcher": "",
      "hooks": [
        {"type": "command", "command": "bash ~/.claude/hooks/cleanup-empty-sessions.sh", "async": true}
      ]
    }
  ]
}
```

**特别注意**：实验 ML 项目**不要**装 `pytest on save`——单测本身往往慢且依赖 GPU；用 `verification-before-completion` skill 在 commit 前手动跑。

---

## 推荐 .claude/settings.json 关键字段

```json
{
  "permissions": {
    "defaultMode": "dontAsk",
    "allow": [
      "Bash(pytest *)",
      "Bash(python3 scripts/*)",
      "Bash(amlt *)",
      "Bash(azcopy *)"
    ],
    "deny": [
      "Edit(.env)",
      "Edit(*.pem)",
      "Edit(secrets/**)",
      "Edit(.azure/credentials)"
    ]
  },
  "env": {
    "ENABLE_TOOL_SEARCH": "true"
  }
}
```

---

## CLAUDE.md 模板片段（ML 研究专用段落）

```markdown
## 服务器配置
cd <PROJECT_ROOT>
source <VENV>/bin/activate
python3 instead of python

## 硬件
GPU: <user-filled, e.g. A100 80GB / 4090>
CUDA: <auto-detected from nvidia-smi>

## API & 基础设施 ⚠️ IMPORTANT
- <user-filled endpoint constraint, e.g. "永远不要直接调用 OpenAI 官方 endpoint，必须走 <proxy_host>">
- 所有外部 API 都从代理走

## 数据
- <user-filled, e.g. Azure Blob: <container>/<path>>
- 全量 / smoke test 子集说明

## 性能约束
- <user-filled latency / throughput / accuracy targets>

## 实验目录
experiments/{phase|model|benchmark}/
metadata/index.yaml — 由实验 indexer skill 维护（或脚本生成）

## 跑实验工作流
1. 配置 → 实验配置参考 skill（含 schema + 错误案例库）
2. 跑 → /experiment-runner
3. 整理表 → 实验 indexer skill（或手动维护 metadata/index.yaml）
```

---

## 反模式（ML 项目特有）

- **不要把 model checkpoint 放进 git**：自动加 `.gitignore`：`models/`, `checkpoints/`, `*.bin`, `*.safetensors`
- **不要把 wandb logs / mlflow artifacts 写进 settings**：让 wandb 自己管
- **不要让 Claude 自动跑长训练**：训练命令进 `permissions.deny` 或要求显式确认
- **null_rate / cache_hit_rate 检查**进 `verification-before-completion` 而不是 CLAUDE.md（避免 prose 提醒被忽略）
