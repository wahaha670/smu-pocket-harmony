# 发布到 GitHub

> ⚠️ 本机**还没装 git**（`git --version` 报命令不存在），所以下面从装 git 开始。

---

## 一、装 git

```powershell
winget install --id Git.Git -e
```

装完**重开一个终端**（PATH 要刷新），确认：

```powershell
git --version
```

> 如果 winget 卡住或失败（本机 WinHTTP 是直连、部分 GitHub 资源会被墙），
> 可以手动去 <https://git-scm.com/download/win> 下载安装包，
> **安装路径选 D 盘**（C 盘空间紧张）。

装完后告诉 git 你是谁（提交记录要用）：

```powershell
git config --global user.name  "你的名字"
git config --global user.email "你的邮箱"
```

---

## 二、首次发布

项目已经整理好，直接在项目目录初始化并推送：

```powershell
cd D:\HarmonyOS\smu-pocket

git init
git branch -M main
git add -A

# ⚠️ 提交前先看一眼暂存了什么，重点确认没有签名材料
git status --short

git commit -m "feat: 南医大口袋鸿蒙版 v1.1.1 首个公开发布"
```

然后在 GitHub 上**新建一个空仓库**（不要勾选 README / .gitignore / License，
因为本地已经有了），再关联并推送：

```powershell
git remote add origin https://github.com/<你的用户名>/smu-pocket-harmony.git
git push -u origin main
```

---

## 三、⚠️ 推送前必看：确认没有泄露签名材料

`signing/` 目录里有你的**个人调试证书**（`.p7b` / `.pem` / Profile），
提交出去等于公开自己的签名身份，**必须**确认被排除。

用下面这条检查（不需要装 git）：

```powershell
# 列出所有 HAP 之外的签名类文件，正常情况下应该一个都不显示
Get-ChildItem -Recurse -File -Force |
  Where-Object { $_.FullName -notmatch '\\(oh_modules|build|\.hvigor|_legacy)\\' -and
                 $_.Extension -match '^\.(p12|p7b|pem|cer|csr|jks|keystore)$' } |
  Select-Object FullName
```

再确认 `.gitignore` 里 `signing/` 这条规则**真的生效**：

```powershell
git check-ignore -v signing/smu-pocket.p7b
# 期望输出类似：  .gitignore:39:signing/   signing/smu-pocket.p7b
```

> 📌 这条检查不是多余的。整理期间 `.gitignore` 因为编辑器编码问题
> **把中文注释搞乱码并吞掉一个换行**，导致 `signing/` 规则被并进注释行、
> **静默失效**。是靠逐条解析规则才发现的。

**如果已经误提交了**，光删文件没用（历史里还在）。要处理历史：

```powershell
# 从整个历史里彻底移除
git filter-repo --path signing --invert-paths
# 或（未装 filter-repo 时）
git rm -r --cached signing
git commit -m "chore: 移除误提交的签名材料"
```

**更稳妥的做法**：既然那些证书是本地生成的，误提交后直接去
华为 AppGallery Connect **吊销并重新生成调试证书**，比清洗 git 历史更彻底。

---

## 四、关于 HAP 和 Release

**不要把调试签名的 HAP 传到 Release。** 原因见 [../dist/README.md](../dist/README.md)：
调试证书绑定了开发者本人的设备 UDID，别人装了也跑不起来，且会暴露签名身份。

`dist/` 里只保留**未签名**的 HAP，供使用者自行签名。

如果你想发一个别人能直接装的包，需要走正式流程：

1. 在 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)
   创建应用、填写包名 `com.smu.pocket`
2. 申请**发布证书**与**发布 Profile**（不是调试证书）
3. 用发布证书签名后，HAP 才可以被任意设备安装

> 注意：正式发布还要过华为的内容审核，且这类"非官方校园客户端"
> 可能不符合上架政策。**更适合的定位是开源项目**，让使用者自己编译签名。

---

## 五、仓库建议设置

| 项 | 建议 |
|---|---|
| 仓库名 | `smu-pocket-harmony`（和安卓版区分开） |
| 描述 | `南方医科大学课表/成绩 · HarmonyOS NEXT 原生客户端（ArkTS）` |
| Topics | `harmonyos` `arkts` `arkui` `harmonyos-next` `smu` `timetable` |
| 许可 | 已在仓库根目录放好 GPL-3.0（与原项目一致） |
| 分支保护 | 至少保护 `main` |

### 建议在仓库描述里说明的

- 这是**非官方**项目，与南方医科大学无隶属关系
- 需要**自己签名**才能安装（鸿蒙机制限制）
- 教务系统**可能只在校园网/VPN 内可达**

---

## 六、后续更新流程

```powershell
cd D:\HarmonyOS\smu-pocket
git add -A
git commit -m "fix: 描述你改了什么"
git push
```

发版本时：

1. 改 `AppScope/app.json5` 里的 `versionCode` / `versionName`
2. 在 `CHANGELOG.md` 顶部加一节
3. 打 tag 并推送：
   ```powershell
   git tag -a v1.1.2 -m "v1.1.2"
   git push origin v1.1.2
   ```
4. 在 GitHub 上基于该 tag 建 Release，把 `CHANGELOG.md` 对应段落粘进去
