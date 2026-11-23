/**
 * 登录页。
 *
 * 核心决定：不在 App 里 POST 账号密码，而是开学校自己的登录页让用户扫码。
 * 收益：极验滑块、密码前端加密、CAS 多跳全部免适配，我们只要结果（cookie）。
 *
 * 流程（与原版一致）：
 * 1. Web 组件打开教务首页（带扫码登录）
 * 2. 每 2 秒从 Web 组件的 CookieManager 捞一次 cookie 存进 SessionStore
 * 3. 顺带发一个轻量请求（`zc=1`）探一次会话是否有效
 * 4. 探通了 → 切到主页，Web 组件被销毁
 *
 * 鸿蒙 API 事实（已核对 @ohos.web.webview.d.ts）：
 * - `fetchCookieSync(url, incognito?): string` —— 读 cookie
 * - `saveCookieSync(): void` —— **把内存里的 cookie 落盘**
 * - `configCookieSync(url, value, ...)` —— **写/覆盖** cookie，
 *   ⚠️ 千万不要用它来"flush"：传空串会把该 URL 的 cookie **清空**，
 *   原版曾有这个误解，会导致刚登录就把会话抹掉。
 * - `putAcceptThirdPartyCookieEnabled(true)` —— CAS 跨域回调必须开
 *
 * 移植自 Android 版 ui/login/LoginScreen.kt + core/CookieHarvester.kt。
 */
import web_webview from '@ohos.web.webview';
import { Theme } from '../../theme/Theme';
import { AppState } from '../../core/AppViewModel';
import { JwConfig } from '../../data/RealJw';
import { hostOf, sleep } from '../../core/Net';
import { FontSize } from '../../theme/Typography';

/** 轮询间隔 */
const POLL_INTERVAL_MS: number = 2000;
/** 最多轮询次数：45 × 2s = 90 秒 */
const MAX_POLLS: number = 45;
/** 30 秒后提示一下 */
const HINT_AFTER_POLLS: number = 15;

@Component
export struct LoginScreen {
  @ObjectLink state: AppState;
  @Prop isDark: boolean = false;

  /** 是否已经打开 Web 登录页 */
  @State showWeb: boolean = false;
  /** 提示文案 */
  @State hint: string = '扫码完成后会自动进入，无需手动操作';
  /** 是否已完成 */
  @State done: boolean = false;

  private webviewController: web_webview.WebviewController = new web_webview.WebviewController();
  /** 轮询循环是否还在跑 */
  private polling: boolean = false;
  /** 当前页面 URL（由 onPageBegin 更新） */
  private currentUrl: string = JwConfig.LOGIN_URL;

  /** 由父组件注入的动作 */
  onDemo: () => void = () => {};
  onCookieHarvested: (host: string, cookieHeader: string) => void = () => {};
  verifySession: () => Promise<boolean> = async () => false;
  onLoginCancelled: () => void = () => {};
  /**
   * 是否「一进来就自动打开扫码登录」——用回调而非布尔值。
   *
   * 为什么用回调：组件挂载由 aboutToAppear 触发，
   * 在这里调一次即可精确消费「重新登录后待自动扫码」的标记；
   * 若传布尔值，父组件 build() 的反复重渲染会让它时有时无。
   */
  consumeAutoStart: () => boolean = () => false;

  aboutToAppear(): void {
    // CAS / 统一身份认证跨域回调时，第三方 cookie 必须开，否则拿不到凭证
    try {
      if (!web_webview.WebCookieManager.isThirdPartyCookieAllowed()) {
        web_webview.WebCookieManager.putAcceptThirdPartyCookieEnabled(true);
      }
      if (!web_webview.WebCookieManager.isCookieAllowed()) {
        web_webview.WebCookieManager.putAcceptCookieEnabled(true);
      }
    } catch (e) {
      // 忽略：不让开关失败阻断登录
    }

    // 「重新登录以同步」场景：自动打开扫码，省掉用户第二次点击
    if (this.consumeAutoStart()) {
      this.showWeb = true;
      this.startPolling();
    }
  }

  aboutToDisappear(): void {
    // 页面销毁时停掉轮询，避免定时器泄漏
    this.polling = false;
  }

  build() {
    Column() {
      if (this.showWeb) {
        this.LoginWeb()
      } else {
        this.LoginIntro()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.colors(this.isDark).background)
  }

  // ---- 引导页 ----
  @Builder
  LoginIntro() {
    Column() {
      Text('南医大口袋')
        .fontSize(FontSize.displayLarge)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.colors(this.isDark).onSurface)
      Text('非官方客户端 · 课表 / 成绩')
        .fontSize(FontSize.small)
        .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        .margin({ top: 4 })

      Text('登录在学校自己的页面里完成，App 不接触密码、不保存密码。')
        .fontSize(FontSize.bodyStrong)
        .fontColor(Theme.colors(this.isDark).onSurface)
        .margin({ top: 24 })
      Text('点下面的按钮打开教务首页，用手机扫码登录；登录成功后会自动跳回来，不需要手动关闭。')
        .fontSize(FontSize.smallBody)
        .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        .margin({ top: 6 })

      Button('打开教务系统登录（扫码）')
        .width('100%')
        .fontSize(FontSize.bodyStrong)
        .backgroundColor(Theme.colors(this.isDark).primary)
        .margin({ top: 24 })
        .onClick(() => {
          this.showWeb = true;
          this.startPolling();
        })

      Button('先用演示数据看看')
        .width('100%')
        .fontSize(FontSize.bodyStrong)
        .fontColor(Theme.colors(this.isDark).primary)
        .backgroundColor(Color.Transparent)
        .margin({ top: 8 })
        .onClick(() => {
          this.onDemo();
        })

      if (this.state.loading) {
        Text('正在加载…')
          .fontSize(FontSize.small)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .margin({ top: 16 })
      }

      if (this.state.error.length > 0) {
        Text(this.state.error)
          .fontSize(FontSize.smallBody)
          .fontColor(Theme.colors(this.isDark).error)
          .margin({ top: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Start)
  }

  // ---- Web 登录 ----
  @Builder
  LoginWeb() {
    Column() {
      // 顶部提示条
      Row() {
        Column() {
          Text('教务系统登录')
            .fontSize(FontSize.subtitle)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.colors(this.isDark).onSurface)
          Text(this.hint)
            .fontSize(FontSize.caption)
            .fontColor(this.done
              ? Theme.colors(this.isDark).primary
              : Theme.colors(this.isDark).onSurfaceVariant)
            .margin({ top: 2 })
            .maxLines(2)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('关闭')
          .fontSize(FontSize.body)
          .fontColor(Theme.colors(this.isDark).primary)
          .padding(8)
          .onClick(() => {
            this.polling = false;
            this.onLoginCancelled();
            this.showWeb = false;
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      // Web 组件：开启 JS / DOM 存储 / 第三方 cookie
      Web({ src: JwConfig.LOGIN_URL, controller: this.webviewController })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .databaseAccess(true)
        .imageAccess(true)
        .mixedMode(MixedMode.Compatible)
        .onPageBegin((event) => {
          // 页面开始加载时更新当前 URL
          this.currentUrl = event.url;
        })
        .onPageEnd((event) => {
          this.currentUrl = event.url;
        })
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 开始轮询捞 cookie + 探测会话。
   *
   * 为什么不用 onPageEnd 一次性判断：
   * 扫码是页面内异步完成的，主文档 URL 可能根本不变，
   * 所以只能定时捞 cookie 并真打一次接口。
   */
  private startPolling(): void {
    if (this.polling) {
      return;
    }
    this.polling = true;
    this.pollLoop();
  }

  private async pollLoop(): Promise<void> {
    let polls = 0;
    while (this.polling && polls < MAX_POLLS) {
      await sleep(POLL_INTERVAL_MS);
      if (!this.polling) {
        return;
      }
      polls++;

      // 同时捞当前页和登录页：CAS 场景下凭证可能落在另一个 host 上
      const harvested = this.harvest([this.currentUrl, JwConfig.LOGIN_URL]);
      if (harvested.size === 0) {
        if (polls === HINT_AFTER_POLLS) {
          this.hint = '还没拿到 cookie，确认页面是否加载完了';
        }
        continue;
      }

      let any = false;
      harvested.forEach((header: string, host: string) => {
        any = true;
        this.onCookieHarvested(host, header);
      });
      if (!any) {
        continue;
      }

      let ok = false;
      try {
        ok = await this.verifySession();
      } catch (e) {
        ok = false;
      }

      if (ok) {
        this.hint = '登录成功，正在加载课表…';
        this.done = true;
        this.polling = false;
        this.showWeb = false;
        return;
      }

      if (polls === HINT_AFTER_POLLS) {
        this.hint = '还没检测到登录成功，请确认已经完成扫码';
      }
    }

    if (this.polling) {
      this.hint = '等了 90 秒仍未登录成功，可以点「关闭」重试';
      this.polling = false;
    }
  }

  /**
   * 从 Web 组件的 cookie 管理器里捞 cookie，返回 host → "a=1; b=2"。
   *
   * 关键点（原版踩过的坑）：
   * 1. 不能用 JS 读 cookie：会话 cookie 基本是 HttpOnly，document.cookie 看不见；
   * 2. cookie 按 URL 记，CAS 和教务各有一份，必须按 host 分别存；
   * 3. 捞之前要落盘：saveCookieSync() 把内存里的 cookie 刷到磁盘，
   *    否则刚 Set-Cookie 完立刻读可能拿到旧值。
   *    ⚠️ 不能用 configCookieSync(url, '') 来"flush" —— 那是清空 cookie。
   */
  private harvest(urls: string[]): Map<string, string> {
    const byHost = new Map<string, string>();
    if (urls.length === 0) {
      return byHost;
    }

    const manager = web_webview.WebCookieManager;
    // 只做"落盘"，不写入任何值
    try {
      manager.saveCookieSync();
    } catch (e) {
      // 忽略：落盘失败不影响读取内存中的值
    }

    for (const url of urls) {
      if (url.length === 0) {
        continue;
      }
      const isHttp = url.startsWith('http://') || url.startsWith('https://');
      if (!isHttp) {
        continue;
      }
      const host = hostOf(url);
      if (host === undefined) {
        continue;
      }
      let header = '';
      try {
        header = manager.fetchCookieSync(url);
      } catch (e) {
        header = '';
      }
      if (header === undefined || header === null || header.length === 0) {
        continue;
      }
      const old = byHost.get(host);
      if (old === undefined || header.length > old.length) {
        // 同一 host 被多次命中时取更完整的那一份
        byHost.set(host, header);
      }
    }
    return byHost;
  }
}
