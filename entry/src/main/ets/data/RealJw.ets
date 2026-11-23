/**
 * 真实教务实现。
 *
 * 结论全部来自原项目的真机实测：
 *
 * 1. `zc` 就是「第几周」：`zc=9` 第 9 周；`zc=` 空 整学期总表；`zc=201` 空数组。
 * 2. `Referer` 必须带，否则返回 `{"code":-401,"message":"疑似非法请求…"}`。
 * 3. 未登录是 HTTP 200 + `code:-401`，要翻译成 SessionExpiredError。
 * 4. 第 1 周的课表带 `qsrq`，所以「第一周周一」可以从它反推，不需要校历接口。
 * 5. 学期代码不再写死：交给 TermResolver 动态推算。
 *
 * 移植自 Android 版 data/RealJw.kt / Jw.kt。
 */
import { Course, Grade, TimetableConfig } from '../core/Models';
import { DefaultPeriods } from '../core/Periods';
import { Semester } from '../core/Semester';
import { SessionExpiredError, JwTransport } from '../core/Net';
import { TermCode } from '../core/TermCode';
import { addDays, parseDate, todayStart } from '../core/DateUtils';
import { toCourses, toGrades } from './Mappers';
import { CourseData, JwJson, examTaskHasMore, onlineExamNumber, scoreHasMore } from './JwJson';
import { TermResolver } from './TermResolver';

/** 教务入口配置 */
export class JwConfig {
  /** 扫码登录入口页 */
  static readonly LOGIN_URL: string = 'https://zhjw.smu.edu.cn/';
  /** 接口 baseUrl */
  static readonly BASE_URL: string = 'https://zhjw.smu.edu.cn/';
}

/** 教务服务契约 */
export interface JwService {
  timetableConfig(): Promise<TimetableConfig>;
  timetable(week?: number): Promise<Course[]>;
  grades(term?: string): Promise<Grade[]>;
  termCourses(): Promise<Course[]>;
  examNumbers(term?: string): Promise<Map<string, string>>;
  semesterCode(): Promise<string | undefined>;
  probeSession(): Promise<boolean>;
}

const MAX_PAGES: number = 20;
const MIN_WEEKS: number = 16;
const MAX_WEEKS: number = 30;
const DEFAULT_TOTAL_WEEKS: number = 20;

/**
 * 兜底学期起始日：202601 学期第 1 周周一（由 `zc=1` 的 10 条真实记录反推得出）。
 * 自举失败时用它，保证 UI 不会因为拿不到日期而崩。
 */
const FALLBACK_FIRST_MONDAY: number = new Date(2026, 7, 31, 0, 0, 0, 0).getTime();

/** 简单包装，避免到处写 `{ records: ... }` */
export interface CourseDataHolder {
  records: CourseData[];
}

export class RealJw implements JwService {
  private anchor: TimetableConfig | undefined;
  private termRows: CourseDataHolder | undefined;
  private examNumberCache: Map<string, string> | undefined;
  private resolvedTerm: string | undefined;
  /** 传输层 */
  private transport: JwTransport;
  /** 学期代码解析器 */
  private terms: TermResolver;
  /** 手填的「第一周周一」。填了就跳过自举 */
  private manualFirstMonday: number | undefined;

  constructor(transport: JwTransport, terms: TermResolver, manualFirstMonday?: number) {
    this.transport = transport;
    this.terms = terms;
    this.manualFirstMonday = manualFirstMonday;
  }

  /** 当前学期代码。首次调用会触发解析，之后走内存缓存 */
  private async term(): Promise<string> {
    if (this.resolvedTerm !== undefined) {
      return this.resolvedTerm;
    }
    const resolved = await this.terms.resolve();
    this.resolvedTerm = resolved.code;
    return resolved.code;
  }

  /** 探针专用：不触发网络解析 */
  private termForProbe(): string {
    if (this.resolvedTerm !== undefined) {
      return this.resolvedTerm;
    }
    return this.terms.peek();
  }

  async semesterCode(): Promise<string | undefined> {
    return await this.term();
  }

  async timetableConfig(): Promise<TimetableConfig> {
    return await this.bootstrap();
  }

  async timetable(week?: number): Promise<Course[]> {
    const config = await this.bootstrap();
    const target = Semester.clampWeek(
      week !== undefined ? week : Semester.weekOf(todayStart(), config.firstMonday),
      config.totalWeeks
    );

    // 响应里没有 zc（按周查的嘛），但「我查的是第 target 周」我自己知道
    const rows = await this.fetchWeek(target);
    return toCourses(rows.records, target, undefined);
  }

  /**
   * 整学期课表（含考试）。数据来自 bootstrap 已经拉过的总表，通常不产生新请求。
   * 日期用「第一周周一 + zc + xq」推算（总表没有 qsrq）。
   */
  async termCourses(): Promise<Course[]> {
    const config = await this.bootstrap();
    const rows = await this.fetchAllWeeks();
    return toCourses(rows.records, undefined, config.firstMonday);
  }

  /**
   * 考试网考号：课程名 → 号码。
   *
   * 这是纯展示增强：任何失败都退化成空表，「考试安排」照常只显示课名。
   */
  async examNumbers(term?: string): Promise<Map<string, string>> {
    if (this.examNumberCache !== undefined) {
      return this.examNumberCache;
    }

    const targetTerm = term !== undefined ? term : await this.term();
    const collected = new Map<string, string>();
    let page = 1;

    while (page <= MAX_PAGES) {
      const body = await this.transport.postForm('new/student/xskcrw/skrwDatas', {
        'xnxqdm': targetTerm,
        'page': `${page}`,
        'rows': '200'
      });
      const parsed = JwJson.examTasks(body);
      this.throwIfAuthFailed(parsed.code, parsed.message);
      if (parsed.code !== 0) {
        break;
      }

      for (const row of parsed.rows) {
        const name = row.kcmc.trim();
        const number = onlineExamNumber(row);
        if (name.length > 0 && number.length > 0) {
          collected.set(name, number);
        }
      }

      if (!examTaskHasMore(parsed)) {
        break;
      }
      page++;
    }

    // 一条都没拿到就先别缓存，下次进「今日」还能再试一次
    if (collected.size > 0) {
      this.examNumberCache = collected;
    }
    return collected;
  }

  async grades(term?: string): Promise<Grade[]> {
    const collected: Grade[] = [];
    let page = 1;

    while (page <= MAX_PAGES) {
      // 成绩要查全部学期：传空 xnxqdm 服务器才返回所有学期。
      // 传当前学期代码只会返回本学期的成绩 —— 开学初是 0 条。
      const body = await this.transport.postForm('new/student/xskccj/kccjDatas', {
        'xnxqdm': term !== undefined ? term : '',
        'source': 'kccjlist',
        'ismax': '1',
        'page': `${page}`,
        'rows': '200'
      });
      const parsed = JwJson.scores(body);
      this.throwIfAuthFailed(parsed.code, parsed.message);

      const pageGrades = toGrades(parsed.rows);
      for (const g of pageGrades) {
        collected.push(g);
      }
      if (parsed.rows.length === 0 || !scoreHasMore(parsed)) {
        break;
      }
      page++;
    }

    return collected;
  }

  /**
   * 一次请求判断登录态：`zc=1` 是最便宜的可用请求。
   * 不走 bootstrap（那要 2~3 个请求），因为扫码时会每 2 秒探一次。
   */
  async probeSession(): Promise<boolean> {
    try {
      const body = await this.transport.postForm('new/student/xsgrkb/getCalendarWeekDatas', {
        'xnxqdm': this.termForProbe(),
        'zc': '1'
      });
      return JwJson.timetable(body).code === 0;
    } catch (e) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // 自举：第一周周一 + 总周数
  // ------------------------------------------------------------------

  private async bootstrap(): Promise<TimetableConfig> {
    if (this.anchor !== undefined) {
      return this.anchor;
    }

    if (this.manualFirstMonday !== undefined) {
      return this.configOf(this.manualFirstMonday, DEFAULT_TOTAL_WEEKS);
    }

    let firstMonday: number | undefined;
    try {
      firstMonday = await this.deriveFirstMonday();
    } catch (e) {
      firstMonday = undefined;
    }
    if (firstMonday === undefined) {
      firstMonday = FALLBACK_FIRST_MONDAY;
    }

    let totalWeeks = DEFAULT_TOTAL_WEEKS;
    try {
      totalWeeks = await this.deriveTotalWeeks();
    } catch (e) {
      totalWeeks = DEFAULT_TOTAL_WEEKS;
    }

    return this.configOf(firstMonday, totalWeeks);
  }

  /**
   * 查第 1 周（`zc=1`），每行都带 `qsrq`；
   * 该行所在周的周一 = qsrq - (xq-1) 天，取最小值就是第一周周一。
   */
  private async deriveFirstMonday(): Promise<number | undefined> {
    const rows = await this.fetchWeek(1);
    let best: number | undefined;
    for (const row of rows.records) {
      const date = parseDate(row.qsrq);
      if (date === undefined) {
        continue;
      }
      if (row.xq < 1 || row.xq > 7) {
        continue;
      }
      const monday = addDays(date, -(row.xq - 1));
      if (best === undefined || monday < best) {
        best = monday;
      }
    }
    return best;
  }

  /** `zc` 传空 → 整学期总表 → 所有周次串里的最大周次就是总周数 */
  private async deriveTotalWeeks(): Promise<number> {
    const rows = await this.fetchAllWeeks();
    let max = 0;
    for (const row of rows.records) {
      const weeks = Semester.parseWeeks(row.zc);
      for (const w of weeks) {
        if (w > max) {
          max = w;
        }
      }
    }
    if (max < MIN_WEEKS) {
      return DEFAULT_TOTAL_WEEKS;
    }
    if (max > MAX_WEEKS) {
      return MAX_WEEKS;
    }
    return max;
  }

  private configOf(firstMonday: number, totalWeeks: number): TimetableConfig {
    // 这里可能还没触发过 term() 解析（bootstrap 在 timetableConfig 里最先被调用），
    // 所以 termName 用确定性来源：已解析的 > 不联网的 peek()。
    // 之后 UI 会通过 semesterCode() 拿到权威值再刷新设置页显示。
    const termCode = this.resolvedTerm !== undefined ? this.resolvedTerm : this.terms.peek();
    const config: TimetableConfig = {
      termName: TermCode.displayName(termCode),
      firstMonday: firstMonday,
      totalWeeks: totalWeeks,
      periods: DefaultPeriods.ALL
    };
    this.anchor = config;
    return config;
  }

  // ------------------------------------------------------------------
  // 底层请求
  // ------------------------------------------------------------------

  private async fetchWeek(week: number): Promise<CourseDataHolder> {
    const term = await this.term();
    const body = await this.transport.postForm('new/student/xsgrkb/getCalendarWeekDatas', {
      'xnxqdm': term,
      'zc': `${week}`
    });
    return this.decodeTimetable(body);
  }

  private async fetchAllWeeks(): Promise<CourseDataHolder> {
    if (this.termRows !== undefined) {
      return this.termRows;
    }
    const term = await this.term();
    const body = await this.transport.postForm('new/student/xsgrkb/getCalendarWeekDatas', {
      'xnxqdm': term,
      'zc': ''
    });
    const rows = this.decodeTimetable(body);
    this.termRows = rows;
    return rows;
  }

  private decodeTimetable(body: string): CourseDataHolder {
    const parsed = JwJson.timetable(body);
    this.throwIfAuthFailed(parsed.code, parsed.message);
    if (parsed.code !== 0) {
      throw new Error(`教务返回 code=${parsed.code}，message=${parsed.message}`);
    }
    return { records: parsed.data };
  }

  /** 教务用 `code = -401` 表示未登录（HTTP 仍是 200），统一翻译成可捕获的异常 */
  private throwIfAuthFailed(code: number, message: string): void {
    if (code === -401) {
      throw new SessionExpiredError(message.length > 0 ? message : '登录态失效，请重新扫码登录');
    }
  }
}
