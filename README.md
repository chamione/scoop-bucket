# chamione/scoop-bucket

这是我的 Scoop bucket，用来维护主 bucket 中没有收录、但我需要的软件。

## 使用

```powershell
scoop bucket add chamione https://github.com/chamione/scoop-bucket.git
scoop install chamione/rebased
scoop install chamione/clawd-on-desk
scoop install chamione/herdr
```

更新 bucket 后，Scoop 会使用 manifest 中固定的版本和 SHA-256 校验值安装软件。上游发布新版本后，GitHub Actions 会检查官方 release，更新 manifest，然后创建 pull request。
