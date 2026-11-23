/**
 * 根页面：登录与否的分发 + 底部导航。
 *
 * 对齐 Android 版 ui/RootScreen.kt。
 *
 * ⚠️ 全工程统一用 **状态管理 V1**（@State/@Prop/@ObjectLink/@Link），
 * 不使用 V2 的 @ComponentV2/@Monitor/@Local —— 两者混用会编译失败。
 *
 * 子页面不直接持有 ViewModel：切周、同步、退出这类动作
 * 通过 **回调 prop** 上抛给 RootScreen，由它统一调用 ViewModel。
 * 这比用 AppStorage 传"意图"更直接，也避免时序问题。
 */
import { Theme } from '../theme/Theme';
import { AppState, AppViewModel } from '../core/AppViewModel';
import { LoginScreen } from './login/LoginScreen';
import { TodayScreen } from './today/TodayScreen';
import { ScheduleScreen } from './schedule/ScheduleScreen';
import { GradesScreen } from './grades/GradesScreen';
import { SettingsScreen } from './settings/SettingsScreen';
import { FontSize } from '../theme/Typography';

interface TabItem {
  label: string;
  icon: string;
}

@Component
export struct RootScreen {
  @ObjectLink viewModel: AppViewModel;
  @ObjectLink state: AppState;
  @Prop isDark: boolean = false;

  @State currentTab: number = 0;
  /** 已经触发过首次加载，避免重复 */
  private booted: boolean = false;

  aboutToAppear(): void {
    if (!this.booted) {
      this.booted = true;
      // 启动时先亮缓存，再后台刷新。
      // 卡片刷新已收口在 loadAll 内部（成功后自动 reloadForms），
      // 这里不再重复调用。
      this.viewModel.bootstrap();
    }
  }

  build() {
    Column() {
      if (!this.state.loggedIn) {
        LoginScreen({
          state: this.state,
          isDark: this.isDark,
          onDemo: (): void => {
            this.viewModel.enterDemo();
          },
          onCookieHarvested: (host: string, cookie: string): void => {
            this.viewModel.onLoginCookies(host, cookie);
          },
          verifySession: (): Promise<boolean> => {
            return this.viewModel.verifySession();
          },
          onLoginCancelled: (): void => {
            this.viewModel.onLoginCancelled();
          },
          // 用户点了「重新登录以同步」时，登录页一挂载就自动打开扫码。
          // 用回调而不是布尔值：LoginScreen 在 aboutToAppear 里调用它，
          // 保证「只在挂载那一刻消费一次」，不会被 build 的反复重渲染影响。
          consumeAutoStart: (): boolean => {
            return this.viewModel.consumeAutoLoginFlag();
          }
        })
      } else {
        Column() {
          if (this.currentTab === 0) {
            TodayScreen({ state: this.state, isDark: this.isDark })
          } else if (this.currentTab === 1) {
            ScheduleScreen({
              state: this.state,
              isDark: this.isDark,
              onSelectWeek: (week: number): void => {
                this.viewModel.selectWeek(week);
              },
              onPrevWeek: (): void => {
                this.viewModel.prevWeek();
              },
              onNextWeek: (): void => {
                this.viewModel.nextWeek();
              }
            })
          } else if (this.currentTab === 2) {
            GradesScreen({ state: this.state, isDark: this.isDark })
          } else {
            SettingsScreen({
              state: this.state,
              isDark: this.isDark,
              onSync: (): void => {
                // 卡片刷新已在 loadAll 内部收口（成功后自动 reloadForms），
                // 这里不再重复调用，避免同一次同步触发两遍重绘。
                this.viewModel.syncNow();
              },
              onReloginSync: (): void => {
                // 「重新登录以同步最新数据」：真正清会话并触发扫码登录，
                // 登录成功后 LoginScreen 会自动跑一次 loadAll() 同步。
                this.viewModel.reloginAndSync();
              },
              onLogout: (): void => {
                this.viewModel.logout();
              },
              onFillContents: async (): Promise<string> => {
                // 逐周拉取上课内容，合并进整学期缓存；完成后刷新卡片
                const weeks: number = await this.viewModel.fillAllWeekContents(
                  (done: number, total: number): void => {
                    console.info(`[fill] ${done}/${total}`);
                  }
                );
                this.viewModel.refreshWidgets();
                if (weeks === 0) {
                  return '所有周的上课内容都已完整，无需补全';
                }
                return `已补全 ${weeks} 周的上课内容`;
              }
            })
          }
        }
        .width('100%')
        .layoutWeight(1)

        // 底部导航
        Row() {
          ForEach(this.tabs(), (tab: TabItem, idx: number) => {
            Column() {
              Text(tab.icon)
                .fontSize(FontSize.titleLarge)
                .fontColor(idx === this.currentTab
                  ? Theme.colors(this.isDark).primary
                  : Theme.colors(this.isDark).onSurfaceVariant)
              Text(tab.label)
                .fontSize(FontSize.caption)
                .margin({ top: 2 })
                .fontColor(idx === this.currentTab
                  ? Theme.colors(this.isDark).primary
                  : Theme.colors(this.isDark).onSurfaceVariant)
            }
            .layoutWeight(1)
            .padding({ top: 8, bottom: 12 })
            .alignItems(HorizontalAlign.Center)
            .height(58)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.currentTab = idx;
            })
          }, (tab: TabItem, idx: number) => `tab_${idx}`)
        }
        .width('100%')
        .height(58)
        .backgroundColor(Theme.colors(this.isDark).surface)
        .border({ width: { top: 1 }, color: Theme.colors(this.isDark).outline })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.colors(this.isDark).background)
  }

  private tabs(): TabItem[] {
    return [
      { label: '今日', icon: '☀' },
      { label: '课表', icon: '▤' },
      { label: '成绩', icon: '★' },
      { label: '设置', icon: '⚙' }
    ];
  }
}
