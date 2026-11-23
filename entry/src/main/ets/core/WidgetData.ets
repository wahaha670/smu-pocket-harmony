/**
 * 桌面卡片（服务卡片）的数据契约。
 *
 * ## 数据怎么流到卡片上
 *
 * 卡片运行在独立的 FormExtensionAbility 里，**不适合自己联网**
 * （系统对卡片有严格的能力与耗时限制）。所以采用「应用写、卡片读」：
 *
 * ```
 * App 同步到课表 → 写 widget_data.json → 卡片读取并渲染
 *                              ↑
 *                    卡片定时/被拉起时读
 * ```
 *
 * 两边都通过本文件读写，保证格式一致。
 *
 * ## 为什么用文件而不是只靠 formProvider.updateForm
 *
 * `updateForm` 只在应用运行时能推数据；而卡片第一次被加到桌面
 * （`onAddForm`）时应用可能根本没启动。那时卡片必须能自己拿到数据，
 * 所以落一份文件是必须的。
 */
import fs from '@ohos.file.fs';

/** 卡片上的一门课（只保留渲染需要的字段，尽量小） */
export interface WidgetCourse {
  /** 课程名 */
  name: string;
  /** 时间，如 "08:00" 或 "08:00-10:30" */
  time: string;
  /** 地点（取不到时为空串） */
  room: string;
  /** 色块颜色（与课表页用同一套配色） */
  color: string;
  /** 授课老师（教务把多个老师拼在一个字段里，这里原样带过来，由展示层截断） */
  teacher: string;
  /** 上课内容 `sknrjj`（只有按周查询才有，取不到时为空串） */
  content: string;
}

/** 卡片所需的数据 */
export interface WidgetSnapshot {
  /** 顶部左侧："第 11 周"（写入时的值，跨天后卡片会按当前日期重算） */
  weekText: string;
  /** 顶部右侧："周五"（同上） */
  dayText: string;
  /** 今天的课程（写入时的「今天」，**跨天后会被卡片按日期重算覆盖**） */
  today: WidgetCourse[];
  /** 明天的课程（同上） */
  tomorrow: WidgetCourse[];
  /** 明天的小标题："明天 · 11/14 周六" */
  tomorrowLabel: string;
  /** 写入时刻（毫秒）—— 卡片据此判断数据是否跨天，决定要不要本地重算 */
  updatedAt: number;

  // ---- 以下为「跨天自动重算」所需的完整数据 ----
  //
  // 卡片是「应用写、卡片读」，如果只存「今天/明天」两个切片，
  // 那么过零点后卡片会一直显示昨天的课（实测 bug）。
  // 所以额外带上整周课表 + 学期起始日 + 总周数，
  // 让卡片能自己按**当前真实日期**算出该显示哪一天的课。

  /** 学期第 1 周周一（毫秒时间戳，当天 00:00） */
  firstMonday?: number;
  /** 总周数 */
  totalWeeks?: number;
  /**
   * 当前这一周的课表（按星期 1-7 分组）。
   *
   * ⚠️ **只在 `termDays` 缺失时作为兜底**。
   * 单独存一周会导致「跨到下一周后仍显示上一周的课」
   * （实测缺陷：标题变第 13 周、内容还是第 12 周的）。
   * 正确做法是用下面的 `termDays`（整学期）。
   */
  weekDays?: WidgetDay[];
  /**
   * **整学期**课表：每一周每一天的课。
   *
   * 卡片据此可以连续跨任意多天/多周，不需要应用中途再写一次。
   * 实测 20 周 × 7 天的完整数据约 30–60 KB，对卡片完全可接受。
   */
  termDays?: WidgetTermDay[];
}

/** 一周中某一天的全部课程 */
export interface WidgetDay {
  /** 1 = 周一 … 7 = 周日 */
  dayOfWeek: number;
  courses: WidgetCourse[];
}

/** 整学期中的某一天 */
export interface WidgetTermDay {
  /** 第几周（1 起） */
  week: number;
  /** 1 = 周一 … 7 = 周日 */
  dayOfWeek: number;
  courses: WidgetCourse[];
}

/** 没有数据时的空快照 */
export function emptySnapshot(): WidgetSnapshot {
  return {
    weekText: '',
    dayText: '',
    today: [],
    tomorrow: [],
    tomorrowLabel: '明天',
    updatedAt: 0,
    firstMonday: 0,
    totalWeeks: 0,
    weekDays: [],
    termDays: []
  };
}

// ---------------------------------------------------------------------------
// 磁盘读写
// ---------------------------------------------------------------------------

const WIDGET_FILE: string = 'widget_data.json';

/** 卡片数据文件的完整路径 */
export function widgetFilePath(filesDir: string): string {
  return `${filesDir}/${WIDGET_FILE}`;
}

/** 写入卡片数据（App 侧调用） */
export function saveWidgetSnapshot(filesDir: string, snapshot: WidgetSnapshot): void {
  try {
    const text = JSON.stringify(snapshot);
    const path = widgetFilePath(filesDir);
    const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, text);
    } finally {
      fs.closeSync(file);
    }
  } catch (e) {
    // 卡片是附加功能，写失败不能影响主流程
  }
}

/** 读取卡片数据（卡片侧调用）；文件不存在或损坏时返回 undefined */
export function loadWidgetSnapshot(filesDir: string): WidgetSnapshot | undefined {
  try {
    const path = widgetFilePath(filesDir);
    if (!fs.accessSync(path)) {
      return undefined;
    }
    const text = fs.readTextSync(path);
    return parseSnapshot(text);
  } catch (e) {
    return undefined;
  }
}

// ---------------------------------------------------------------------------
// 解析 / 序列化
// ---------------------------------------------------------------------------

/**
 * 安全解析卡片数据。
 *
 * 与教务 JSON 的解析思路一致：**任何字段缺失或类型不对都不能抛异常**，
 * 卡片白屏比显示空数据更糟。
 */
export function parseSnapshot(text: string): WidgetSnapshot | undefined {
  let root: Record<string, Object> | undefined;
  try {
    const v: Object = JSON.parse(text) as Object;
    if (v === null || v === undefined || typeof v !== 'object' || Array.isArray(v)) {
      return undefined;
    }
    root = v as Record<string, Object>;
  } catch (e) {
    return undefined;
  }

  const s = emptySnapshot();
  s.weekText = asString(root['weekText']);
  s.dayText = asString(root['dayText']);
  s.tomorrowLabel = asString(root['tomorrowLabel']);
  if (s.tomorrowLabel.length === 0) {
    s.tomorrowLabel = '明天';
  }
  s.updatedAt = asNumber(root['updatedAt']);
  s.today = parseCourses(root['today']);
  s.tomorrow = parseCourses(root['tomorrow']);
  // 跨天重算所需字段（老版本数据没有这些，缺了就退回快照原值）
  s.firstMonday = asNumber(root['firstMonday']);
  s.totalWeeks = asNumber(root['totalWeeks']);
  s.weekDays = parseWeekDays(root['weekDays']);
  s.termDays = parseTermDays(root['termDays']);
  return s;
}

/** 解析「整学期每一天的课表」 */
function parseTermDays(v: Object | undefined): WidgetTermDay[] {
  const out: WidgetTermDay[] = [];
  if (v === undefined || v === null || !Array.isArray(v)) {
    return out;
  }
  for (const item of v as Object[]) {
    if (item === null || item === undefined || typeof item !== 'object') {
      continue;
    }
    const o = item as Record<string, Object>;
    const week: number = asNumber(o['week']);
    const dow: number = asNumber(o['dayOfWeek']);
    if (week < 1 || dow < 1 || dow > 7) {
      continue;
    }
    out.push({ week: week, dayOfWeek: dow, courses: parseCourses(o['courses']) });
  }
  return out;
}

/** 解析「按星期分组的整周课表」 */
function parseWeekDays(v: Object | undefined): WidgetDay[] {
  const out: WidgetDay[] = [];
  if (v === undefined || v === null || !Array.isArray(v)) {
    return out;
  }
  for (const item of v as Object[]) {
    if (item === null || item === undefined || typeof item !== 'object') {
      continue;
    }
    const o = item as Record<string, Object>;
    const dow: number = asNumber(o['dayOfWeek']);
    if (dow < 1 || dow > 7) {
      continue;
    }
    out.push({ dayOfWeek: dow, courses: parseCourses(o['courses']) });
  }
  return out;
}

function parseCourses(v: Object | undefined): WidgetCourse[] {
  const out: WidgetCourse[] = [];
  if (v === undefined || v === null || !Array.isArray(v)) {
    return out;
  }
  for (const item of v as Object[]) {
    if (item === null || item === undefined || typeof item !== 'object') {
      continue;
    }
    const o = item as Record<string, Object>;
    const c: WidgetCourse = {
      name: asString(o['name']),
      time: asString(o['time']),
      room: asString(o['room']),
      color: asString(o['color']),
      teacher: asString(o['teacher']),
      content: asString(o['content'])
    };
    if (c.name.length > 0) {
      out.push(c);
    }
  }
  return out;
}

function asString(v: Object | undefined): string {
  if (v === undefined || v === null) {
    return '';
  }
  if (typeof v === 'string') {
    return v as string;
  }
  if (typeof v === 'number' || typeof v === 'boolean') {
    return `${v}`;
  }
  return '';
}

function asNumber(v: Object | undefined): number {
  if (v === undefined || v === null) {
    return 0;
  }
  if (typeof v === 'number') {
    return v as number;
  }
  const n = Number.parseFloat(asString(v));
  return Number.isNaN(n) ? 0 : n;
}

// ---------------------------------------------------------------------------
// 表单绑定数据
// ---------------------------------------------------------------------------

/**
 * 转成卡片的绑定数据。
 *
 * ⚠️ 表单绑定数据只支持**基本类型**（string/number/boolean）与其数组，
 * 不能直接传对象或 Map，所以课程列表序列化成 JSON 字符串传过去。
 */
export interface WidgetBinding {
  weekText: string;
  dayText: string;
  tomorrowLabel: string;
  todayJson: string;
  tomorrowJson: string;
  todayCount: number;
  tomorrowCount: number;
}

export function toBinding(s: WidgetSnapshot): WidgetBinding {
  const b: WidgetBinding = {
    weekText: s.weekText,
    dayText: s.dayText,
    tomorrowLabel: s.tomorrowLabel,
    todayJson: JSON.stringify(s.today),
    tomorrowJson: JSON.stringify(s.tomorrow),
    todayCount: s.today.length,
    tomorrowCount: s.tomorrow.length
  };
  return b;
}
