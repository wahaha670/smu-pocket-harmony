/**
 * 学期代码（`xnxqdm`）的换算与推算。
 *
 * 规则由真实数据反推：
 *
 * ```
 * 代码 = 学年起始年 + "0" + 学期序号
 *
 * 202601 → 2026-2027 学年 第 1 学期
 * 202502 → 2025-2026 学年 第 2 学期
 * ```
 *
 * 注意：第 2 学期的代码年份是**学年起始年**，不是结束年。
 *
 * ## 为什么要「推算」
 *
 * 这个教务系统**没有提供查询当前学期的接口**：`getXnxqList` / `getXnxq` /
 * `getCalendar` 等候选路径全部 404。好在学期边界非常规律（9 月开学），
 * 按日期推算的结果与教务一致，且完全不依赖网络。
 *
 * ⚠️ 历史坑：教务成绩页下拉里混着 203402（2034 年）这种未来值，
 * 早期「取最大六位数」直接把 203402 当当前学期，导致所有请求返回空数据。
 * 所以必须有 [isPlausible] 拦着。
 *
 * 移植自 Android 版 core/TermCode.kt。
 */
import { yearOf } from './DateUtils';

export class TermCode {
  /** 兜底学期：所有手段都失败时用它 */
  static readonly FALLBACK: string = '202601';

  /**
   * "2026-2027-1"、"2026-2027 学年 第 1 学期"、"2025-2026-2" → 短代码。
   * 认不出来的返回 undefined（不会瞎猜）。
   */
  static fromDisplayName(name: string | undefined | null): string | undefined {
    const text = (name ?? '').trim();
    if (text.length === 0) {
      return undefined;
    }

    const yearMatch = text.match(/(\d{4})\s*-\s*(\d{4})/);
    if (!yearMatch) {
      return undefined;
    }
    const startYear = yearMatch[1];

    let half: string | undefined;
    const chinese = text.match(/第\s*([12])\s*学期/);
    if (chinese) {
      half = chinese[1];
    } else {
      const trailing = text.match(/-\s*([12])\s*$/);
      if (trailing) {
        half = trailing[1];
      }
    }
    if (!half) {
      return undefined;
    }
    return `${startYear}0${half}`;
  }

  /** "202601" → "2026-2027 学年 第 1 学期" */
  static displayName(code: string): string {
    const start = Number.parseInt(code.substring(0, 4), 10);
    if (Number.isNaN(start)) {
      return code;
    }
    const halfRaw = code.substring(4);
    const half = Number.parseInt(halfRaw, 10);
    if (Number.isNaN(half)) {
      return code;
    }
    return `${start}-${start + 1} 学年 第 ${half === 2 ? 2 : 1} 学期`;
  }

  /**
   * 按日期推算当前学期代码。学年 9 月开学：
   *
   * | 月份 | 学年起始年 | 学期 |
   * |---|---|---|
   * | 9 ~ 12 | 当年 | 第 1 学期 |
   * | 1 | 上一年 | 第 1 学期 |
   * | 2 ~ 8 | 上一年 | 第 2 学期 |
   */
  static fromDate(dateMs?: number): string {
    const d = dateMs === undefined ? new Date() : new Date(dateMs);
    const month = d.getMonth() + 1;
    const year = d.getFullYear();
    const startYear = month >= 9 ? year : year - 1;
    const half = month >= 2 && month <= 8 ? 2 : 1;
    return `${startYear}0${half}`;
  }

  static isValid(code: string | undefined | null): boolean {
    if (!code) {
      return false;
    }
    return /^\d{6}$/.test(code);
  }

  /**
   * 这个代码像不像「真的学期」。
   *
   * 规则：学期号只能是 1 或 2，且学年起始年离今天不超过 ±1 年。
   */
  static isPlausible(code: string | undefined | null, todayMs?: number): boolean {
    if (!TermCode.isValid(code)) {
      return false;
    }
    const raw = code as string;
    const startYear = Number.parseInt(raw.substring(0, 4), 10);
    const half = Number.parseInt(raw.substring(4), 10);
    if (Number.isNaN(startYear) || Number.isNaN(half)) {
      return false;
    }
    if (half !== 1 && half !== 2) {
      return false;
    }
    const todayYear = todayMs === undefined ? new Date().getFullYear() : yearOf(todayMs);
    return Math.abs(startYear - todayYear) <= 1;
  }
}
