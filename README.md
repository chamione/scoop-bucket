# chamione/scoop-bucket

这是我的 Scoop bucket，用来维护主 bucket 中没有收录、但我需要的软件。

## 使用

```powershell
scoop bucket add chamione https://github.com/chamione/scoop-bucket.git
scoop install chamione/rebased
scoop install chamione/clawd-on-desk
scoop install chamione/herdr
scoop install chamione/claude-cage
```

更新 bucket 后，Scoop 会使用 manifest 中固定的版本和 SHA-256 校验值安装软件。上游发布新版本后，GitHub Actions 会检查官方 release，更新 manifest，然后创建 pull request。

## 仓库结构

```text
.
├── bucket/                       # Windows 软件的 Scoop 清单
│   ├── claude-cage.json
│   ├── clawd-on-desk.json
│   ├── herdr.json
│   └── rebased.json
├── scripts/
│   ├── update-<包名>.sh          # 每个包的 Bash 更新入口
│   └── lib/release.sh            # 共用的发布查询、校验及清单写入函数
├── .github/workflows/
│   └── update-<包名>.yml         # 每个包的定时和手动更新任务
├── .gitattributes                # 保证 Bash 脚本使用 LF 换行
└── README.md
```

## 自动化维护规范

- 仓库自动化统一使用 Linux 和 Bash。脚本使用 `.sh` 扩展名和 LF 换行，入口启用 `set -euo pipefail`。工作流使用 `ubuntu-latest` 并通过 `bash scripts/update-<包名>.sh` 调用。不要新增或调用 `.ps1` 自动化脚本。Scoop 清单内的安装与卸载命令由用户的 Windows 环境执行。
- 新增软件时，使用相同包名创建清单、更新脚本和工作流，并补充上方的安装示例。工作流同时支持定时运行和手动触发，通过 `GH_TOKEN` 查询上游正式发布。
- 按文件名和架构匹配官方 Windows 发布文件。优先使用发布文件的 SHA-256；缺少摘要时，可下载官方文件计算 SHA-256，或终止更新。任一架构缺少安装包或校验失败时，保留原清单。
- 只更新版本、下载地址和哈希。全部架构校验通过后再写入清单。重复运行应产生相同结果，有变更时通过 PR 提交对应包的清单。

在 Linux 上安装 Bash、GitHub CLI（`gh`）、`jq`、`curl` 和 GNU coreutils，并完成 `gh auth login` 或设置 `GH_TOKEN` 后，可从仓库根目录运行单个包的更新脚本：

```bash
bash scripts/update-herdr.sh
git diff -- bucket/herdr.json
```
