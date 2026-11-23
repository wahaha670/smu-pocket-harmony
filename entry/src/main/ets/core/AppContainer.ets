/**
 * 手写依赖容器。故意不引框架：整个 App 就两三个对象。
 *
 * 对齐 Android 版 App.kt 的 AppContainer。
 *
 * 关键点：`jwFactory()` 用**函数**而不是属性 ——
 * 写成属性会在 App 启动那一刻定死，扫码登录完之后还一直在用启动时选中的实现
 * （Android 版就是这么踩过坑的）。
 */
import common from '@ohos.app.ability.common';
import { CacheStore } from '../core/CacheStore';
import { JwTransport, SessionStore } from '../core/Net';
import { RealJw, JwService, JwConfig } from '../data/RealJw';
import { FakeJw } from '../data/FakeJw';
import { TermResolver, TermStore } from '../data/TermResolver';
import { AppDeps, AppViewModel } from '../core/AppViewModel';

export class AppContainer {
  readonly session: SessionStore;
  readonly cache: CacheStore;
  readonly termStore: TermStore;
  readonly filesDir: string;
  /** 应用上下文：装配 AppViewModel 与刷新卡片都要用 */
  private context: common.UIAbilityContext;
  private termResolver: TermResolver;
  private transport: JwTransport;

  private constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.filesDir = context.filesDir;
    this.session = new SessionStore(context);
    this.cache = new CacheStore(context);
    this.termStore = new TermStore(context);
    this.termResolver = new TermResolver(this.termStore);
    this.transport = new JwTransport(this.session, JwConfig.BASE_URL);
  }

  /**
   * 初始化容器（Preferences 是异步 API，必须先 await 一次）。
   */
  static async create(context: common.UIAbilityContext): Promise<AppContainer> {
    const container = new AppContainer(context);
    await container.session.init();
    await container.termStore.init();
    return container;
  }

  /**
   * 有会话就用真接口，没有就退回演示数据。
   *
   * 注意：必须是函数，写成属性会被缓存在启动那一刻。
   */
  jwService(): JwService {
    if (this.session.isLoggedIn()) {
      return new RealJw(this.transport, this.termResolver);
    }
    return new FakeJw();
  }

  /** 装配出可用的 ViewModel */
  buildViewModel(): AppViewModel {
    const deps = new AppDeps(
      this.session,
      this.cache,
      (): JwService => this.jwService(),
      // 传上下文：既用于取沙箱 files 目录写卡片数据，
      // 也用于 formProvider.reloadForms 刷新卡片
      this.context
    );
    return new AppViewModel(deps);
  }

  /** 退出登录时把学期代码也清掉（和 Android 版一致） */
  async clearAll(): Promise<void> {
    await this.session.clear();
    await this.termStore.clear();
    this.cache.clear();
  }
}
