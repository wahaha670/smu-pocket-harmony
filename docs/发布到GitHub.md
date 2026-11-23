# 发布到 GitHub

> ✅ **当前状态（2026-11-23）**：git 已装到 `D:\Git`，仓库已初始化并完成首次提交
> （`main` 分支，118 个文件，`.git` 约 5.5 MB）。剩下只差在 GitHub 建仓并推送。
>
> ⚠️ 本机 PATH 里没有 git（装到了 D 盘），每次用之前先加一行：
> ```powershell
> $env:Path = "D:\Git\cmd;" + $env:Path
> ```

---

## 一、装 git（已完成，记录备查）

```powershell
winget install --id Git.Git -e --location "D:\Git"
```

装完**重开终端**（PATH 要刷新），或每次临时加：
```powershell
$env:Path = "D:\Git\cmd;" + $env:Path
```

记录当前状态（提交历史要显示）：
```powershell
git config user.name  "你的名字"
git config user.email "你的邮箱"
```

---

## 二、首次发布（仓库已就绪，只需推送）

本地已完成 `git init` + 首次提交。**剩下只有两步**：

1. 在 GitHub 上**新建空仓库**（不要勾选 README / .gitignore / License，本地已有）
2. 关联并推送：

```powershell
$env:Path = "D:\Git\cmd;" + $env:Path
cd D:\HarmonyOS\smu-pocket

git remote add origin https://github.com/<你的用户名>/smu-pocket-harmony.git
git push -u origin main
```

> 如果 GitHub 推送很慢或超时，先确认 Clash 在跑（本机代理 127.0.0.1:7897）：
> ```powershell
> git config --global http.proxy http://127.0.0.1:7897
> ```

---

## 三、⚠️ 推送前必看：确认没有泄露签名材料

`signing/` 目录里有你的**个人调试证书**（`.p7b` / `.pem` / Profile），
提交出去等于公开自己的签名身份，**必须**确认被排除。

### 本仓已修过的一个真实漏洞（务必理解）

`.gitignore` 曾写过：

```gitignore
*.hap
!dist/*.hap        # ← 这一行等于把所有 HAP 重新纳入，包括 *-signed.hap
```

`!` 是「**取消忽略**」，所以签名包会被一并提交。
**已改成只放行未签名包**：

```gitignore
*.hap
!dist/*-UNSIGNED.hap
```

### 推送前用这条自检（已实测有效）

```powershell
$env:Path = "D:\Git\cmd;" + $env:Path
cd D:\HarmonyOS\smu-pocket

# 看 git 真正会提交什么，再筛敏感项
git status --porcelain --untracked-files=all |
  Select-String 'signing/|\.(p12|p7b|pem|cer|jks|keystore)$|-signed\.hap|_private/'
# 期望：没有任何输出
```

> ⚠️ 不要用 `git check-ignore` 判断「未签名包有没有被保留」：
> 它只报告**最后一条匹配规则**，`!` 规则也会让它输出一行，
> 容易被误读成「被忽略了」。以 `git status` 的实际列表为准。

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

## 四、⚠️ 截图必须用演示数据（本次踩到的大坑）

这是**比签名材料更容易被忽略**的隐私风险。

### 问题

早期截图是直接在真机上截的，里面包含**真实学业数据**：

- 真实课表（第 8 周、2026-2027 学年第 1 学期）
- 真实教师姓名（邱清、吴让科、罗铭杰、王方…）
- 真实教室号（504智慧教室、804教室、珠江医院临床技能中心）
- **真实成绩单**（46 门课 / 5 个学期 / GPA 3.67 / 各学期 87.2、86.3…）

成绩单尤其敏感 —— 这类数据一旦推到 GitHub，即使删掉文件，
**Git 历史里仍然存在**，很难彻底清除。

### 解决

项目内置了完整的演示数据 `entry/src/main/ets/data/FakeJw.ets`，
课程（系统解剖学/生理学/大学英语）、老师（王老师/李老师）、
成绩都是虚构的。**用演示模式重新截图**。

重新截图的可靠做法（模拟器点击不稳时）：

```typescript
// RootScreen.ets —— 临时改，截完必须还原
aboutToAppear(): void {
  if (!this.booted) {
    this.booted = true;
    this.viewModel.enterDemo();   // 临时：进入演示模式
    // 原来：this.viewModel.bootstrap();
  }
}
```

浅色/深色切换同理，在 `pages/Index.ets` 里临时写死：
```typescript
this.isDark = false;   // 浅色截图用；还原为 prefersDark(context)
```

**截完务必还原这两处**，否则正式版会一启动就显示演示数据。

### 自查

```powershell
# 截图里不该出现这些真实姓名
Get-ChildItem screenshots -Recurse -File |
  Select-String -Pattern '邱清|吴让科|秦佳|李振林|504智慧教室' -List
# 期望：无输出（Select-String 对图片无效，改用肉眼核对或对比文件时间）
```

更实际的办法：**看文件修改时间**，只有本次新截的才算数。
真实数据的旧图备份已移到 `_private/`（已被 `.gitignore` 排除）。

---

## 五、关于 HAP 和 Release

**不要把调试签名的 HAP 传到 Release。** 原因见 [../dist/README.md](../dist/README.md)：
调试证书绑定了开发者本人的设备 UDID，别人装了也跑不起来，且会暴露签名身份。

`dist/` 里只保留**未签名**的 HAP，供使用者自行签名。

> 📌 **`dist/` 只保留最新一版**。历史版本已移到 `_private/dist-history/`（不提交），
> 因为 22 个历史包共约 24 MB，会让别人 `git clone` 很慢，
> 而且 Git 历史里的二进制文件基本删不干净。历史版本应走 GitHub Release 分发。

如果你想发一个别人能直接装的包，需要走正式流程：

1. 在 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)
   创建应用、填写包名 `com.smu.pocket`
2. 申请**发布证书**与**发布 Profile**（不是调试证书）
3. 用发布证书签名后，HAP 才可以被任意设备安装

> 注意：正式发布还要过华为的内容审核，且这类"非官方校园客户端"
> 可能不符合上架政策。**更适合的定位是开源项目**，让使用者自己编译签名。

---

## 六、仓库建议设置

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
