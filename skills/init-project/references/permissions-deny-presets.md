# Permissions Deny Presets

> Phase 4 第 4 题"敏感目录"答完后，根据项目类型直接套用以下预设到 `.claude/settings.json` 的 `permissions.deny`。

---

## 通用最小集（任何项目都加）

```json
"permissions": {
  "deny": [
    "Edit(.env)",
    "Edit(.env.*)",
    "Edit(*.pem)",
    "Edit(*.key)",
    "Edit(id_rsa*)",
    "Edit(id_ed25519*)",
    "Edit(.ssh/**)"
  ]
}
```

---

## ML 研究项目额外

```json
[
  "Edit(.azure/credentials)",
  "Edit(.aws/credentials)",
  "Edit(.huggingface/token)",
  "Edit(wandb_api_key*)",
  "Edit(models/**)",            // 模型权重不该手编
  "Edit(checkpoints/**)",
  "Bash(amlt run*)",            // 提交集群任务前要确认
  "Bash(rm -rf experiments/*)"  // 防止误删实验结果
]
```

---

## Web app 项目额外

```json
[
  "Edit(.env.production)",
  "Edit(.env.local)",
  "Edit(prisma/migrations/**)",      // DBA 边界
  "Edit(supabase/migrations/**)",
  "Edit(drizzle/migrations/**)",
  "Edit(.next/**)",                  // build artifact
  "Edit(node_modules/**)",
  "Bash(npm publish*)",
  "Bash(yarn publish*)",
  "Bash(pnpm publish*)",
  "Bash(vercel deploy*)",            // 防止误部署 prod
  "Bash(railway up*)"
]
```

---

## CLI / Library 项目额外

```json
[
  "Bash(cargo publish*)",
  "Bash(cargo yank*)",
  "Bash(twine upload*)",
  "Bash(npm publish*)",
  "Edit(CHANGELOG.md)",              // 必须人工手写 release notes
  "Edit(VERSION)",
  "Bash(git tag *)",                  // tag 是不可逆操作
  "Bash(git push --force*)"
]
```

---

## Data pipeline 项目额外

```json
[
  "Bash(aws s3 rm*)",
  "Bash(aws s3api delete*)",
  "Bash(gsutil rm*)",
  "Bash(azcopy remove*)",
  "Edit(dags/production/**)",         // Airflow 生产 DAG
  "Edit(.dvc/config)",
  "Bash(dvc remove*)"
]
```

---

## Infra / DevOps 项目额外

```json
[
  "Edit(*.tfstate)",                  // Terraform state 永远不该手编
  "Edit(*.tfstate.backup)",
  "Bash(terraform destroy*)",
  "Bash(terraform apply*)",           // 要求显式确认
  "Bash(kubectl delete*)",
  "Bash(helm uninstall*)",
  "Bash(aws iam delete*)",
  "Bash(az role assignment delete*)"
]
```

---

## 公开 OSS 项目特别加（防泄露）

```json
[
  "Edit(scripts/secrets/**)",
  "Bash(git config user.email *@<your-org>.com)",  // 防止误用公司 email 提交
  "Edit(.git/config)",
  "Bash(git push <internal-remote>*)"  // 防止推到内部 remote
]
```

---

## 与 hook 的取舍

| 用 `permissions.deny` 当 |
|--------------------------|
| 模式固定（path/cmd 完全可枚举）|
| 不需要动态判断 |
| 想给 Claude 一个明确"边界" 让它自己绕开 |

| 用 `PreToolUse` hook 当 |
|------------------------|
| 需要根据文件**内容**判断（如检测 secret）|
| 需要返回更细错误信息 |
| 需要 conditional logic（如"周末不许 deploy"）|

简单情况优先 `permissions.deny`——它更便宜（不启动 shell）。

---

## 通用反模式

- **deny 列表过长** → 模型会无法做正常工作；一般 8–15 条已经够
- **deny 太宽**（如 `Edit(*)`）→ 完全瘫痪，永远不要这么写
- **忘了 path 通配符**（`Edit(prisma)` 不会匹配 `prisma/migrations/foo.sql`）→ 要写 `Edit(prisma/**)`
- **deny 但允许 Bash 绕过**（如 deny `Edit(.env)` 但允许 `Bash(echo ... > .env)`）→ Bash 通配也得 deny
