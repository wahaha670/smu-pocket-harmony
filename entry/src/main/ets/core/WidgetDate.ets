/**
 * 卡片「按当前真实日期重算今天/明天」的纯函数。
 *
 * ## 解决什么问题
 *
 * 桌面卡片是「应用写、卡片读」：应用在某个时刻把「今天/明天」两天的课
 * 写进 widget_data.json，卡片只负责渲染。
 *
 * 但**过了零点**，那份快照里的「今天」已经是昨天了 ——
 * 卡片会一直显示昨天的课，直到应用下次运行并重写文件。
 * 实测就是这样：第二天打开桌面，卡片还是昨天的内容。
 *
 * ## 怎么解决
 *
 * 应用写入时**额外带上整周课表**（`weekDays`）+ 学期起始日 + 总周数。
 * 卡片每次刷新时用本文件的函数，按**当前真实日期**重新算出
 * 「今天是第几周、星期几、有哪些课」，而不是照搬快照。
 *
 * 这样即使应用几天没打开，卡片也能自己跳到正确的日期。
 *
 * ## 为什么放在这里而不是卡片里
 *
 * 逻辑与平台无关、纯计算，放独立模块可以直接单测
 * （卡片 UI 代码不好在 Node 里跑）。
 */

/** 与 WidgetSnapshot 一致的最小结构（避免循环依赖，只声明用到的字段） */
export interface DayCourses {
  dayOfWeek: number;
  courses: WidgetCourseLike[];
}

/** 整学期中的某一天 */
export interface TermDayCourses {
  week: number;
  dayOfWeek: number;
  courses: WidgetCourseLike[];
}

export interface WidgetCourseLike {
  name: string;
  time: string;
  room: string;
  color: string;
  teacher: string;
  content: string;
}

/** 重算结果 */
export interface RecomputedDay {
  /** 顶部左侧："第 12 周" */
  weekText: string;
  /** 顶部右侧："周三" */
  dayText: string;
  /** 今天（按当前日期算出） */
  today: WidgetCourseLike[];
  /** 明天 */
  tomorrow: WidgetCourseLike[];
  /** 明天的小标题："明天 · 11/19 周四" */
  tomorrowLabel: string;
  /** 数据是否已经不可用（跨到了整周课表覆盖不到的周） */
  outOfRange: boolean;
}

const MS_PER_DAY: number = 24 * 60 * 60 * 1000;

/** 把毫秒时间戳归一到「当天 00:00」 */
export function startOfDay(ms: number): number {
  const d = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0).getTime();
}

/** 1 = 周一 … 7 = 周日（JS 的 getDay() 里周日是 0，需要转换） */
export function dayOfWeekOf(ms: number): number {
  const g: number = new Date(startOfDay(ms)).getDay();
  return g === 0 ? 7 : g;
}

/**
 * 第几周（1 起）。以 firstMonday 那天为第 1 周周一。
 *
 * 未来日期（before firstMonday）返回 <= 0，由调用方决定怎么处理。
 */
export function weekOfDate(ms: number, firstMonday: number): number {
  const diffDays: number = Math.floor((startOfDay(ms) - startOfDay(firstMonday)) / MS_PER_DAY);
  return Math.floor(diffDays / 7) + 1;
}

/** 中文星期：1→一 … 7→日 */
export function cnWeekdayOf(dayOfWeek: number): string {
  const arr: string[] = ['一', '二', '三', '四', '五', '六', '日'];
  if (dayOfWeek < 1 || dayOfWeek > 7) {
    return '';
  }
  return arr[dayOfWeek - 1];
}

/** "11/19 周四" 这样的短标签 */
function shortLabel(ms: number): string {
  const d = new Date(ms);
  return `${d.getMonth() + 1}/${d.getDate()} 周${cnWeekdayOf(dayOfWeekOf(ms))}`;
}

/** 从整周课表里取某一天的课 */
function coursesOfDay(days: DayCourses[], dayOfWeek: number): WidgetCourseLike[] {
  for (const d of days) {
    if (d.dayOfWeek === dayOfWeek) {
      return d.courses;
    }
  }
  return [];
}

/** 从整学期课表里取「第 week 周、星期 dayOfWeek」的课 */
function coursesOfTermDay(
  termDays: TermDayCourses[], week: number, dayOfWeek: number
): WidgetCourseLike[] | undefined {
  for (const d of termDays) {
    if (d.week === week && d.dayOfWeek === dayOfWeek) {
      return d.courses;
    }
  }
  return undefined;
}

/** 兜底值（老版本快照没有整周课表时用） */
export interface DayFallback {
  weekText: string;
  dayText: string;
  today: WidgetCourseLike[];
  tomorrow: WidgetCourseLike[];
  tomorrowLabel: string;
}

/**
 * 按当前日期重算卡片要显示的内容。
 *
 * ## 两种数据源，优先用整学期
 *
 * - `termDays`（整学期）：**可以连续跨任意多天/多周**，是推荐路径
 * - `weekDays`（仅当前一周）：跨到下一周后会显示上一周的课（已知缺陷，
 *   仅为兼容老快照保留，且跨周时**主动清空**而不是显示错内容）
 *
 * @param now 当前时间戳（毫秒）。测试时传固定值便于断言。
 * @param firstMonday 学期第 1 周周一（毫秒）
 * @param totalWeeks 总周数
 * @param termDays 整学期课表（优先）
 * @param weekDays 仅当前周的课表（兜底，跨周不可用）
 * @param fb 可选兜底：缺少上面两者时，退回快照里的原值
 */
export function recomputeForToday(
  now: number,
  firstMonday: number,
  totalWeeks: number,
  termDays: TermDayCourses[],
  weekDays: DayCourses[],
  fb?: DayFallback
): RecomputedDay {
  const hasTerm: boolean = termDays.length > 0;
  const hasWeek: boolean = weekDays.length > 0;

  // 缺少必要信息 → 退回快照原值（老版本写入的数据就是这种情况）
  if (firstMonday <= 0 || (!hasTerm && !hasWeek)) {
    return {
      weekText: fb !== undefined ? fb.weekText : '',
      dayText: fb !== undefined ? fb.dayText : '',
      today: fb !== undefined ? fb.today : [],
      tomorrow: fb !== undefined ? fb.tomorrow : [],
      tomorrowLabel: fb !== undefined ? fb.tomorrowLabel : '明天',
      outOfRange: true
    };
  }

  const todayMs: number = startOfDay(now);
  const tomorrowMs: number = todayMs + MS_PER_DAY;

  const week: number = weekOfDate(todayMs, firstMonday);
  // 超出学期范围（开学前 / 放假后）：不显示课程，但标题仍然给出周次
  if (totalWeeks > 0 && (week < 1 || week > totalWeeks)) {
    return {
      weekText: week < 1 ? '未开学' : '学期已结束',
      dayText: `周${cnWeekdayOf(dayOfWeekOf(todayMs))}`,
      today: [],
      tomorrow: [],
      tomorrowLabel: `明天 · ${shortLabel(tomorrowMs)}`,
      outOfRange: true
    };
  }

  const todayDow: number = dayOfWeekOf(todayMs);
  const tomorrowDow: number = dayOfWeekOf(tomorrowMs);
  // 明天跨进下一周时，明天属于 week + 1
  const tomorrowWeek: number = tomorrowDow <= todayDow ? week + 1 : week;

  let todayCourses: WidgetCourseLike[] = [];
  let tomorrowCourses: WidgetCourseLike[] = [];

  if (hasTerm) {
    // ---- 优先：整学期数据，任意跨天/跨周都正确 ----
    const t = coursesOfTermDay(termDays, week, todayDow);
    todayCourses = t !== undefined ? t : [];
    // 明天若超出学期范围则留空
    if (totalWeeks <= 0 || tomorrowWeek <= totalWeeks) {
      const m = coursesOfTermDay(termDays, tomorrowWeek, tomorrowDow);
      tomorrowCourses = m !== undefined ? m : [];
    }
  } else {
    // ---- 兜底：只有当前一周的数据 ----
    //
    // ⚠️ 跨周后不能再拿这一周的课冒充下一周。
    // 宁可显示空（用户能看出「需要打开 App 同步」），也不能显示错的课。
    todayCourses = coursesOfDay(weekDays, todayDow);
    if (tomorrowWeek === week) {
      tomorrowCourses = coursesOfDay(weekDays, tomorrowDow);
    } else {
      tomorrowCourses = [];  // 明天已在下一周，本快照没有那天数据
    }
  }

  return {
    weekText: `第 ${week} 周`,
    dayText: `周${cnWeekdayOf(todayDow)}`,
    today: todayCourses,
    tomorrow: tomorrowCourses,
    tomorrowLabel: `明天 · ${shortLabel(tomorrowMs)}`,
    outOfRange: false
  };
}
