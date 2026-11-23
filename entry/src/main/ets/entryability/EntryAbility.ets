/**
 * 应用入口 Ability。
 *
 * 职责：
 * 1. 设置窗口为全屏、沉浸式；
 * 2. 把 UIAbilityContext 交给 AppContainer（存储需要它）；
 * 3. 加载首页。
 */
import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import hilog from '@ohos.hilog';
import Want from '@ohos.app.ability.Want';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import { prefersDark, applySystemBarColors } from '../core/SystemTheme';

const TAG: string = 'SmuPocket';
const DOMAIN: number = 0x0001;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onCreate');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 主窗口加载首页
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      // 使用系统默认布局（非沉浸式）：
      // 这样内容会自动避开状态栏与底部导航条，页面标题不会和状态栏时间重叠。
      // 之前设为 true（沉浸式全屏）但没有做安全区偏移，导致标题顶到状态栏底下。
      windowStage.getMainWindow().then((win: window.Window) => {
        win.setWindowLayoutFullScreen(false);
        win.setWindowSystemBarEnable(['status', 'navigation']);
        // 仅靠非沉浸式布局，系统栏会用自己的默认色（纯黑/纯白），
        // 和 App 自己的背景对不上 → 底部会出现一条可见的接缝。
        // 所以启动时立刻把系统栏染成与相邻 App 区域一致的颜色。
        return applySystemBarColors(this.context, prefersDark(this.context));
      }).catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'window setup failed: %{public}s', e.message);
      });
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
  }

  onBackground(): void {
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onDestroy');
  }
}
