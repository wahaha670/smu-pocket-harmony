/**
 * 设置页。
 *
 * 内容：同步入口 / 接入状态 / 退出登录 / 关于 / 开发者与反馈。
 *
 * 移植自 Android 版 ui/settings/SettingsScreen.kt。
 */
import pasteboard from '@ohos.pasteboard';
import { Theme } from '../../theme/Theme';
import { AppState } from '../../core/AppViewModel';
import { CardBox, LabelValue } from '../components/Common';
import { humanizeAgo, formatDate } from '../../core/DateUtils';
import {
  probeLiveView, probeLiveViewDeep, LiveViewProbe, LiveViewStatus,
  startCourseLiveView, stopAllCourseLiveViews
} from '../../core/LiveView';
import { Course } from '../../core/Models';
import { getPushToken, PushTokenResult } from '../../core/PushToken';
import { FontSize } from '../../theme/Typography';

/** 更新通知 / 问题反馈 QQ 群。点一下复制到剪贴板 */
const QQ_GROUP: string = '1128162850';

/** App 版本号 */
const APP_VERSION: string = 'v1.1.1';

@Component
export struct SettingsScreen {
  @ObjectLink state: AppState;
  @Prop isDark: boolean = false;

  /** 复制成功的提示文案 */
  @State toast: string = '';

  /** 实况窗是否开启（本次运行内的开关，暂不落盘） */
  @State liveViewOn: boolean = false;
  /** 提前多少分钟提醒 */
  @State leadMinutes: number = 15;
  /** 实况窗可用性探测结果 */
  @State liveViewHint: string = '点击探测本机实况窗是否可用';
  /** 探测到的状态 */
  @State liveViewState: string = '';
  /** Push Token（白名单调试要用） */
  @State pushToken: string = '';
  @State pushTokenHint: string = '白名单调试需要先把 Push Token 填进 AGC';

  /**
   * 程序内部复位开关时，抑制随之而来的 onChange 回调。
   *
   * 为什么必须要有它：Toggle 是受控组件（isOn 绑定本字段）。我们把
   * liveViewOn 从 true 改回 false 时，ArkUI 会再触发一次 onChange(false)，
   * 而那次回调会走 applyLiveView 的 on=false 分支，把刚写好的
   * 「失败原因」覆盖成「已关闭提醒」—— 用户就永远看不到真正的错误。
   * 用普通字段（非 @State）即可，不需要参与渲染。
   */
  private suppressToggle: boolean = false;

  /** 「补全全部周内容」进行中的进度文案；空串 = 空闲 */
  @State fillProgress: string = '';
  /** 补全结果提示 */
  @State fillResult: string = '';
  /** 是否正在补全（用于禁用按钮、防重复点击） */
  @State filling: boolean = false;

  /** 由父组件注入的动作 */
  onSync: () => void = () => {};
  /**
   * 「重新登录并同步」：必须真正触发登录流程，而不只是切回登录页。
   *
   * 由 RootScreen 注入 `viewModel.reloginAndSync()`。
   */
  onReloginSync: () => void = () => {};
  onLogout: () => void = () => {};
  /** 补全全部周上课内容：返回「已补全周数」的说明文案 */
  onFillContents: () => Promise<string> = async () => '';

  build() {
    Scroll() {
      Column() {
        // 标题：与今日页/成绩页保持完全一致的内联结构
        Column() {
          Text('设置')
            .fontSize(FontSize.display)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.colors(this.isDark).onSurface)
          Text('非官方客户端 · 数据直连学校系统 · 不经过第三方服务器')
            .fontSize(FontSize.smallBody)
            .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
            .margin({ top: 3 })
            .maxLines(2)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 20, right: 20, top: 16, bottom: 10 })

        // ---- 同步入口 ----
        CardBox({ isDark: this.isDark }) {
          this.SyncCard()
        }

        // ---- 接入状态 ----
        CardBox({ isDark: this.isDark }) {
          this.StatusCard()
        }

        // ---- 实况窗提醒 ----
        CardBox({ isDark: this.isDark }) {
          this.LiveViewCard()
        }

        // ---- 退出登录 ----
        CardBox({ isDark: this.isDark }) {
          this.LogoutCard()
        }

        // ---- 关于 ----
        CardBox({ isDark: this.isDark }) {
          this.AboutCard()
        }

        // ---- 开发者与反馈 ----
        CardBox({ isDark: this.isDark }) {
          this.DeveloperCard()
        }

        Text(`南医大口袋 ${APP_VERSION} · 遵循 GPL-3.0 开源协议`)
          .fontSize(FontSize.caption)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .opacity(0.7)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 8, bottom: 24 })
      }
      .width('100%')
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    // ⚠️ 必须显式顶部对齐。
    // ArkUI 的 Scroll 默认按 Alignment.Center 摆放内容，
    // 当内容比视口短时（设置页就是这种情况）整块会被垂直居中，
    // 表现为顶部凭空多出 ~170px 空白、标题被压低。
    .align(Alignment.Top)
    .backgroundColor(Theme.colors(this.isDark).background)
  }

  /**
   * 实况窗提醒卡片。
   *
   * ⚠️ 实况窗的 event 只有 15 个官方商业场景（打车/外卖/航班/计时…），
   * **没有「上课」**，且必须向华为申请场景权限。所以这里如实把状态显示出来，
   * 拿不到权限时给明确指引，而不是让用户面对一个无声失败的开关。
   */
  @Builder
  LiveViewCard() {
    Column() {
      Row() {
        Text('开课前实况窗提醒')
          .fontSize(FontSize.bodyStrong)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.colors(this.isDark).onSurface)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.liveViewOn })
          .onChange((on: boolean) => {
            if (this.suppressToggle) {
              // 这是我们自己复位引起的回声，忽略它，保住失败原因
              this.suppressToggle = false;
              return;
            }
            this.liveViewOn = on;
            this.applyLiveView(on);
          })
      }
      .width('100%')

      Text('上课前在实况窗/锁屏上常驻显示课程，到点响铃提醒')
        .fontSize(FontSize.small)
        .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        .margin({ top: 6 })
        .width('100%')

      // 提前分钟数
      Row() {
        Text('提前')
          .fontSize(FontSize.smallBody)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        Text(`${this.leadMinutes} 分钟`)
          .fontSize(FontSize.smallBody)
          .fontColor(Theme.colors(this.isDark).primary)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 6 })
          .layoutWeight(1)
        ForEach([5, 10, 15, 30], (m: number) => {
          Text(`${m}`)
            .fontSize(FontSize.small)
            .fontColor(this.leadMinutes === m
              ? Theme.colors(this.isDark).primary
              : Theme.colors(this.isDark).onSurfaceVariant)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .borderWidth(1)
            .borderColor(this.leadMinutes === m
              ? Theme.colors(this.isDark).primary
              : Theme.colors(this.isDark).outline)
            .margin({ left: 4 })
            .onClick(() => {
              this.leadMinutes = m;
              if (this.liveViewOn) {
                this.applyLiveView(true);
              }
            })
        }, (m: number) => `lead_${m}`)
      }
      .width('100%')
      .margin({ top: 12 })

      // 状态说明
      Text(this.liveViewHint)
        .fontSize(FontSize.caption)
        .fontColor(this.liveViewState === LiveViewStatus.READY
          ? Theme.colors(this.isDark).primary
          : Theme.colors(this.isDark).warning)
        .margin({ top: 10 })
        .width('100%')

      Button('检测实况窗权限')
        .width('100%')
        .fontSize(FontSize.smallBody)
        .backgroundColor(Theme.colors(this.isDark).surfaceVariant)
        .fontColor(Theme.colors(this.isDark).onSurface)
        .margin({ top: 10 })
        .onClick(() => {
          this.checkLiveView();
        })

      Divider()
        .color(Theme.colors(this.isDark).outline)
        .margin({ top: 14, bottom: 10 })

      // ---- Push Token：白名单调试按 Token 添加设备 ----
      Text('Push Token（白名单调试用）')
        .fontSize(FontSize.small)
        .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        .width('100%')

      Text(this.pushToken.length > 0 ? this.pushToken : '未获取')
        .fontSize(FontSize.caption)
        .fontColor(this.pushToken.length > 0
          ? Theme.colors(this.isDark).onSurface
          : Theme.colors(this.isDark).onSurfaceVariant)
        .width('100%')
        .maxLines(3)
        .margin({ top: 4 })

      Text(this.pushTokenHint)
        .fontSize(FontSize.caption)
        .fontColor(this.pushToken.length > 0
          ? Theme.colors(this.isDark).primary
          : Theme.colors(this.isDark).warning)
        .width('100%')
        .maxLines(3)
        .margin({ top: 6 })

      Row() {
        Button('获取 Push Token')
          .fontSize(FontSize.small)
          .layoutWeight(1)
          .backgroundColor(Theme.colors(this.isDark).surfaceVariant)
          .fontColor(Theme.colors(this.isDark).onSurface)
          .onClick(() => {
            this.loadPushToken();
          })
        if (this.pushToken.length > 0) {
          Button('复制')
            .fontSize(FontSize.small)
            .margin({ left: 8 })
            .backgroundColor(Theme.colors(this.isDark).primary)
            .onClick(() => {
              try {
                const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.pushToken);
                pasteboard.getSystemPasteboard().setDataSync(data);
                this.pushTokenHint = 'Push Token 已复制';
              } catch (e) {
                this.pushTokenHint = '复制失败';
              }
            })
        }
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  SyncCard() {
    Column() {
      // 按钮文案随状态变化，**行为与文案严格对应**：
      //
      // - 「重新登录以同步最新数据」（离线/过期）
      //     → 走 onReloginSync：清旧会话 + 自动打开扫码登录 + 登录后自动同步
      // - 「同步最新课表与成绩」（在线）
      //     → 走 onSync：直接静默刷新
      //
      // ⚠️ 之前两种文案都走 onSync，而 onSync 在无会话时只会切回登录页、
      //    让用户自己再点一次扫码 —— 按钮只做了一半，名不副实。
      Button(this.syncButtonText())
        .width('100%')
        .fontSize(FontSize.bodyStrong)
        .enabled(!this.state.loading)
        .backgroundColor(this.state.stale
          ? Theme.colors(this.isDark).warning
          : Theme.colors(this.isDark).primary)
        .onClick(() => {
          if (this.state.stale) {
            this.onReloginSync();
          } else {
            this.onSync();
          }
        })

      Text(this.syncHint())
        .fontSize(FontSize.caption)
        .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        .margin({ top: 8 })

      // ---- 补全全部周上课内容 ----
      //
      // 教务的「整学期总表」只对部分课程返回 sknrjj（上课内容），
      // 实测 220 条里仅 43 条有值；而「按周查询」当周全带。
      // 所以这里逐周拉一遍，把内容合并进整学期缓存。
      Divider()
        .color(Theme.colors(this.isDark).outline)
        .margin({ top: 14, bottom: 12 })

      Button(this.filling ? this.fillProgress : '补全全部周的上课内容')
        .width('100%')
        .fontSize(FontSize.body)
        .enabled(!this.filling && this.canFill())
        .backgroundColor(Theme.colors(this.isDark).surfaceVariant)
        .fontColor(this.canFill()
          ? Theme.colors(this.isDark).onSurface
          : Theme.colors(this.isDark).onSurfaceVariant)
        .opacity(this.canFill() ? 1 : 0.5)
        .onClick(() => {
          this.runFill();
        })

      Text(this.fillHintText())
        .fontSize(FontSize.caption)
        .fontColor(this.fillResult.length > 0
          ? Theme.colors(this.isDark).primary
          : Theme.colors(this.isDark).onSurfaceVariant)
        .margin({ top: 6 })
        .width('100%')
        .maxLines(3)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 补全按钮是否可点。
   *
   * 三个前置条件：
   * - 不在补全中（防重复点击）
   * - 不是在演示模式（演示数据是假数据，补全无意义）
   * - 不是离线缓存（离线时没有会话，拉不到内容）
   */
  private canFill(): boolean {
    return !this.state.stale && !this.state.demoMode && !this.state.loading;
  }

  /** 补全区域的提示文案 */
  private fillHintText(): string {
    if (this.fillResult.length > 0) {
      return this.fillResult;
    }
    if (this.state.demoMode) {
      return '当前是演示数据，无法补全。请先登录教务系统';
    }
    if (this.state.stale) {
      return '当前是离线缓存，需重新登录后才能补全';
    }
    return '逐周拉取，约需 10–20 秒。补全后翻任意周都能看到上课内容';
  }

  /** 执行补全：按钮状态 + 进度 + 结果 */
  private async runFill(): Promise<void> {
    if (this.filling) {
      return;
    }
    this.filling = true;
    this.fillResult = '';
    this.fillProgress = '准备中…';
    try {
      const msg: string = await this.onFillContents();
      this.fillResult = msg;
    } catch (e) {
      this.fillResult = '补全失败，请检查网络后重试';
    } finally {
      this.filling = false;
      this.fillProgress = '';
    }
  }

  /** 由父组件推进度（可选） */
  setFillProgress(done: number, total: number): void {
    this.fillProgress = `补全中 ${done}/${total}…`;
  }

  /** 同步按钮文案：随在线/离线状态变化 */
  private syncButtonText(): string {
    if (this.state.loading) {
      return '同步中…';
    }
    if (this.state.stale) {
      return '重新登录以同步最新数据';
    }
    return '同步最新课表与成绩';
  }

  @Builder
  StatusCard() {
    Column() {
      Text('接入状态')
        .fontSize(FontSize.bodyStrong)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.colors(this.isDark).onSurface)

      // 「教务系统」是本卡片最需要一眼看清的状态：
      // 离线时用橙色强调，未接入用灰色，正常接入用主色。
      LabelValue({
        label: '教务系统',
        value: this.connectionState(),
        isDark: this.isDark,
        valueColor: this.connectionColor()
      })
      LabelValue({
        label: '当前学期',
        value: this.state.config !== undefined ? this.state.config.termName : '—',
        isDark: this.isDark
      })
      LabelValue({ label: '学期代码', value: this.termCodeText(), isDark: this.isDark })
      LabelValue({ label: '第一周周一', value: this.firstMondayText(), isDark: this.isDark })
      LabelValue({
        label: '总周数',
        value: this.state.config !== undefined ? `${this.state.config.totalWeeks}` : '—',
        isDark: this.isDark
      })
      LabelValue({
        label: '课表数据',
        value: this.courseDataText(),
        isDark: this.isDark,
        valueColor: this.state.stale ? Theme.colors(this.isDark).warning : ''
      })
      LabelValue({
        label: '成绩数据',
        value: this.gradeDataText(),
        isDark: this.isDark,
        valueColor: this.state.stale ? Theme.colors(this.isDark).warning : ''
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  LogoutCard() {
    Column() {
      Button('退出登录（清空登录态）')
        .width('100%')
        .fontSize(FontSize.body)
        .fontColor(Theme.colors(this.isDark).error)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onLogout();
        })
      Text('退出后会同时清空本地缓存，下次需要重新扫码。')
        .fontSize(FontSize.caption)
        .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  AboutCard() {
    Column() {
      Text('关于')
        .fontSize(FontSize.bodyStrong)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.colors(this.isDark).onSurface)
      Text(`南医大口袋 ${APP_VERSION}`)
        .fontSize(FontSize.smallBody)
        .fontColor(Theme.colors(this.isDark).onSurface)
        .margin({ top: 6 })
      Text('账号密码只在学校的登录页输入，App 不保存密码、不上传任何数据。')
        .fontSize(FontSize.smallBody)
        .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        .margin({ top: 2 })
      Text('本项目仅供学习交流与个人使用，请遵守学校信息系统使用规定，不要高频请求。')
        .fontSize(FontSize.caption)
        .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        .margin({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  DeveloperCard() {
    Column() {
      Text('开发者：QIU')
        .fontSize(FontSize.caption)
        .fontColor(Theme.colors(this.isDark).onSurfaceVariant)

      Row() {
        Text('更新通知 / 问题反馈 QQ 群：')
          .fontSize(FontSize.caption)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        Text(QQ_GROUP)
          .fontSize(FontSize.caption)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .decoration({ type: TextDecorationType.Underline })
      }
      .margin({ top: 4 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.copyQqGroup();
      })

      if (this.toast.length > 0) {
        Text(this.toast)
          .fontSize(FontSize.caption)
          .fontColor(Theme.colors(this.isDark).primary)
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 同步按钮下方的小字提示。
   *
   * 离线时要明确告诉用户「现在点同步会怎样」——
   * 否则他会以为点一下就恢复在线，实际会被弹回登录页。
   */
  private syncHint(): string {
    if (this.state.stale) {
      if (this.state.cachedAt > 0) {
        return `当前为离线缓存（更新于 ${humanizeAgo(this.state.cachedAt)}）。点上方按钮会要求重新扫码登录。`;
      }
      return '当前为离线缓存。点上方按钮会要求重新扫码登录。';
    }
    const tail = '如发现课程有变动或无法加载，请重新扫码登录。';
    if (this.state.cachedAt > 0) {
      return `当前数据更新于 ${humanizeAgo(this.state.cachedAt)}，${tail}`;
    }
    return tail;
  }

  /**
   * 「教务系统」这一行的状态文案。
   *
   * 三种状态互斥，措辞要让人一眼分清「现在能不能连上」：
   * - 演示模式：根本没接入
   * - 离线缓存：登录态已失效，数据全部来自本地
   * - 已接入：有有效登录态，数据是最新拉取的
   */
  private connectionState(): string {
    if (this.state.demoMode) {
      return '演示数据（未接入）';
    }
    if (this.state.stale) {
      return '离线缓存';
    }
    return '已接入';
  }

  /**
   * 「教务系统」状态对应的颜色。
   * 离线用橙色（提示需要注意），未接入用灰，正常接入用主色。
   */
  private connectionColor(): string {
    if (this.state.demoMode) {
      return Theme.colors(this.isDark).onSurfaceVariant;
    }
    if (this.state.stale) {
      return Theme.colors(this.isDark).warning;
    }
    return Theme.colors(this.isDark).primary;
  }

  /**
   * 「课表数据」这一行的值。
   *
   * 用**整学期条数**而不是「当前选中周条数」：
   * - 整学期数据才是离线可用的基础，用户关心的是「我本地存了多少课」；
   * - 只显示当前周会让人以为缓存很少（切到别的周数字又变了）。
   *
   * 离线时额外标注来源，和「教务系统」那一行呼应。
   */
  private courseDataText(): string {
    const termCount = this.state.termCourses.length;
    if (termCount > 0) {
      if (this.state.stale) {
        return `${termCount} 条（整学期 · 离线）`;
      }
      return `${termCount} 条（整学期）`;
    }
    // 没有整学期缓存时退回当前周条数
    const weekCount = this.state.scheduleCourses.length;
    if (this.state.stale) {
      return `${weekCount} 条（当前周 · 离线）`;
    }
    return `${weekCount} 条（当前周）`;
  }

  /**
   * 「成绩数据」这一行的值。
   * 成绩同样可以从缓存读取，离线时标注一下。
   */
  private gradeDataText(): string {
    const n = this.state.grades.length;
    if (this.state.stale) {
      return `${n} 条（离线）`;
    }
    return `${n} 条`;
  }

  /**
   * 只有真的在演示模式才敢标「演示数据」：缓存恢复时 semesterCode 是空的，
   * 那时显示「—（演示数据）」会让用户以为课表是假数据。
   */
  private termCodeText(): string {
    if (this.state.semesterCode.length > 0) {
      return this.state.semesterCode;
    }
    if (this.state.demoMode) {
      return '—（演示数据）';
    }
    return '—';
  }

  private firstMondayText(): string {
    const cfg = this.state.config;
    if (cfg === undefined) {
      return '—';
    }
    return formatDate(cfg.firstMonday);
  }

  /** 取 Push Token（白名单调试要先拿到它去 AGC 填） */
  private async loadPushToken(): Promise<void> {
    this.pushTokenHint = '获取中…';
    const r: PushTokenResult = await getPushToken();
    if (r.ok) {
      this.pushToken = r.token;
      this.pushTokenHint = '已获取，点「复制」后到 AGC 实况窗 → 白名单设备管理里添加';
    } else {
      this.pushToken = '';
      this.pushTokenHint = r.message;
    }
  }

  /**
   * 探测实况窗可用性。
   *
   * 用**深度探测**而不是只看 isLiveViewEnabled()：后者只能判断系统总开关，
   * 查不出华为是否下发了场景权益。深度探针会真的建一次极短实况窗，
   * 把 1003500005 这类「没权益」暴露成明确结论。
   */
  private async checkLiveView(): Promise<void> {
    this.liveViewHint = '检测中…';
    const probe: LiveViewProbe = await probeLiveViewDeep();
    this.liveViewState = probe.status;
    this.liveViewHint = probe.message;
  }

  /**
   * 开关变化时批量创建/结束实况窗。
   *
   * 只对「本周还有课的课程」建实况窗，避免一次性创建上百个把系统限流打满
   * （错误码 1003500008 就是每秒创建过多）。失败信息汇总成一句提示。
   */
  private async applyLiveView(on: boolean): Promise<void> {
    const courses: Course[] = this.state.currentWeekCourses;
    if (!on) {
      await stopAllCourseLiveViews(courses);
      this.liveViewState = '';
      this.liveViewHint = '已关闭提醒';
      return;
    }
    if (courses.length === 0) {
      // 没有课就不能开提醒：这里必须把开关复位，否则 Toggle 会被
      // 受控状态（isOn: liveViewOn）弹回，用户看到的就是"拨不过去"。
      this.suppressToggle = true;
      this.liveViewOn = false;
      this.liveViewState = '';
      this.liveViewHint = '本周课表为空，无法开启提醒：请先在上方点「同步」拉取课表，再回来打开';
      return;
    }
    this.liveViewHint = `正在为 ${courses.length} 门课创建实况窗…`;
    let failed: string = '';
    let okCount: number = 0;
    for (let i = 0; i < courses.length; i++) {
      const err: string | null = await startCourseLiveView(courses[i], this.leadMinutes);
      if (err !== null) {
        failed = err;
        break;  // 权限类错误没必要重复撞，直接停
      }
      okCount++;
      // 每次创建间隔 20ms，避免触发「每秒过多」限流
      await new Promise<void>((r) => setTimeout(() => {
        r();
      }, 20));
    }
    if (failed.length > 0) {
      this.suppressToggle = true;
      this.liveViewOn = false;
      this.liveViewState = LiveViewStatus.NO_RIGHT;
      this.liveViewHint = okCount > 0
        ? `已创建 ${okCount} 个后停止：${failed}`
        : `无法开启：${failed}`;
    } else {
      this.liveViewState = LiveViewStatus.READY;
      this.liveViewHint = `已为 ${okCount} 门课创建实况窗`;
    }
  }

  private copyQqGroup(): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, QQ_GROUP);
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.toast = 'QQ群号已复制';
    } catch (e) {
      this.toast = '复制失败';
    }
  }
}
