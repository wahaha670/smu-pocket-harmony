/**
 * 解析「当前学期代码」。
 *
 * ## 结论：这个教务系统拿不到「当前学期」
 *
 * 实测过的所有途径：
 *
 * | 途径 | 结果 |
 * |---|---|
 * | `POST /new/student/xsgrkb/getXnxqList` 等 6 个 JSON 接口 | 全部 404 |
 * | `GET /new/student/xskccj/kccjList.page` | 返回 HTML，下拉里确实有学期列表 |
 *
 * 但那个下拉是**全量列表**（202001 ~ 203402，最新在前），
 * **没有任何 `selected` 标记** —— 当前学期是 JS 运行时选的，静态 HTML 里看不出来。
 *
 * 早期实现「取最大六位数」直接把 203402 当成了当前学期，
 * 导致所有请求用错 `xnxqdm`、**全部返回空数据**。这条路走不通。
 *
 * ## 所以用日期推算
 *
 * 学年 9 月开学、2 月开学，边界固定，推算结果与教务一致，
 * 而且**不依赖网络、不会因为页面改版而失效**。
 *
 * 移植自 Android 版 data/TermResolver.kt + core/TermStore.kt。
 */
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import { TermCode } from '../core/TermCode';

export enum TermSource {
  CACHE = 'CACHE',
  DATE = 'DATE',
  FALLBACK = 'FALLBACK'
}

export interface ResolvedTerm {
  code: string;
  source: TermSource;
}

/**
 * 当前学期代码的本地存储。
 *
 * 单独一个 Preferences 文件（`smu_term`），不跟 cookie 混在一起：
 * cookie 是账号凭证，学期代码不是，两者的生命周期也不同
 * （学期一个学期换一次，cookie 可能几小时就过期）。
 */
export class TermStore {
  private static readonly PREF_NAME: string = 'smu_term';
  // v2：旧版曾把 203402 写进来，换 key 直接作废
  private static readonly KEY_CODE: string = 'term_code_v2';
  private static readonly KEY_SOURCE: string = 'term_source';
  private static readonly KEY_SAVED_AT: string = 'term_saved_at';

  private prefs: preferences.Preferences | undefined;
  private ready: boolean = false;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async init(): Promise<void> {
    if (this.ready) {
      return;
    }
    this.prefs = await preferences.getPreferences(this.context, TermStore.PREF_NAME);
    this.ready = true;
  }

  /** 只认「像学期」的代码，坏值当作没有（否则一次抓错会永久污染缓存） */
  load(): string | undefined {
    if (this.prefs === undefined) {
      return undefined;
    }
    const code = this.prefs.getSync(TermStore.KEY_CODE, '') as string;
    if (code.length === 0) {
      return undefined;
    }
    return TermCode.isPlausible(code) ? code : undefined;
  }

  save(code: string, source: string): void {
    if (this.prefs === undefined) {
      return;
    }
    this.prefs.putSync(TermStore.KEY_CODE, code);
    this.prefs.putSync(TermStore.KEY_SOURCE, source);
    this.prefs.putSync(TermStore.KEY_SAVED_AT, `${Date.now()}`);
    this.prefs.flush();
  }

  /** 最近一次学期代码是从哪来的：cache / date / fallback */
  source(): string {
    if (this.prefs === undefined) {
      return '';
    }
    return this.prefs.getSync(TermStore.KEY_SOURCE, '') as string;
  }

  async clear(): Promise<void> {
    if (this.prefs !== undefined) {
      await this.prefs.clear();
      await this.prefs.flush();
    }
  }
}

export class TermResolver {
  private store: TermStore;

  constructor(store: TermStore) {
    this.store = store;
  }

  async resolve(): Promise<ResolvedTerm> {
    const cached = this.store.load();
    if (cached !== undefined) {
      return { code: cached, source: TermSource.CACHE };
    }

    const byDate = TermCode.fromDate();
    if (TermCode.isPlausible(byDate)) {
      this.store.save(byDate, 'date');
      return { code: byDate, source: TermSource.DATE };
    }

    return { code: TermCode.FALLBACK, source: TermSource.FALLBACK };
  }

  /** 不联网的「当前学期」，探针用 */
  peek(): string {
    const cached = this.store.load();
    if (cached !== undefined) {
      return cached;
    }
    return TermCode.fromDate();
  }
}
