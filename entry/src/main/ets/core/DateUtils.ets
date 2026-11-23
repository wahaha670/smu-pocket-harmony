/**
 * 日期工具。
 *
 * Android 版用 `java.time.LocalDate`，HarmonyOS ArkTS 没有这个类，
 * 所以这里用「UTC 毫秒时间戳」表示某一天 00:00:00，
 * 并提供等价的加减 / 比较 / 格式化能力。
 *
 * 关键：**全部按本地时区的当天 00:00 计算**，避免夏令时/时区把日期算偏。
 * 中国没有夏令时，但代码写成通用形式更稳。
 *
 * 移植自 Android 版 core/TimeUtils.kt / Semester.kt。
 */

/** 一天的毫秒数 */
export const DAY_MS: number = 24 * 3600 * 1000;

/** 把年月日转成「当天本地 00:00」的毫秒时间戳 */
export function makeDate(year: number, month: number, day: number): number {
  // month 为 1~12
  return new Date(year, month - 1, day, 0, 0, 0, 0).getTime();
}

/** 今天 00:00 */
export function todayStart(): number {
  const d = new Date();
  return makeDate(d.getFullYear(), d.getMonth() + 1, d.getDate());
}

/** 在某个日期上加天数（返回新的 00:00 时间戳） */
export function addDays(dateMs: number, days: number): number {
  const d = new Date(dateMs);
  return makeDate(d.getFullYear(), d.getMonth() + 1, d.getDate() + days);
}

/** 在某个日期上加周数 */
export function addWeeks(dateMs: number, weeks: number): number {
  return addDays(dateMs, weeks * 7);
}

/** 两个日期相差多少天（b - a），向下取整到天 */
export function daysBetween(aMs: number, bMs: number): number {
  return Math.round((bMs - aMs) / DAY_MS);
}

/**
 * 星期几：1 = 周一 … 7 = 周日。
 * JS 的 `getDay()` 是 0=周日，要转换。
 */
export function dayOfWeek(dateMs: number): number {
  const jsDay = new Date(dateMs).getDay(); // 0..6, 0=Sunday
  return jsDay === 0 ? 7 : jsDay;
}

/** 该日期所在周的周一 */
export function mondayOf(dateMs: number): number {
  return addDays(dateMs, -(dayOfWeek(dateMs) - 1));
}

/** 年 / 月(1~12) / 日 */
export function yearOf(dateMs: number): number {
  return new Date(dateMs).getFullYear();
}

export function monthOf(dateMs: number): number {
  return new Date(dateMs).getMonth() + 1;
}

export function dayOfMonth(dateMs: number): number {
  return new Date(dateMs).getDate();
}

/** "2026-10-23" */
export function formatDate(dateMs: number): string {
  const y = yearOf(dateMs);
  const m = monthOf(dateMs);
  const d = dayOfMonth(dateMs);
  return `${y}-${pad2(m)}-${pad2(d)}`;
}

/** 教务要求的参数格式："2026-10-26 00:00:00" */
export function formatPayload(dateMs: number): string {
  return `${formatDate(dateMs)} 00:00:00`;
}

/**
 * 解析教务给的日期字符串。
 * 兼容 "2026-10-23" 和 "2026-10-23 00:00:00" 两种写法。
 * 解析失败返回 undefined（不瞎猜）。
 */
export function parseDate(raw: string | undefined | null): number | undefined {
  if (!raw) {
    return undefined;
  }
  const text = raw.trim();
  if (text.length < 10) {
    return undefined;
  }
  const head = text.substring(0, 10);
  const m = head.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!m) {
    return undefined;
  }
  const y = Number.parseInt(m[1], 10);
  const mo = Number.parseInt(m[2], 10);
  const d = Number.parseInt(m[3], 10);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) {
    return undefined;
  }
  return makeDate(y, mo, d);
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/** 人类可读的相对时间："刚刚 / 12 分钟前 / 3 小时前 / 2 天前" */
export function humanizeAgo(millis: number): string {
  const minutes = Math.floor((Date.now() - millis) / 60000);
  if (minutes < 1) {
    return '刚刚';
  }
  if (minutes < 60) {
    return `${minutes} 分钟前`;
  }
  if (minutes < 60 * 24) {
    return `${Math.floor(minutes / 60)} 小时前`;
  }
  return `${Math.floor(minutes / (60 * 24))} 天前`;
}

/** 中文星期："一".."日" */
export function cnWeekday(dateMs: number): string {
  // ArkTS 不允许对字符串做索引访问（arkts-no-props-by-index），改用数组
  const labels: string[] = ['一', '二', '三', '四', '五', '六', '日'];
  const idx = dayOfWeek(dateMs);
  return idx >= 1 && idx <= 7 ? labels[idx - 1] : '?';
}

/** 由「第一周周一 + 第几周 + 星期几」算出具体日期 */
export function dateOf(firstMonday: number, week: number, dayOfWeekValue: number): number {
  return addDays(addWeeks(firstMonday, week - 1), dayOfWeekValue - 1);
}
