/**
 * 领域模型。
 *
 * 字段名按「语义」定，和教务的 40 个字符段解耦 ——
 * 教务改字段名只需改 data/Mappers.ets 一个文件。
 *
 * 移植自 Android 版 core/Models.kt。
 */

/** 日期工具：鸿蒙 ArkTS 没有 java.time，这里用 [年, 月, 日] 的毫秒时间戳代替 */
export type DateLike = number; // UTC 毫秒（当天 00:00:00）

export interface Course {
  id: string;
  name: string;
  teacher?: string;
  room?: string;
  /** 1 = 周一 … 7 = 周日 */
  dayOfWeek: number;
  startSection: number;
  endSection: number;
  /** 出现在哪几周。按周查询时就是 { 当前周 } */
  weeks: number[];
  /** 上课内容，只有按周查询才有 */
  content?: string;
  /** 真实日期（当天 00:00 的毫秒时间戳），只有按周查询才有 */
  date?: DateLike;
  /** 教务给的上课时刻，如 "08:30-10:00"（来自 qssj/jssj，比作息表准） */
  timeLabel?: string;
  /** 教务给的课程配色，如 "#1f86c7" */
  colorHex?: string;
  /** 自主学习（`jxhjmc` = 自主学习）：不需要去教室 */
  isSelfStudy?: boolean;
  /** 考试环节（`jxhjmc` = 考试（理论）/考试（实操）） */
  isExam?: boolean;
}

export function sectionSpan(c: Course): number {
  return c.endSection - c.startSection + 1;
}

export function occursIn(c: Course, week: number): boolean {
  return c.weeks.indexOf(week) >= 0;
}

export function cellKey(c: Course): number {
  return c.dayOfWeek * 100 + c.startSection;
}

export interface Grade {
  course: string;
  term: string;
  /** 百分制分数。等级制课程（优/良/中）这里可能是 undefined */
  score?: number;
  level?: string;
  gpa?: number;
  credit: number;
  kind?: string;
}

export interface Period {
  index: number;
  start: string;
  end: string;
}

export function periodLabel(p: Period): string {
  return `${p.start}-${p.end}`;
}

/**
 * 课表固定渲染的节次数：1..14。
 *
 * 晚课可能排到第 11~14 节，而 [TimetableConfig.periods] 可能是**旧版本缓存**里只有 10 条的数据。
 * 所以布局不跟配置走：永远画满 14 行，没有课的格子留空 ——
 * 否则「配置里没有 11~14 节」会让这些课整块消失在网格外。
 */
export const TOTAL_SECTIONS: number = 14;

/**
 * 课表渲染所需的元信息。
 * [firstMonday] 由「第 1 周查询的 qsrq」反推；[periods] 接口不给，用默认值。
 */
export interface TimetableConfig {
  termName: string;
  /** 第一周周一（当天 00:00 的毫秒时间戳） */
  firstMonday: DateLike;
  totalWeeks: number;
  periods: Period[];
}

export function maxSection(config: TimetableConfig): number {
  let max = 0;
  for (const p of config.periods) {
    if (p.index > max) {
      max = p.index;
    }
  }
  return max;
}
