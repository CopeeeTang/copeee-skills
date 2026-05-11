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
  [e] 多硬件对比（如 A100 vs 4090，性能研究）

ML-Q3: 性能/质量目标？（自由填写）
  - latency budget? throughput? accuracy floor?

ML-Q4: 研究问题列表？（自由填写多条，默认合并成 1 个 research-notes.md）
  - 例: 数据 layout 是否有助理解 / 模型理解开放式意图 / 响应速度上限

ML-Q5: 是否有不可越过的工程红线？
  - 例: "ASR + 图像预处理必须并行（不允许串行）"
  - 例: "VLM 必须本地推理，不允许换远端 API（影响 latency 研究可信度）"
  → 进 CLAUDE.md ⚠️ IMPORTANT 段
```

---

## 默认生成的 artifact（仅 init-project default 集，无项目级 settings/commands/hooks）

| Artifact | 内容 |
|----------|------|
| `CLAUDE.md` | WHY/WHAT/HOW + 硬件 + 数据 + 性能约束 + ⚠️ 红线（见下面模板片段） |
| `CLAUDE.local.md` | 个人 secrets 占位 + 个人风格偏好 |
| `research-notes.md` | 合并多个 RQ 到单文件（见下面模板）|
| `pyproject.toml` | ML 依赖模板（`transformers`, `torch`, etc.）—— 不安装 |
| `.gitignore` 追加块 | `models/`, `checkpoints/`, `*.bin`, `*.safetensors`, `wandb/`, `mlruns/`, `.env*`, `results/` 私有部分 |

> **不会自动生成**：`.claude/settings.json`、`.claude/commands/*`、hooks、`.claude/agents/*`。用户全局已 `dontAsk` + all-permissions + 已装 plugin 提供的 skill（experiment-runner / verification-before-completion / brainstorming 等）会自动按 description 触发，**无需项目级配置**。

---

## CLAUDE.md 模板片段（ML 研究专用段落）

```markdown
# <project-name>

## WHY
<user-filled: 一句话研究目标>

## WHAT
<end-to-end pipeline 图，<= 5 行>

- 数据集: <user-filled, e.g. Azure Blob: <container>/<path>>
- 全量 / smoke 子集
- 评测: <metric 1> + <metric 2>

## HOW
依赖管理 (uv / pip / poetry):
    uv sync                                  # 第一次装依赖
    uv run python -m <module>.smoke --n 5    # 快验

实验结果归档:
    results/{YYYY-MM-DD}/{hardware}/{exp_name}.json
    每条 record 含 stage_timings 等关键字段

## ⚠️ 不可违反的红线
1. <user-filled 红线 1，如"ASR 与图像预处理必须并行">
2. <user-filled 红线 2，如"VLM 只用本地，不允许换远端 API">
3. **不删除 results/** 下任何已落盘文件
4. **SAS token / secret 永远不入 git**

## 研究问题
见 `research-notes.md`

## 调试 latency / accuracy
- 用 record 的 stage_timings 字段（首选）
- 不用 wall-clock 推断
```

---

## research-notes.md 模板（合并多个 RQ 到 1 个文档）

```markdown
# Research Notes — <project-name>

## Problem statement
<2-3 sentence 研究背景 + 核心目标>

## Research questions

### RQ1: <一句话 title>

**问题**: <详细描述>

**子问题**:
- <sub-q 1>
- <sub-q 2>

**实验设计**:
| condition | <var 1> | <var 2> |
|-----------|---------|---------|
| baseline  | ...     | ...     |
| variant A | ...     | ...     |

**指标**: <metric list>

**TODO**:
- [ ] 数据 schema 确认
- [ ] 评估协议 draft
- [ ] golden answer 标注规范

### RQ2: <一句话 title>
... (同结构)

### RQ3: <一句话 title>
... (同结构)

## Cross-cutting engineering constraints
- 红线 1: <同步 CLAUDE.md>
- 红线 2: ...

## Open questions
- annotation: 谁标？标几遍？冲突仲裁？
- ...
```

**何时**把单文件拆成 `.kiro/specs/<rq>/` 或类似多文件结构：
1. 用户**明确说**"我要按 spec-driven 跑这些 RQ"
2. 某个 RQ 已经分化出 design.md + tasks.md 实质内容
3. 各 RQ 的实验设计差异巨大无法在一个文档讲清

否则默认就是单文件 living doc，随项目演化追加内容。

---

## pyproject.toml 模板（不安装，只画蓝图）

```toml
[project]
name = "<project-name>"
version = "0.0.1"
description = "<one-liner>"
requires-python = ">=3.10"
dependencies = [
    # VLM / model serving (注释掉的需要时再开启)
    "transformers>=4.45",
    # "vllm>=0.6",          # 大模型推理（可选）
    "torch",
    # ASR / multimodal (按需)
    # "faster-whisper>=1.0",
    # "openai-whisper",
    # Data / cloud
    # "azure-storage-blob>=12.20",
    # "datasets",          # HuggingFace
    "pillow",
    "numpy",
]

[tool.uv]
dev-dependencies = [
    "pytest>=8.0",
    "ruff>=0.7",
]

[tool.ruff]
line-length = 100
target-version = "py310"

[tool.pytest.ini_options]
testpaths = ["tests"]
```

> **关键**：注释掉一半依赖，让用户根据 backend / ASR 选定后**自己**取消注释 + `uv sync`。init-project **不**自动跑 `uv sync` / `pip install`。

---

## .gitignore 追加块（ML 项目）

```
# Models / checkpoints
models/
checkpoints/
*.bin
*.safetensors
*.pt
*.ckpt

# Experiment tracking
wandb/
mlruns/
lightning_logs/

# Secrets
.env
.env.*
*.pem
*.key
*credentials*

# 个人偏好
CLAUDE.local.md
.claude/settings.local.json

# Smoke / tmp
/tmp/smoke_*
.DS_Store
```

---

## 反模式（ML 项目特有）

- **不要把 model checkpoint 放进 git** → 默认 `.gitignore` 已加 `models/`, `checkpoints/`, `*.bin`, `*.safetensors`
- **不要把 wandb logs / mlflow artifacts 写进 settings** → 让 wandb 自己管
- **不要让 Claude 自动跑长训练** → 别用 hook，让用户手动决定
- **不要把 null_rate / cache_hit_rate / latency 检查写进 CLAUDE.md prose** → 用 `verification-before-completion` skill 在 commit 前跑（plugin skill 已经覆盖，不需要项目级配置）
- **不要预生成 settings.json 的 deny 规则** → 用户全局 dontAsk 默认；除非该项目有特殊敏感目录（用户主动喊 `add settings` 才生成）
- **不要拆研究问题到多文件** → 默认 1 个 `research-notes.md`，等用户喊"拆"再分
- **不要在 init 阶段强行装 venv** → `pyproject.toml` 是蓝图，安装时机由用户自己决定
