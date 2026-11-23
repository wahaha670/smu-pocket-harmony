/**
 * 系统深浅色检测 + 系统栏配色。
 *
 * HarmonyOS 通过 `Configuration.colorMode` 判断，
 * 值域是 `ConfigurationConstant.ColorMode`。
 *
 * ⚠️ `config.colorMode` 的类型是 `ColorMode | undefined`，
 * 直接赋给 `ColorMode` 会报类型错误，必须先判 undefined。
 */
import common from '@ohos.app.ability.common';
import ConfigurationConstant from '@ohos.app.ability.ConfigurationConstant';
import window from '@ohos.window';
import hilog from '@ohos.hilog';
import { Theme } from '../theme/Theme';

const TAG: string = 'SmuPocket';

/** 读当前是否深色 */
export function prefersDark(context?: common.UIAbilityContext): boolean {
  try {
    if (context === undefined) {
      // 没有 context 时退回 AppStorage 里缓存的值
      const cached = AppStorage.get<number>('colorMode');
      return cached === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    const mode: ConfigurationConstant.ColorMode | undefined = context.config.colorMode;
    if (mode === undefined) {
      return false;
    }
    return mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  } catch (e) {
    return false;
  }
}

/**
 * 让系统状态栏 / 导航条区域的颜色与 App 自己的配色一致。
 *
 * ## 为什么需要这一步
 *
 * App 用的是「非沉浸式」布局（`setWindowLayoutFullScreen(false)`），
 * 好处是内容自动避开状态栏和底部导航条，页面标题不会顶到时间底下。
 *
 * 但代价是：**状态栏和底部导航条区域由系统自己上色**，
 * 默认是纯黑/纯白，于是和 App 自己的背景色对不上 —— 出现一条接缝。
 *
 * 实测数据（深色模式，Mate 分辨率）：
 * ```
 * App 底栏        #1A1D22
 * 系统导航条区域   #000000   ← 两种深色相邻，肉眼可见一条分界
 * ```
 * 浅色模式下两边都是白，所以这个问题只在深色下暴露。
 *
 * ## 做法
 *
 * 把两个系统栏区域染成**和它紧邻的 App 区域相同的颜色**：
 * - 状态栏 → App 的背景色（`background`）
 * - 导航条 → App 底部导航栏的颜色（`surface`）
 *
 * 这样视觉上就等于 App 的背景一路铺到了屏幕边缘。
 *
 * 失败不影响功能（只是外观退化），所以整体包在 try/catch 里。
 */
export async function applySystemBarColors(
  context: common.UIAbilityContext,
  isDark: boolean
): Promise<void> {
  try {
    const c = Theme.colors(isDark);
    const win = await window.getLastWindow(context);

    // 窗口背景色：系统栏区域没有内容时透出的就是它。
    //
    // ⚠️ 实测要点：`setWindowSystemBarProperties` 的 `navigationBarColor`
    // 在手势导航下**会被系统忽略**（日志里该项为 null），
    // 但 `setWindowBackgroundColor` 是生效的 —— 底部导航条区域透出的
    // 正是这个窗口背景色。
    //
    // 所以这里取 `surface` 而不是 `background`：
    // 底部紧邻系统栏的是**底部导航栏**，它的颜色就是 surface，
    // 窗口背景与它一致，接缝才会彻底消失。
    // （顶部状态栏由上面的 statusBarColor 单独负责，不受这里影响。）
    await win.setWindowBackgroundColor(c.surface);

    await win.setWindowSystemBarProperties({
      // 顶部状态栏：与页面背景同色
      statusBarColor: c.background,
      statusBarContentColor: c.onSurface,
      // 底部导航条：与 App 底部导航栏同色 —— 接缝就消失在这一步
      navigationBarColor: c.surface,
      navigationBarContentColor: c.onSurfaceVariant,
      // 关闭切换动画，避免切深浅色时系统栏颜色"闪"一下
      enableStatusBarAnimation: false,
      enableNavigationBarAnimation: false
    });
  } catch (e) {
    const err = e as Error;
    hilog.warn(0x0001, TAG, 'applySystemBarColors failed: %{public}s',
      err !== undefined && err.message !== undefined ? err.message : 'unknown');
  }
}

