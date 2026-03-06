---
name: save-session
description: 在对话 compact 前保存会话行动路线摘要。当检测到 context 即将满、用户准备结束会话、或用户主动调用时使用。提炼关键 prompt、思路、探索方向和执行结果，写入 docs/history/ 目录。
argument-hint: "[project-name (可选，自动推断)]"
---

# Save Session - 会话行动路线保存（子 Agent 版）

将当前对话的关键行动路线提炼为结构化 Markdown，保存到 `docs/history/{project_name}/round_{N}.md`。

**核心改进**: 使用 Agent 子进程执行保存，避免在主 context 中产生大量 token 导致 compact。

## 触发时机

1. **用户主动调用**: `/save-session` 或 `/save-session my-project`
2. **Claude 主动触发**: 当检测到对话已经很长、讨论了大量内容、或即将 compact 时
3. **对话结束前**: 用户表示要结束或切换话题时

**重要**: 如果你感觉当前对话内容已经很丰富（多轮探索、重要决策、实验结果），应主动建议用户运行此 skill 或直接执行。

## 工作流程（必须严格遵循）

### Step 1: 确定项目名称和 round 编号（主 agent 做，快速）

项目名称优先级：
1. 用户通过参数指定: `/save-session estp-phase3`
2. 从对话内容自动推断（操作的文件路径、讨论主题）
3. 如果无法推断，使用 `misc`

项目名称应该简短（1-3个词，kebab-case），如：`estp-bench`、`streaming-agent`、`gui-pipeline`

用 Bash 检查已有 round 文件确定编号：
```bash
ls docs/history/{project_name}/round_*.md 2>/dev/null | sort -V | tail -1
```

### Step 2: 在主 agent 中快速起草要点（~200 tokens）

在你的脑中快速回顾对话，提炼出：
- 会话目标（1句话）
- 关键阶段（每个阶段 1-2 句话，包含用户原始 prompt 摘录）
- 关键决策和数据
- 当前状态和下一步

**不要在主对话中展开写**——只在脑中整理，直接写入 Agent prompt。

### Step 3: 启动子 Agent 执行保存（关键步骤！）

**必须使用 Agent 工具**，不要在主对话中直接写文件。

使用以下模式启动 Agent：

```
Agent tool:
  subagent_type: "general-purpose"
  description: "Save session history"
  model: "sonnet"  (用 sonnet 即可，不需要 opus)
  prompt: |
    你是会话历史保存助手。请根据当前对话内容，生成结构化的会话历史文件。

    ## 任务
    将当前对话的行动路线保存到: `docs/history/{project_name}/round_{N}.md`

    ## 项目信息
    - 项目名: {project_name}
    - Round: {N}
    - 日期: {today}

    ## 对话要点摘要
    {你在 Step 2 中整理的要点，200-500 tokens}

    ## 输出要求
    1. 先 `mkdir -p docs/history/{project_name}`
    2. 回顾上方对话历史，提炼完整的行动路线
    3. 按下面的模板格式写入文件
    4. 长度 100-300 行，质量标准：可回顾性、原始性、数据优先

    ## 模板格式

    ```markdown
    # {Project Name} - Round {N}

    > 日期: YYYY-MM-DD
    > 会话轮数: 约 X 轮
    > 主要方向: {一句话概括}

    ## 会话目标
    {1-3 句话}

    ## 行动路线

    ### 1. {阶段标题}
    **Prompt**: > {用户原始指令，保留原文}
    **探索过程**: - {做了什么} - {发现了什么}
    **结果**: {关键数据/结论}
    ---
    ### 2. {下一阶段}
    ...

    ## 关键决策
    | 决策点 | 选择 | 原因 | 备选方案 |
    |--------|------|------|----------|

    ## 关键数据/指标
    {硬数据优先}

    ## 文件变更摘要
    - `path/to/file.py` - {修改说明}

    ## 问题与发现
    - **{问题}**: {描述} → {状态}

    ## 当前状态
    {进展到哪一步}

    ## 下一步
    - [ ] TODO 1
    - [ ] TODO 2
    ```

    ## 质量标准
    - 用户的关键 prompt 保留原文，不要改写
    - 实验数据、F1 分数、错误信息等硬数据优先保留
    - 按对话的实际推进顺序组织
    - 使用中文撰写
```

### Step 4: 确认结果

子 Agent 完成后，简要告知用户保存位置和 round 编号。

## 注意事项

- **绝不在主对话中生成完整的 session markdown** —— 这是导致 compact 的根本原因
- 如果对话很短（< 5 轮），可能不值得保存，提醒用户
- 如果对话中有多个不相关的项目，分别启动子 Agent 写入不同目录
- 子 Agent 可以看到完整对话历史，所以你的 prompt 只需要提供结构化指引，不需要复述所有内容
- 使用 `model: "sonnet"` 节省成本，sonnet 足够完成格式化写作任务
- **原始 dump 备份**: PreCompact hook 会在每次 compact 前自动将用户消息原文 dump 到 `~/.claude/backups/{timestamp}_{session_id}_{trigger}.md`。即使 `/save-session` 未运行，原始 prompt 也不会丢失。如果子 Agent 需要补充细节，可以读取该目录下的备份文件
