# Mate 80 Pro Max 适配说明

> 目标机型：**HUAWEI Mate 80 Pro Max**
> 实测环境：HarmonyOS 模拟器（已改为同分辨率），2026-11-13

---

## 一、目标机型规格（华为官网数据）

| 项 | 值 |
|---|---|
| **屏幕分辨率** | **2848 × 1320**（竖屏时 1320 × 2848） |
| 屏幕尺寸 | 6.9 英寸 |
| 宽高比 | **2.1576**（1320 : 2848） |
| 屏幕类型 | 双层 OLED，1–120Hz LTPO |
| 机身尺寸 | 164.4 × 79 × 8.25 mm |
| 重量 | 约 239 g |
| 处理器 | 麒麟 9030 Pro |
| 系统 | HarmonyOS 6.0 |

**像素密度推算**：1320px 宽 / 6.9 英寸屏、79mm 机宽 → dpi ≈ 480（scale 3.0）
→ 逻辑分辨率约 **440 × 949 vp**

---

## 二、与旧测试环境的差异

改造前模拟器用的是默认 phone 尺寸，与真机差异明显：

| 项 | 改造前（默认 phone） | Mate 80 Pro Max | 差异 |
|---|---|---|---|
| 分辨率 | 1320 × 2232 | **1320 × 2848** | 高度 **+616px（+27.6%）** |
| 宽高比 | 1.6909 | **2.1576** | 更修长 |
| 逻辑高度 | 约 744 vp | 约 **949 vp** | +205vp |

> ⚠️ 按 2232 调出来的布局，在真机上会显得「内容偏少、留白多」。
> 所以必须按 2848 重新验证。

---

## 三、如何把模拟器改成 Mate 尺寸（已执行）

模拟器创建命令不支持自定义分辨率，但可以改实例配置：

```powershell
# 1. 先停掉模拟器
$deveco = '$env:APPDATA\xiaoyiwork\connectors\deveco\devecocli.cmd'
& $deveco emulator stop "smuphone"

# 2. 改配置（路径固定）
$cfg = "$env:LOCALAPPDATA\Huawei\Emulator\deployed\smuphone\config.ini"

# 3. 把这两行改掉
#    hw.lcd.single.height=2232   →  2848
#    hw.lcd.single.diagonalSize=6.39  →  6.9
```

改完后**必须重新接受一次协议**（改配置会重置校验状态）：

```powershell
& $deveco emulator license accept
& $deveco emulator start "smuphone"
```

验证：

```powershell
$hdc = 'D:\HarmonyOS\commandline-tools\command-line-tools\sdk\default\openharmony\toolchains\hdc.exe'
& $hdc -t 127.0.0.1:5555 shell snapshot_display -f /data/local/tmp/x.jpeg
# 输出应为 width: 1320, height: 2848
```

> 💡 回滚：把 `hw.lcd.single.height` 改回 2232、`diagonalSize` 改回 6.39。
> 备份在 `config.ini.bak-2232`。

---

## 四、适配改动

### 4.1 课表单元格高度自适应

**问题**：单元格高度原先硬编码 62vp。在不同长宽比的机型上，
要么留白过多（长屏），要么显示过少（矮屏）。

**方案**：用 `onAreaChange` 测出网格实际可用高度，动态算单节高度。

```typescript
private cellHeight(): number {
  if (this.gridAreaHeight <= 0) return CELL_HEIGHT_BASE;  // 62
  const fit = (this.gridAreaHeight - 8) / 14;             // 14 节平分
  if (fit <= CELL_HEIGHT_BASE) return CELL_HEIGHT_BASE;   // 放不下→用基准，靠滚动
  return Math.min(fit, 96);                               // 上限 96，避免过空
}
```

**在 Mate 80 Pro Max 上的实际表现**：

| 计算项 | 值 |
|---|---|
| 逻辑高度 | 949 vp |
| 减去状态栏/标题/周次条/表头/翻周/底部导航 | 网格可用约 **616 vp** |
| 616 / 14 | ≈ 44 vp |
| 44 < 62 | → **保持 62vp，靠滚动** |

这是**刻意的取舍**：如果强行塞进 14 节，每节只有 44vp，
课名+教室+内容三行文字会挤在一起、字号要缩到 8 以下，反而看不清。

**实测效果**：一屏可见 **10 节**（原 2232 高度时只有 8 节），
滚动后完整看到 11–14 节，晚课区留空正确。

### 4.2 修复设置页顶部异常留白（真实 bug）

**现象**：在长屏上，设置页标题被压低，顶部凭空多出约 170px 空白；
今日/课表/成绩页都正常。实测各页内容起始位置：

| 页面 | 修复前 | 修复后 |
|---|---|---|
| 今日 | y=182 | y=182 |
| 课表 | y=170 | — |
| 成绩 | y=172 | — |
| **设置** | **y=346** ❌ | **y=174** ✅ |

**根因**：**ArkUI 的 `Scroll` 默认按 `Alignment.Center` 摆放内容**。

- 今日页内容很长（6 场考试），填满视口 → 看不出问题；
- 设置页内容比视口短 → 整块被**垂直居中**，顶部就多出空白。

而且内容越短偏移越大，属于「换台更长的手机会更明显」的隐藏问题。

**修复**：给 `Scroll` 显式指定顶部对齐。

```typescript
Scroll() { ... }
  .scrollable(ScrollDirection.Vertical)
  .width('100%')
  .height('100%')
  .align(Alignment.Top)   // ← 关键
```

今日页也一并加上，避免将来「假期没课没考试、内容变短」时重现同样问题。

> 📌 排查过程中的教训：我一开始误判为「`ScreenHeader` 组件导致偏移」，
> 改成内联标题后**实测仍是 346，证明判断错误**。
> 真正的定位方法是**用像素测量对比各页内容起始位置**（写脚本扫截图里第一行非空像素），
> 而不是凭肉眼觉得「这页看起来偏低」。改代码前先拿到可量化的证据，能少走弯路。

### 4.3 安全区

`EntryAbility` 里已设 `setWindowLayoutFullScreen(false)`，
系统自动避让状态栏与手势条。实测布局 dump：

```
标题「第 14 周 · 11月」 bounds = [60, 165, 521, 242]
状态栏约到 y=100
```

两者不重叠，**安全区正确**，无需额外处理。

### 4.4 列表页受益于更高的屏幕

长屏带来的额外高度全部用于展示内容，无需改动：

| 页面 | 2232 高度 | 2848 高度 |
|---|---|---|
| **今日页** | 考试安排显示 2 场 | **显示 6 场（到今天 1 月 4 日）** |
| 课表页 | 一屏 8 节 | **一屏 10 节** |
| 成绩页 | 学期列表可滚动 | 5 个学期全部可见 + 留白 |

---

## 五、验证清单（Mate 80 Pro Max 分辨率实测）

| 项 | 结果 |
|---|---|
| 分辨率正确 | ✅ 1320 × 2848 |
| 标题不与状态栏重叠 | ✅ 标题 y=165，状态栏约到 y=100 |
| 课表 14 节完整可达 | ✅ 滚动后 11–14 节都在 |
| 底部导航可点击 | ✅ 四个 Tab 正常切换 |
| 卡片右侧不溢出 | ✅ 之前修的 `CardBox` width 问题在长屏同样正常 |
| 切周内容刷新 | ✅ 正常 |
| 离线缓存显示 | ✅ 正常 |
| 周次月份 + 日期 | ✅ 正常（跨月圆点显示） |

---

## 六、其他直板机的适配策略

代码没有硬编码任何机型尺寸，用的是相对布局 + 自适应高度，所以理论上适配所有直板机：

| 机型类型 | 典型分辨率 | 宽高比 | 表现 |
|---|---|---|---|
| 长屏旗舰（Mate 80 Pro Max） | 1320×2848 | 2.16 | 一屏 10 节，其余滚动 |
| 常规旗舰 | 1200×2616 等 | 2.18 | 同上 |
| 中端/旧机型 | 1080×2340 等 | 2.17 | 同上（vp 换算后接近） |
| 矮屏机型 | 1080×1920 | 1.78 | 一屏约 7 节，靠滚动 |

**关键点**：`cellHeight()` 的 `Math.min(fit, 96)` 上限，
保证在 2in1 / 平板这类高屏设备上格子不会被拉得过于空旷。

---

## 七、如果想在真机上验证

1. 手机开启开发者模式 + USB 调试
2. 连接电脑，`hdc list targets` 应出现设备序列号
3. 签名（真机必需，模拟器不需要）：
   ```powershell
   & $deveco auth login
   Push-Location 'D:\HarmonyOS\smu-pocket'
   & $deveco signature generate --product default
   Pop-Location
   ```
4. 安装运行：
   ```powershell
   & $deveco run --device <你的设备序列号>
   ```
