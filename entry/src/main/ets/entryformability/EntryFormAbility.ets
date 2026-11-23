/**
 * 桌面卡片的提供方（FormExtensionAbility）。
 *
 * ## 职责
 *
 * 系统在「用户把卡片加到桌面」或「卡片定时刷新」时会拉起本扩展，
 * 我们负责把数据交给卡片：
 * 1. 从沙箱读 `widget_data.json`（由主应用写入）；
 * 2. 转成表单绑定数据返回，卡片 UI 通过 `@LocalStorageProp` 取用。
 *
 * ## 为什么不在卡片里联网
 *
 * 卡片对**网络请求、执行时长、内存**都有严格限制，
 * 在卡片里直接打教务接口既慢又容易被系统杀。
 * 所以数据统一由主应用准备好写入文件，卡片只做展示。
 *
 * ## 生命周期要点
 *
 * - `onAddForm`：卡片被加到桌面时调用，**必须同步返回**数据；
 * - `onUpdateForm`：卡片定时/被要求刷新时调用，用 `formProvider.updateForm` 推数据；
 * - `onRemoveForm`：卡片被移除，无需处理；
 * - 本扩展与主应用**不在同一进程**，但共享同一个应用沙箱目录。
 *
 * ## ⚠️ 卡片尺寸为什么要落盘（踩过的坑）
 *
 * 卡片有 2*2 / 2*4 / 4*4 三种规格，需要按规格切换布局。
 *
 * **`onAddForm` 的 want 里有尺寸参数，但 `onUpdateForm` 没有。**
 * 最初的实现把尺寸存在内存 `Map<formId, boolean>` 里，结果：
 * **FormExtensionAbility 进程一重启 Map 就清空** →
 * 下次定时刷新时查不到尺寸、退回默认布局 →
 * 2*2 卡片在桌面上会自己「变回」双栏，课名被压成一个字。
 *
 * 所以现在把尺寸**持久化到文件** `form_sizes.json`：
 * - `onAddForm`：算出尺寸 → 写盘 → 返回数据；
 * - `onUpdateForm`：从盘上读回尺寸 → 保证刷新后布局不变。
 *
 * 实测数据（HarmonyOS 7.0.0.111 / API 26）：
 * | 卡片 | form_width | form_height | 宽高比 |
 * |------|-----------|-------------|--------|
 * | 2*2  | 1099      | 1099        | 1.00   |
 * | 2*4  | 1099      | 482         | 2.28   |
 */
import FormExtensionAbility from '@ohos.app.form.FormExtensionAbility';
import formBindingData from '@ohos.app.form.formBindingData';
import formProvider from '@ohos.app.form.formProvider';
import Want from '@ohos.app.ability.Want';
import hilog from '@ohos.hilog';
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { loadWidgetSnapshot, toBinding, emptySnapshot, WidgetSnapshot } from '../core/WidgetData';
import { recomputeForToday, DayFallback } from '../core/WidgetDate';

const TAG: string = 'SmuPocketForm';
const DOMAIN: number = 0x0001;

/** 卡片名称，必须与 form_config.json 里的 name 一致 */
const FORM_NAME: string = 'TodayTomorrowCard';

/** 尺寸缓存文件名（放在 filesDir 下，与 widget_data.json 同级） */
const SIZE_FILE: string = 'form_sizes.json';

/** form_dimension 参数键 */
const KEY_DIMENSION: string = 'ohos.extra.param.key.form_dimension';
/** form_width 参数键 */
const KEY_WIDTH: string = 'ohos.extra.param.key.form_width';
/** form_height 参数键 */
const KEY_HEIGHT: string = 'ohos.extra.param.key.form_height';
/** form_identity 参数键（formId） */
const KEY_IDENTITY: string = 'ohos.extra.param.key.form_identity';

export default class EntryFormAbility extends FormExtensionAbility {
  /**
   * 卡片被添加到桌面时调用。
   *
   * ⚠️ 必须**同步返回**绑定数据，不能在这里 await 异步任务，
   * 否则系统会认为卡片创建失败。
   */
  onAddForm(want: Want): formBindingData.FormBindingData {
    const compact: boolean = this.isCompactDimension(want);
    const formId: string = this.formIdOf(want);

    // 把尺寸落盘：onUpdateForm 拿不到尺寸参数，只能靠这里存下来
    if (formId.length > 0) {
      this.saveSize(formId, compact);
    }

    const data: Record<string, string | number | boolean> = this.loadBinding(compact);
    hilog.info(DOMAIN, TAG,
      'onAddForm formId=%{public}s compact=%{public}s today=%{public}d',
      formId, compact ? 'true' : 'false', data['todayCount'] as number);
    return formBindingData.createFormBindingData(data);
  }

  /**
   * 卡片定时刷新 / 被要求刷新时调用。
   *
   * 尺寸从落盘文件读回 —— 不能依赖内存，进程可能已重启。
   */
  onUpdateForm(formId: string, wantParams?: Record<string, Object>): void {
    const compact: boolean = this.loadSize(formId);
    const data: Record<string, string | number | boolean> = this.loadBinding(compact);
    const binding = formBindingData.createFormBindingData(data);
    formProvider.updateForm(formId, binding)
      .then(() => {
        hilog.info(DOMAIN, TAG,
          'updateForm ok formId=%{public}s compact=%{public}s today=%{public}d',
          formId, compact ? 'true' : 'false', data['todayCount'] as number);
      })
      .catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'updateForm failed: %{public}s', e.message);
      });
  }

  /** 卡片被移除：顺手清掉它的尺寸记录，避免文件无限增长 */
  onRemoveForm(formId: string): void {
    this.forgetSize(formId);
    hilog.info(DOMAIN, TAG, 'onRemoveForm formId=%{public}s', formId);
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, 'onFormEvent: %{public}s', message);
  }

  // ==================== 尺寸判定 ====================

  /**
   * 判断是否为 2*2 紧凑卡片。
   *
   * ⚠️ **只信宽高比，不信 form_dimension**。
   *
   * 实测（HarmonyOS 7.0.0.111 / API 26）：
   * | 卡片 | form_width | form_height | 宽高比 | form_dimension |
   * |------|-----------|-------------|--------|----------------|
   * | 2*2  | 1099      | 1099        | 1.00   | 2              |
   * | 2*4  | 1099      | 482         | 2.28   | **2（相同！）**|
   *
   * 2*4 长条上报的 dimension 也是 2，与 2*2 完全一样。
   * 只用 dimension 判断会让 2*2 渲染成双栏、课名被压成一个字。
   */
  private isCompactDimension(want: Want): boolean {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined || params === null) {
      return false;
    }
    const w: number = this.numOf(params[KEY_WIDTH]);
    const h: number = this.numOf(params[KEY_HEIGHT]);
    if (w > 0 && h > 0) {
      // 2*2 ≈ 1.00，2*4 ≈ 2.28，取 1.5 分界，两组相距极远
      return (w / h) < 1.5;
    }
    // 拿不到宽高时才退回 dimension（不可靠，只是兜底）
    return this.numOf(params[KEY_DIMENSION]) === 2;
  }

  /** 从 want 取 formId */
  private formIdOf(want: Want): string {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined || params === null) {
      return '';
    }
    const raw: Object | undefined = params[KEY_IDENTITY];
    if (raw === undefined || raw === null) {
      return '';
    }
    return String(raw);
  }

  private numOf(v: Object | undefined): number {
    if (v === undefined || v === null) {
      return 0;
    }
    const n: number = Number(v);
    return isNaN(n) ? 0 : n;
  }

  // ==================== 尺寸持久化 ====================

  private sizePath(): string {
    return `${this.context.filesDir}/${SIZE_FILE}`;
  }

  /** 读取全部尺寸记录：`{ "1300435157": true, ... }` */
  private readSizes(): Record<string, boolean> {
    const out: Record<string, boolean> = {};
    try {
      const p: string = this.sizePath();
      if (!fs.accessSync(p)) {
        return out;
      }
      const stat = fs.statSync(p);
      const buf = new ArrayBuffer(stat.size);
      const file = fs.openSync(p, fs.OpenMode.READ_ONLY);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      const text: string = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buf));
      if (text.length === 0) {
        return out;
      }
      const parsed = JSON.parse(text) as Record<string, Object>;
      for (const k of Object.keys(parsed)) {
        out[k] = parsed[k] === true;
      }
    } catch (e) {
      // 读不出来就当没有：退化为标准布局，不影响卡片显示
      hilog.warn(DOMAIN, TAG, 'readSizes failed, fallback to empty');
    }
    return out;
  }

  private writeSizes(sizes: Record<string, boolean>): void {
    try {
      const p: string = this.sizePath();
      const text: string = JSON.stringify(sizes);
      const file = fs.openSync(p, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, text);
      fs.closeSync(file);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'writeSizes failed');
    }
  }

  private saveSize(formId: string, compact: boolean): void {
    const sizes: Record<string, boolean> = this.readSizes();
    sizes[formId] = compact;
    this.writeSizes(sizes);
  }

  private loadSize(formId: string): boolean {
    const sizes: Record<string, boolean> = this.readSizes();
    return sizes[formId] === true;
  }

  private forgetSize(formId: string): void {
    const sizes: Record<string, boolean> = this.readSizes();
    // ⚠️ ArkTS 不支持 delete 运算符（arkts-no-delete），
    // 所以重建一个新对象再写回。
    const next: Record<string, boolean> = {};
    for (const k of Object.keys(sizes)) {
      if (k !== formId) {
        next[k] = sizes[k];
      }
    }
    this.writeSizes(next);
  }

  // ==================== 数据绑定 ====================

  /**
   * 读取快照，并**按当前真实日期重算**今天/明天的课。
   *
   * ⚠️ 为什么必须重算（真机 bug）：
   * 快照里的 `today` / `tomorrow` 是**应用写入那一刻**算的。
   * 过了零点，那份「今天」已经是昨天了 ——
   * 卡片会一直显示昨天的课，直到应用下次运行并重写文件。
   * 实测就是这样：第二天看桌面，卡片还停在昨天的课程。
   *
   * 现在快照里额外带 `weekDays`（整周课表）+ `firstMonday` + `totalWeeks`，
   * 卡片用 `recomputeForToday()` 按当前日期重算，即使几天没开应用也能自动跳到正确日期。
   *
   * 老版本写入的数据没有这些字段 → 自动退回快照原值，不会白屏。
   */
  private refreshedSnapshot(): WidgetSnapshot {
    const dir: string = this.context.filesDir;
    const snap = loadWidgetSnapshot(dir);
    if (snap === undefined) {
      return emptySnapshot();
    }

    // ArkTS 要求对象字面量必须有显式类型，所以先构造再传
    const fb: DayFallback = {
      weekText: snap.weekText,
      dayText: snap.dayText,
      today: snap.today,
      tomorrow: snap.tomorrow,
      tomorrowLabel: snap.tomorrowLabel
    };

    const rec = recomputeForToday(
      Date.now(),
      snap.firstMonday !== undefined ? snap.firstMonday : 0,
      snap.totalWeeks !== undefined ? snap.totalWeeks : 0,
      snap.termDays !== undefined ? snap.termDays : [],
      snap.weekDays !== undefined ? snap.weekDays : [],
      fb
    );

    // 重算结果覆盖到快照副本上（保留 firstMonday 等元信息）
    const out = emptySnapshot();
    out.weekText = rec.weekText.length > 0 ? rec.weekText : snap.weekText;
    out.dayText = rec.dayText;
    out.today = rec.today;
    out.tomorrow = rec.tomorrow;
    out.tomorrowLabel = rec.tomorrowLabel;
    out.updatedAt = snap.updatedAt;
    out.firstMonday = snap.firstMonday;
    out.totalWeeks = snap.totalWeeks;
    out.weekDays = snap.weekDays;
    // ⚠️ termDays 必须一并拷回，否则这个「重算后的快照」是不完整的。
    //    当前调用方（loadBinding → toBinding）虽然只读 today/tomorrow 等字段，
    //    但保留完整数据能避免将来被复用时出现「跨天还能用、跨周就退化成空」的怪问题。
    out.termDays = snap.termDays;

    if (rec.outOfRange) {
      hilog.info(DOMAIN, TAG, 'date out of range, showing empty day');
    }
    return out;
  }

  /**
   * 组装卡片绑定数据。
   *
   * @param compact 是否为 2*2 紧凑布局
   */
  private loadBinding(compact: boolean): Record<string, string | number | boolean> {
    const out: Record<string, string | number | boolean> = {};
    try {
      const effective = this.refreshedSnapshot();
      const b = toBinding(effective);
      out['weekText'] = b.weekText.length > 0 ? b.weekText : '南医大口袋';
      out['dayText'] = b.dayText;
      out['tomorrowLabel'] = b.tomorrowLabel;
      out['todayJson'] = b.todayJson;
      out['tomorrowJson'] = b.tomorrowJson;
      out['todayCount'] = b.todayCount;
      out['tomorrowCount'] = b.tomorrowCount;
      out['compact'] = compact ? 1 : 0;
      hilog.info(DOMAIN, TAG,
        'loadBinding week=%{public}s day=%{public}s today=%{public}d tomorrow=%{public}d',
        b.weekText, b.dayText, b.todayCount, b.tomorrowCount);
      return out;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'loadBinding failed');
      out['weekText'] = '南医大口袋';
      out['dayText'] = '';
      out['tomorrowLabel'] = '明天';
      out['todayJson'] = '[]';
      out['tomorrowJson'] = '[]';
      out['todayCount'] = 0;
      out['tomorrowCount'] = 0;
      out['compact'] = compact ? 1 : 0;
      return out;
    }
  }
}
