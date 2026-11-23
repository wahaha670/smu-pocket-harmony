/**
 * 学期 / 周次换算。纯函数，无依赖，单测覆盖（SemesterTest）。
 *
 * 三条规则来自真实踩坑：
 * 1. 用 floorDiv 而不是整除，否则开学前的日期会算成第 0 周却显示成第 1 周；
 * 2. 周次必须能钳住（寒暑假期间 today 会算出 25 周，不能直接拿去查）；
 * 3. 周次串格式各家不同（"1-16" / "1,3,5" / "1-16单周" / "第3周"），必须容错。
 *
 * 移植自 Android 版 core/Semester.kt。
 */
import { addDays, daysBetween } from './DateUtils';

export class Semester {
  /** 日期属于第几周。开学前返回 ≤ 0 */
  static weekOf(dateMs: number, firstMondayMs: number): number {
    const days = daysBetween(firstMondayMs, dateMs);
    // 等价于 Kotlin 的 Math.floorDiv(days, 7) + 1
    return Math.floor(days / 7) + 1;
  }

  static clampWeek(week: number, totalWeeks: number): number {
    if (totalWeeks <= 0) {
      return 1;
    }
    if (week < 1) {
      return 1;
    }
    if (week > totalWeeks) {
      return totalWeeks;
    }
    return week;
  }

  static mondayOfWeek(week: number, firstMondayMs: number): number {
    return addDays(firstMondayMs, (week - 1) * 7);
  }

  static datesOfWeek(week: number, firstMondayMs: number): number[] {
    const monday = Semester.mondayOfWeek(week, firstMondayMs);
    const out: number[] = [];
    for (let i = 0; i <= 6; i++) {
      out.push(addDays(monday, i));
    }
    return out;
  }

  /**
   * 把教务返回的周次串解析成集合。
   *
   * 兼容：`"1-16"`、`"1,3,5,7"`、`"1-16(单)"`、`"2-16双"`、`"第3周"`、全角逗号。
   */
  static parseWeeks(raw: string, totalWeeks: number = 30): number[] {
    if (!raw || raw.trim().length === 0) {
      return [];
    }
    const text = raw
      .replace(/，/g, ',')
      .replace(/、/g, ',')
      .replace(/；/g, ',')
      .replace(/（/g, '(')
      .replace(/）/g, ')')
      .replace(/\s+/g, '');

    const seen: Set<number> = new Set<number>();
    const tokens = text.split(',');
    for (const token of tokens) {
      if (token.length === 0) {
        continue;
      }
      const oddOnly = token.indexOf('单') >= 0;
      const evenOnly = token.indexOf('双') >= 0;
      // 只保留数字和连字符
      let digits = '';
      for (const ch of token) {
        if ((ch >= '0' && ch <= '9') || ch === '-') {
          digits += ch;
        }
      }
      if (digits.length === 0) {
        continue;
      }

      const dash = digits.indexOf('-');
      let from = 0;
      let to = 0;
      if (dash >= 0) {
        const f = digits.substring(0, dash);
        const t = digits.substring(dash + 1);
        const pf = Number.parseInt(f, 10);
        const pt = Number.parseInt(t, 10);
        if (Number.isNaN(pf) || Number.isNaN(pt)) {
          continue;
        }
        from = pf;
        to = pt;
      } else {
        const p = Number.parseInt(digits, 10);
        if (Number.isNaN(p)) {
          continue;
        }
        from = p;
        to = p;
      }
      if (from <= 0 || to < from) {
        continue;
      }

      for (let w = from; w <= to; w++) {
        if (w > totalWeeks) {
          continue;
        }
        if (oddOnly && w % 2 === 0) {
          continue;
        }
        if (evenOnly && w % 2 !== 0) {
          continue;
        }
        seen.add(w);
      }
    }
    // 排序输出，方便 UI 稳定渲染
    return Array.from(seen).sort((a, b) => a - b);
  }
}
