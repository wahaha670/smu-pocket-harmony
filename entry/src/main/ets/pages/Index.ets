/**
 * 首页：装配容器与 ViewModel，然后挂上 RootScreen。
 *
 * 这是整个应用的唯一入口页面（module.json5 的 main_pages 指向它）。
 *
 * ⚠️ ArkTS 状态管理约束（踩过就会编译失败）：
 * - `@ObjectLink` 的父级必须提供**确定类型**的 @Observed 实例，
 *   不能是 `AppState | undefined` 这种联合类型。
 * - 所以这里用 `@State ready: boolean` 控制「装载完成」，
 *   装载完成后才渲染 RootScreen —— 此时 `appState` 一定有值。
 *   `!` 非空断言在 ArkTS 里可用，但更稳的做法是保证赋值顺序。
 */
import common from '@ohos.app.ability.common';
import Configuration from '@ohos.app.ability.Configuration';
import { AppContainer } from '../core/AppContainer';
import { AppViewModel, AppState } from '../core/AppViewModel';
import { RootScreen } from '../ui/RootScreen';
import { prefersDark, applySystemBarColors } from '../core/SystemTheme';
import { FontSize } from '../theme/Typography';

@Entry
@Component
struct Index {
  /** 容器与 ViewModel 都好了才置 true */
  @State ready: boolean = false;
  @State isDark: boolean = false;
  @State errorText: string = '';

  /**
   * 这两个必须是 @State 才能作为子组件 @ObjectLink 的来源。
   * 先给一个空 AppState（它无副作用），等容器建好后再换成真正的实例。
   * 用 `!` 会让 ArkTS 编译期检查更严，这里改用「先空后换」的稳妥写法。
   */
  @State private viewModel: AppViewModel | null = null;
  @State private appState: AppState = new AppState();

  private container: AppContainer | undefined = undefined;

  aboutToAppear(): void {
    this.init();
  }

  /**
   * 初始化：容器里两个存储都是异步 Preferences，必须 await。
   * 失败时给出可读的错误，而不是白屏。
   */
  private async init(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.isDark = prefersDark(context);

      const container = await AppContainer.create(context);
      this.container = container;

      const vm = container.buildViewModel();
      this.viewModel = vm;
      this.appState = vm.state;
      this.ready = true;
    } catch (e) {
      const err = e as Error;
      this.errorText = `初始化失败：${err.message !== undefined ? err.message : '未知错误'}`;
    }
  }

  /**
   * 跟随系统深浅色变化。
   *
   * 这里不直接比较 `newConfig.colorMode`：
   * 在 @Entry 组件里，该回调参数的实际类型与 `@ohos.app.ability.Configuration`
   * 的声明不完全一致，直接跟 `ConfigurationConstant.ColorMode` 比会被
   * TS 判为「string 与 ColorMode 无重叠」。
   * 改为统一走 prefersDark()，把类型细节收敛到一个地方。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    this.isDark = prefersDark(ctx);
    // 深浅色一变，系统栏的颜色也要跟着变，
    // 否则切到深色后底部导航条区域还是浅色，又会露出接缝。
    applySystemBarColors(ctx, this.isDark);
  }

  build() {
    Column() {
      if (this.errorText.length > 0) {
        Column() {
          Text('南医大口袋')
            .fontSize(FontSize.headline)
            .fontWeight(FontWeight.Bold)
          Text(this.errorText)
            .fontSize(FontSize.body)
            .margin({ top: 12 })
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .padding(24)
      } else if (!this.ready || this.viewModel === null) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
          Text('正在启动…')
            .fontSize(FontSize.smallBody)
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        RootScreen({
          viewModel: this.viewModel,
          state: this.appState,
          isDark: this.isDark
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
