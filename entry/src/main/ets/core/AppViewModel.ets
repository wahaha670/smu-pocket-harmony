/**
 * 全局状态 + 业务编排。
 *
 * Android 版用 ViewModel + StateFlow；HarmonyOS ArkUI 用 @Observed + @ObjectLink。
 * 这里选「单例 Store + @Observed 类」：UI 组件持有同一个 AppState 实例，
 * 字段变化时框架自动刷新，语义和 StateFlow 最接近。
 *
 * 移植自 Android 版 ui/AppViewModel.kt（原 515 行）。
 *
 * 核心语义（不能改）：
 * - `scheduleCourses` 是「当前选中那一周」的课（课表页）
 * - `currentWeekCourses` 是「真实当前周」的课（今日页）—— 两者必须解耦
 * - `stale = true` 表示显示的是本地缓存，登录已过期
 */
import { Course, Grade, TimetableConfig } from './Models';
import { Semester } from './Semester';
import { SessionExpiredError, SessionStoreLike } from './Net';
import { todayStart, addDays, dayOfWeek, monthOf, dayOfMonth, cnWeekday } from './DateUtils';
import {
  CacheStore,
  makeSnapshot,
  snapshotToConfig,
  snapshotToCourses,
  snapshotToCurrentCourses,
  snapshotToExams,
  snapshotToGrades,
  snapshotToTermCourses
} from './CacheStore';
import { assignCourseColors, courseColor } from './CourseColors';
import { mergeWeekIntoTerm, enrichCourse, pickText, weekMissingContent, weekNeedsWeeklySync, preserveRichFields } from './CourseMerge';
import { toWidgetCourses, widgetTime, collectCourseColors } from './WidgetBuilder';
import { loadWeekData, WeekLoadResult } from './WeekLoader';
import { WidgetCourse, WidgetSnapshot, WidgetDay, WidgetTermDay, saveWidgetSnapshot } from './WidgetData';
import { JwService } from '../data/RealJw';
import { FakeJw } from '../data/FakeJw';
import formProvider from '@ohos.app.form.formProvider';
import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import { BusinessError } from '@ohos.base';

/** 桌面卡片在 module.json5 / form_config.json 里的三个标识，刷新时必须一致 */
const WIDGET_MODULE_NAME: string = 'entry';
const WIDGET_ABILITY_NAME: string = 'EntryFormAbility';
const WIDGET_FORM_NAME: string = 'TodayTomorrowCard';

/** 网考号最多等多久：超时就当没有，不能让「考试安排」一直转圈 */
const EXAM_NUMBERS_TIMEOUT_MS: number = 5000;

/**
 * 连接套件：把各个存储/服务装在一起，替代 Android 的 AppContainer。
 *
 * ⚠️ 用 class 而不是 interface：ArkTS 要求对象字面量必须对应
 * **显式声明的 class 或 interface**，且接口做对象字面量赋值时
 * 在部分版本会报 `arkts-no-untyped-obj-literals`。用 class 最稳。
 */
export class AppDeps {
  session: SessionStoreLike;
  cache: CacheStore;
  jwFactory: () => JwService;
  /**
   * 应用上下文。
   *
   * 两个用途：
   * 1. 取沙箱 files 目录 —— 桌面卡片的 FormExtensionAbility 要读同一份
   *    `widget_data.json`；
   * 2. 刷新卡片 —— `formProvider.reloadForms` 要求传 UIAbilityContext。
   */
  abilityContext: common.UIAbilityContext;

  constructor(
    session: SessionStoreLike,
    cache: CacheStore,
    jwFactory: () => JwService,
    abilityContext: common.UIAbilityContext
  ) {
    this.session = session;
    this.cache = cache;
    this.jwFactory = jwFactory;
    this.abilityContext = abilityContext;
  }
}

/** 只依赖接口，避免循环引用；定义在 Net.ets 里 */
export { SessionStoreLike } from './Net';

/**
 * 可观察状态。
 *
 * 注意：ArkTS 的 @Observed 只监听一层属性变化。
 * 所以每次更新都整体替换字段（而不是改数组内部元素），
 * 并且数组字段用 copy 生成新数组，确保 UI 能感知。
 */
@Observed
export class AppState {
  loading: boolean = false;
  loggedIn: boolean = false;
  demoMode: boolean = false;
  config: TimetableConfig | undefined = undefined;

  /** 课表页：用户选中那一周的课（随 selectedWeek 变） */
  scheduleCourses: Course[] = [];
  /** 今日页：真实当前周的课（与 selectedWeek 完全无关） */
  currentWeekCourses: Course[] = [];
  /** 明日跨到下一周时，这里是下一周的课（只有今天是周日才会去拉） */
  nextWeekCourses: Course[] = [];
  /** currentWeekCourses 实际属于第几周。缓存是旧的周时，它 != currentWeek */
  currentCoursesWeek: number = 0;

  /** 整学期课表（含考试安排），供「近期考试」使用 */
  termCourses: Course[] = [];

  /**
   * 考试「网考号」：课程名 → 网考号。
   * 只放内存、不落缓存：号码跟着学期/会话变，缓存旧号反而会误导。
   */
  examNumbers: Map<string, string> = new Map<string, string>();
  /** 网考号是否「已就绪」（成功/失败/没会话都算就绪） */
  examNumbersReady: boolean = false;

  /** 成绩是否成功拉取过（失败时不要把缓存里的成绩覆盖成空） */
  gradesLoaded: boolean = false;

  /** 切周失败的原因；空字符串 = 没有错误 */
  weekError: string = '';

  /**
   * 本周课程缺少「上课内容」的轻量提示；空字符串 = 不提示。
   *
   * ⚠️ 与 weekError 严格区分：
   * weekError 有值会让课表**整块被错误页替换**（课程网格消失），
   * 而这个提示只是课表上方的一行小字，不影响网格渲染。
   */
  weekContentHint: string = '';

  /** 当前使用的学期代码，如 "202601" */
  semesterCode: string = '';
  grades: Grade[] = [];
  currentWeek: number = 1;
  selectedWeek: number = 1;
  error: string = '';
  /** 数据来自缓存（登录已过期） */
  stale: boolean = false;
  /** 缓存写入时间，用于「更新于 X 分钟前」 */
  cachedAt: number = 0;

  /**
   * 原地重置所有字段。
   *
   * 必须原地清空，不能 `vm.state = new AppState()`：
   * UI 组件通过 @ObjectLink 绑定的是这个对象实例，
   * 整体替换会让绑定指向旧实例 → 界面不再刷新（退出登录后停在原页面）。
   */
  reset(): void {
    this.loading = false;
    this.loggedIn = false;
    this.demoMode = false;
    this.config = undefined;
    this.scheduleCourses = [];
    this.currentWeekCourses = [];
    this.nextWeekCourses = [];
    this.currentCoursesWeek = 0;
    this.termCourses = [];
    this.examNumbers = new Map<string, string>();
    this.examNumbersReady = false;
    this.gradesLoaded = false;
    this.weekError = '';
    this.semesterCode = '';
    this.grades = [];
    this.currentWeek = 1;
    this.selectedWeek = 1;
    this.error = '';
    this.stale = false;
    this.cachedAt = 0;
  }

  // ---- 派生值（UI 直接调用） ----

  scheduleWeekCourses(): Course[] {
    return this.scheduleCourses.filter((c) => c.weeks.indexOf(this.selectedWeek) >= 0);
  }

  selectedWeekTotal(): number {
    return this.scheduleWeekCourses().length;
  }

  // ---- 选中周次的日期（课表页表头用） ----

  /**
   * 选中那一周的 7 个日期（周一 → 周日），当天 00:00 的毫秒时间戳。
   *
   * 拿不到 config（未登录 / 无数据）时返回空数组，UI 用空表兜底。
   */
  selectedWeekDates(): number[] {
    const cfg = this.config;
    if (cfg === undefined) {
      return [];
    }
    const monday = addDays(cfg.firstMonday, (this.selectedWeek - 1) * 7);
    const out: number[] = [];
    for (let i = 0; i < 7; i++) {
      out.push(addDays(monday, i));
    }
    return out;
  }

  /**
   * 课表标题要显示的月份（1~12）；拿不到日期时返回 0。
   *
   * 规则：**跨月时取前一个月份**（即周一所在的月份）。
   * 例：某周跨 10 月 / 11 月，标题显示「10月」，下方各天日期照常显示自己的日。
   */
  selectedWeekTitleMonth(): number {
    const dates = this.selectedWeekDates();
    if (dates.length === 0) {
      return 0;
    }
    // 周一（第一个元素）所在月份，天然满足「跨月取前一个」
    return monthOf(dates[0]);
  }

  /**
   * 该周是否跨月（周一与周日不在同一个月）。
   * 目前 UI 不需要强调，但保留给后续优化（比如跨月周用不同样式）。
   */
  selectedWeekSpansTwoMonths(): boolean {
    const dates = this.selectedWeekDates();
    if (dates.length === 0) {
      return false;
    }
    return monthOf(dates[0]) !== monthOf(dates[6]);
  }

  /**
   * 今日页：只看**真实当前周**，和 selectedWeek 无关。
   * 用户在课表翻到第 8 周时，今日页必须仍然是真实当前周的课。
   *
   * ⚠️ 离线正确性的关键（本次改造）：
   * 早期实现只从 `currentWeekCourses` 取 —— 那是**缓存那一刻**的「当前周」，
   * 隔天再看就过期了（缓存里还存着昨天的周次/星期）。
   *
   * 现在改为：
   * 1. 用**今天**的日期，从 firstMonday 实时算出「今天属于第几周」；
   * 2. 优先从 `termCourses`（整学期缓存）过滤当天的课；
   * 3. 只有整学期缓存缺失时，才退回老的 `currentWeekCourses`。
   *
   * 这样即使完全离线、登录失效，只要缓存过一次整学期课表，
   * 今日页每天都会按真实日期正确显示当天该上的课。
   */
  todayCourses(): Course[] {
    const todayIdx = dayOfWeek(todayStart());
    const week = this.liveCurrentWeek();
    return this.coursesForWeekAndDay(week, todayIdx);
  }

  /**
   * 取「第 week 周、星期 dayOfWeek」的课，并**合并两种数据源的优点**。
   *
   * 为什么需要合并：
   * - 整学期总表（termCourses）：覆盖全部 20 周，是离线基础；
   *   但教务在总表里**只对部分课程返回 `sknrjj`（上课内容）**，实测 220 条里仅 43 条有。
   * - 按周查询（currentWeekCourses）：内容字段齐全（16/16），但只有「缓存那一刻」的那一周。
   *
   * 所以：以整学期数据为骨架，用按周数据（当周匹配时）**补全 content**。
   * 这样既保住了离线可翻周，又不丢上课内容。
   */
  private coursesForWeekAndDay(week: number, dayOfWeekValue: number): Course[] {
    const term = this.termCourses;
    if (term.length === 0 || week <= 0) {
      // 兜底：无整学期缓存 → 用旧的按周数据
      return this.currentWeekCourses
        .filter((c) => c.weeks.indexOf(this.currentWeek) >= 0 && c.dayOfWeek === dayOfWeekValue)
        .sort((a, b) => a.startSection - b.startSection);
    }

    // 按周数据只对「它自己那一周」有参考价值
    const weeklyUsable = this.currentCoursesWeek === week;
    const rich: Course[] = weeklyUsable ? this.currentWeekCourses : [];

    const picked: Course[] = [];
    for (const c of term) {
      if (c.weeks.indexOf(week) < 0 || c.dayOfWeek !== dayOfWeekValue) {
        continue;
      }
      picked.push(this.enrichWithWeekly(c, rich));
    }
    return picked.sort((a, b) => a.startSection - b.startSection);
  }

  /**
   * 本周课程是否缺上课内容（sknrjj）。
   *
  /**
   * 用按周数据补全某条课的字段（今日页专用路径）。
   *
   * ⚠️ 与 `core/CourseMerge.enrichCourse` 保持一致的策略：
   * - `content`：base 优先，空则取按周值
   * - **`room`：按周值优先** —— 整学期总表给的是「这一学期用过的所有教室」
   *   拼接（如 `207教室,403教室,408教室,604教室`），而按周查询给的是
   *   当周精确教室（如 `604教室`）。以课表页为准 = 以按周值为准。
   *
   * 保留 base 的 id / weeks：离线按周过滤依赖它们。
   */
  private enrichWithWeekly(base: Course, rich: Course[]): Course {
    for (const r of rich) {
      if (r.dayOfWeek === base.dayOfWeek &&
          r.startSection === base.startSection &&
          r.name === base.name) {
        // 命中同一节课：按统一策略合并（room 取按周值）
        return {
          id: base.id,
          name: base.name,
          teacher: pickText(base.teacher, r.teacher),
          room: pickText(r.room, base.room),
          dayOfWeek: base.dayOfWeek,
          startSection: base.startSection,
          endSection: base.endSection,
          weeks: base.weeks,
          content: pickText(base.content, r.content),
          date: base.date,
          timeLabel: pickText(base.timeLabel, r.timeLabel),
          colorHex: pickText(base.colorHex, r.colorHex),
          isSelfStudy: base.isSelfStudy === true || r.isSelfStudy === true,
          isExam: base.isExam === true || r.isExam === true
        };
      }
    }
    return base;
  }

  /**
   * 用**今天**的日期实时算出「真实当前周」。
   *
   * 与 `currentWeek` 字段的区别：
   * - `currentWeek` 是**缓存/加载那一刻**算出来的周次，可能已经过期；
   * - `liveCurrentWeek()` 每次都按当天日期重算，隔天打开就是新的一周。
   *
   * 拿不到 config 时退回 `currentWeek`。
   */
  liveCurrentWeek(): number {
    const cfg = this.config;
    if (cfg === undefined) {
      return this.currentWeek;
    }
    return Semester.clampWeek(
      Semester.weekOf(todayStart(), cfg.firstMonday),
      cfg.totalWeeks
    );
  }

  /** 每天几节课（真实当前周），用于「本周概览」条形图 */
  dailyCounts(): number[] {
    const out: number[] = [];
    const week = this.liveCurrentWeek();
    const term = this.termCourses;
    for (let day = 1; day <= 7; day++) {
      let count = 0;
      if (term.length > 0 && week > 0) {
        for (const c of term) {
          if (c.weeks.indexOf(week) >= 0 && c.dayOfWeek === day) {
            count++;
          }
        }
      } else {
        for (const c of this.currentWeekCourses) {
          if (c.weeks.indexOf(this.currentWeek) >= 0 && c.dayOfWeek === day) {
            count++;
          }
        }
      }
      out.push(count);
    }
    return out;
  }

  /** 本周总节数（按今天实时算的周次） */
  weekTotal(): number {
    const week = this.liveCurrentWeek();
    const term = this.termCourses;
    let count = 0;
    if (term.length > 0 && week > 0) {
      for (const c of term) {
        if (c.weeks.indexOf(week) >= 0) {
          count++;
        }
      }
      return count;
    }
    for (const c of this.currentWeekCourses) {
      if (c.weeks.indexOf(this.currentWeek) >= 0) {
        count++;
      }
    }
    return count;
  }

  /** 明天是第几周（按今天实时推算；拿不到 config 时返回 0） */
  tomorrowWeek(): number {
    const c = this.config;
    if (c === undefined) {
      return 0;
    }
    const tomorrow = addDays(todayStart(), 1);
    return Semester.clampWeek(Semester.weekOf(tomorrow, c.firstMonday), c.totalWeeks);
  }

  /**
   * 当前周的数据是否「新鲜」。
   *
   * 有整学期缓存时永远为 true（因为今日页直接从整学期数据实时过滤，
   * 不依赖「缓存那一刻的周」）；否则退回老的比较方式。
   */
  todayDataReady(): boolean {
    if (this.termCourses.length > 0 && this.config !== undefined) {
      return true;
    }
    return this.currentCoursesWeek === this.currentWeek;
  }

  /** 明天那一周的数据是否已就绪 */
  tomorrowDataReady(): boolean {
    const week = this.tomorrowWeek();
    if (week === 0) {
      return false;
    }
    // 有整学期缓存 → 任意周都能本地算出来
    if (this.termCourses.length > 0) {
      return true;
    }
    if (week === this.currentWeek) {
      return this.todayDataReady();
    }
    return this.nextWeekCourses.length > 0;
  }

  /** 近期考试：只要今天及以后的，按日期从近到远 */
  upcomingExams(): Course[] {
    const today = todayStart();
    return this.termCourses
      .filter((e) => e.isExam === true && e.date !== undefined && e.date >= today)
      .sort((a, b) => {
        const da = a.date !== undefined ? a.date : 0;
        const db = b.date !== undefined ? b.date : 0;
        return da - db;
      });
  }

  /**
   * 明日课程。
   *
   * 注意跨周：今天是周日时，明天属于**下一周**，当前周的数据里没有明天的课。
   *
   * 有整学期缓存时，直接从 `termCourses` 按「明天的周次 + 星期」过滤，
   * 天然支持跨周、跨月、跨年，也不需要 preload 下一周。
   */
  tomorrowCourses(): Course[] {
    const week = this.tomorrowWeek();
    if (week === 0) {
      return [];
    }
    const tomorrowIdx = dayOfWeek(addDays(todayStart(), 1));
    return this.coursesForWeekAndDay(week, tomorrowIdx);
  }

  // ---- 桌面卡片数据 ----

  /**
   * 构建桌面卡片要用的数据快照（今明两天的课）。
   *
   * 卡片里**只放渲染需要的字段**（课名/时间/地点/颜色），
   * 因为卡片数据要跨进程传给 FormExtensionAbility，
   * 传整学期几百条会让卡片启动变慢。
   */
  /** 从整学期课表里取「第 week 周、星期 dow」的课（按节次排序） */
  private coursesOfDayOfWeek(term: Course[], week: number, dow: number): Course[] {
    const out: Course[] = [];
    if (term.length > 0 && week > 0) {
      for (const c of term) {
        if (c.weeks.indexOf(week) >= 0 && c.dayOfWeek === dow) {
          out.push(c);
        }
      }
      out.sort((a, b) => a.startSection - b.startSection);
      return out;
    }
    // 无整学期缓存 → 退回按周数据
    for (const c of this.currentWeekCourses) {
      if (c.weeks.indexOf(this.currentWeek) >= 0 && c.dayOfWeek === dow) {
        out.push(c);
      }
    }
    out.sort((a, b) => a.startSection - b.startSection);
    return out;
  }

  buildWidgetSnapshot(): WidgetSnapshot {
    const today = this.todayCourses();
    const tomorrow = this.tomorrowCourses();
    const colors = this.courseColorMap();
    // 本方法在 AppState 里，配置就是 this.config（不是 this.state.config）
    const config = this.config;

    const term: Course[] = this.termCourses;
    const week: number = this.liveCurrentWeek();
    const totalWeeks: number = config !== undefined ? config.totalWeeks : 0;

    // 整学期课表：卡片据此可连续跨任意多天/多周。
    //
    // ⚠️ 只存「一周」是不够的：卡片跨到下一周后没有新数据，
    // 会继续显示上一周的课（实测缺陷）。所以存**整学期**。
    //
    // 性能说明：40 周×7 天 ≈ 140 条，实测 JSON 约 51 KB，可以接受。
    // 之前还会再单独生成一份「当前周」的 weekDays，但那 7 天是
    // termDays 里同一批数据的**完全重复**（同样的课程对象序列化两遍），
    // 现在改为从 termDays 中直接摘出，不再重复调用 toWidgetCourses。
    const termDays: WidgetTermDay[] = [];
    for (let w = 1; w <= totalWeeks; w++) {
      for (let dow = 1; dow <= 7; dow++) {
        const dayCourses: Course[] = this.coursesOfDayOfWeek(term, w, dow);
        // 空的天也存：卡片据此区分「这天没课」和「这天没数据」
        termDays.push({
          week: w,
          dayOfWeek: dow,
          courses: this.toWidgetCourses(dayCourses, colors)
        });
      }
    }

    // 当前周的 7 天：从 termDays 里直接摘，避免重复序列化同一批课程
    const weekDays: WidgetDay[] = [];
    for (const td of termDays) {
      if (td.week === week) {
        weekDays.push({ dayOfWeek: td.dayOfWeek, courses: td.courses });
      }
    }
    // 边界：当前周超出 termDays 范围（学期已结束）→ 逐天回退计算
    if (weekDays.length === 0) {
      for (let dow = 1; dow <= 7; dow++) {
        weekDays.push({
          dayOfWeek: dow,
          courses: this.toWidgetCourses(this.coursesOfDayOfWeek(term, week, dow), colors)
        });
      }
    }

    const snap: WidgetSnapshot = {
      weekText: `第 ${week} 周`,
      dayText: `周${cnWeekday(todayStart())}`,
      today: this.toWidgetCourses(today, colors),
      tomorrow: this.toWidgetCourses(tomorrow, colors),
      tomorrowLabel: `明天 · ${this.tomorrowShortLabel()}`,
      updatedAt: Date.now(),
      // 供卡片本地重算日期用
      firstMonday: config !== undefined ? config.firstMonday : 0,
      totalWeeks: totalWeeks,
      weekDays: weekDays,
      // 整学期课表：卡片据此可连续跨任意多天/多周
      termDays: termDays
    };
    return snap;
  }

  /** 明天的小标题，如 "11/14 周六" */
  private tomorrowShortLabel(): string {
    const d = addDays(todayStart(), 1);
    const wd: string[] = ['一', '二', '三', '四', '五', '六', '日'];
    const idx = dayOfWeek(d) - 1;
    const w = idx >= 0 && idx < 7 ? wd[idx] : '';
    return `${monthOf(d)}/${dayOfMonth(d)} 周${w}`;
  }

  /** 领域课程 → 卡片条目 */
  private toWidgetCourses(list: Course[], colors: Map<string, string>): WidgetCourse[] {
    // 实现在 core/WidgetBuilder.ets（纯函数，可单测）
    const periods = this.config !== undefined ? this.config.periods : [];
    return toWidgetCourses(list, colors, periods);
  }

  /**
   * 课程名 → 颜色映射（与课表页共用 CourseColors 的分配算法）。
   *
   * 实现在 core/WidgetBuilder.ets（纯函数，可单测）。
   */
  private courseColorMap(): Map<string, string> {
    return collectCourseColors(
      this.termCourses,
      // 今日 + 明日的课都可能还没并进 termCourses，必须一起纳入
      this.todayCourses().concat(this.tomorrowCourses()),
      (names: string[]) => assignCourseColors(names)
    );
  }

  /**
   * 卡片上显示的时间文本（实现在 core/WidgetBuilder.ets）。
   */
  private widgetTime(c: Course): string {
    const periods = this.config !== undefined ? this.config.periods : [];
    return widgetTime(c, periods);
  }

  hasData(): boolean {
    return this.scheduleCourses.length > 0 || this.currentWeekCourses.length > 0 || this.grades.length > 0;
  }

  weightedGpa(): number {
    let sum = 0;
    let credits = 0;
    for (const g of this.grades) {
      if (g.gpa !== undefined && g.credit > 0) {
        sum += g.gpa * g.credit;
        credits += g.credit;
      }
    }
    return credits > 0 ? sum / credits : 0;
  }

  weightedScore(): number {
    let sum = 0;
    let credits = 0;
    for (const g of this.grades) {
      if (g.score !== undefined && g.credit > 0) {
        sum += g.score * g.credit;
        credits += g.credit;
      }
    }
    return credits > 0 ? sum / credits : 0;
  }

  totalCredit(): number {
    let sum = 0;
    for (const g of this.grades) {
      sum += g.credit;
    }
    return sum;
  }

  /** 按学期分组，新的在前 */
  gradesByTerm(): Map<string, Grade[]> {
    const map = new Map<string, Grade[]>();
    for (const g of this.grades) {
      const list = map.get(g.term);
      if (list === undefined) {
        map.set(g.term, [g]);
      } else {
        list.push(g);
      }
    }
    // Map 保序，但学期名要倒序：转成数组再排
    const sorted = new Map<string, Grade[]>();
    const keys: string[] = [];
    map.forEach((_v: Grade[], k: string) => {
      keys.push(k);
    });
    keys.sort((a, b) => (a < b ? 1 : a > b ? -1 : 0));
    for (const k of keys) {
      const v = map.get(k);
      if (v !== undefined) {
        sorted.set(k, v);
      }
    }
    return sorted;
  }
}

@Observed
export class AppViewModel {
  state: AppState = new AppState();

  private jw: JwService;
  private session: SessionStoreLike;
  private cache: CacheStore;
  private jwFactory: () => JwService;
  /** 应用上下文（写卡片数据 + 刷新卡片用） */
  private abilityContext: common.UIAbilityContext;
  /** 沙箱 files 目录，用于写桌面卡片数据 */
  private filesDir: string;

  /** 设置页点了「同步」：这种情况下会话失效就直接回登录页 */
  private explicitSync: boolean = false;

  /**
   * 「重新登录后自动同步」的待办标记。
   *
   * 用户点设置页「重新登录以同步最新数据」后置位；
   * LoginScreen 挂载时消费它 —— 若为 true 就自动打开扫码登录，
   * 省掉用户再点一次「打开教务系统登录」。
   */
  private pendingLoginThenSync: boolean = false;
  /** 切周的请求序号：防止旧响应覆盖新响应（等价于 Android 的 Job.cancel） */
  private weekToken: number = 0;

  constructor(deps: AppDeps) {
    this.session = deps.session;
    this.cache = deps.cache;
    this.jwFactory = deps.jwFactory;
    this.abilityContext = deps.abilityContext;
    this.filesDir = deps.abilityContext.filesDir;
    this.jw = this.jwFactory();
  }

  /**
   * 应用启动时调用：先亮缓存（秒开、断网也能看），再去后台刷新。
   */
  async bootstrap(): Promise<void> {
    const restored = this.restoreFromCache();
    if (restored) {
      if (this.session.isLoggedIn()) {
        await this.loadAll();
      } else {
        // cookie 已经没了，但本地还有数据 —— 温和提示，不踢回登录页
        this.state.stale = true;
        this.state.loggedIn = true;
      }
    } else if (this.session.isLoggedIn()) {
      this.state.loggedIn = true;
      await this.loadAll();
    }
  }

  /** @return 是否成功恢复了缓存 */
  private restoreFromCache(): boolean {
    const snapshot = this.cache.load();
    if (snapshot === undefined) {
      return false;
    }
    if (snapshot.courses.length === 0 && snapshot.grades.length === 0) {
      return false;
    }
    const config = snapshotToConfig(snapshot);
    if (config === undefined) {
      return false;
    }
    const current = Semester.clampWeek(
      Semester.weekOf(todayStart(), config.firstMonday),
      config.totalWeeks
    );

    this.state.loggedIn = true;
    this.state.config = config;
    this.state.scheduleCourses = snapshotToCourses(snapshot);
    this.state.currentWeekCourses = snapshotToCurrentCourses(snapshot);
    this.state.currentCoursesWeek = snapshot.currentWeek;
    // 整学期课表是离线翻周的数据源：登录一次就记住全程，
    // 之后即使登录失效，切到任意周都能本地过滤出正确内容（不会乱序/空白）。
    this.state.termCourses = snapshotToTermCourses(snapshot);
    this.state.grades = snapshotToGrades(snapshot);
    this.state.selectedWeek = snapshot.week;
    this.state.currentWeek = current;
    this.state.cachedAt = snapshot.savedAt;
    // 有会话 → 马上会去刷新，考试列表先等号码一起出来；
    // 没会话（离线看缓存）→ 号码永远不会来，直接放行，别让列表一直转圈
    this.state.examNumbersReady = !this.session.isLoggedIn();
    return true;
  }

  /** 登录页的「先用演示数据看看」 */
  async enterDemo(): Promise<void> {
    this.jw = new FakeJw();
    this.weekToken++;
    this.state.loggedIn = true;
    this.state.demoMode = true;
    this.state.stale = false;
    await this.loadAll();
  }

  onLoginCookies(host: string, cookieHeader: string): void {
    this.session.saveRawCookieHeader(`https://${host}/`, cookieHeader);
    this.jw = this.jwFactory();
  }

  /** 登录成功的唯一可靠判定：拿当前 cookie 真打一次接口 */
  async verifySession(): Promise<boolean> {
    if (!this.session.isLoggedIn()) {
      return false;
    }
    let ok = false;
    try {
      ok = await this.jw.probeSession();
    } catch (e) {
      ok = false;
    }
    if (!ok) {
      return false;
    }
    this.state.loggedIn = true;
    this.state.error = '';
    // loadAll 内部会在成功末尾刷新桌面卡片（见 loadAll 的说明）
    await this.loadAll();
    return true;
  }

  /** 用户关掉登录页但没登录成功：清掉没认证的 cookie */
  async onLoginCancelled(): Promise<void> {
    if (!this.state.loggedIn) {
      await this.session.clear();
      this.jw = this.jwFactory();
    }
  }

  /** 缓存横幅上的「重新登录」 */
  async relogin(): Promise<void> {
    this.weekToken++;
    await this.session.clear();
    this.jw = this.jwFactory();
    // 原地重置，不能整体替换（会断掉 UI 的 @ObjectLink 绑定）
    this.state.reset();
  }

  /**
   * 「重新登录并同步」——设置页按钮的**完整实现**。
   *
   * ## 为什么需要这个（而不是直接调 syncNow）
   *
   * 按钮文案是「重新登录以同步最新数据」，用户点它就是期待
   * **重新登录 + 拿到最新数据** 两件事都发生。
   *
   * 而 `syncNow()` 在没有会话时只会 `backToLogin()` ——
   * 那只是把界面切回登录页并显示一句话，用户还得自己再点一次
   * 「打开教务系统登录（扫码）」。等于按钮只做了一半。
   *
   * ## 现在的行为（名副其实）
   *
   * 1. 清掉旧会话（cookie 过期了留着没意义，还会干扰重新登录）
   * 2. 下一轮渲染会自动显示登录页
   * 3. 通过 `pendingLoginThenSync` 打一个标记：
   *    登录页一挂载就**自动打开扫码**，用户不用再点第二次
   * 4. 登录成功后自动跑一次 `loadAll()` 同步最新数据
   *
   * 若本来就有有效会话，则直接走普通同步，不打断用户。
   */
  async reloginAndSync(): Promise<void> {
    this.weekToken++;
    this.explicitSync = true;

    // 有会话：直接同步，没必要让用户重新登录
    if (this.session.isLoggedIn() && !this.state.stale) {
      this.jw = this.jwFactory();
      await this.loadAll();
      return;
    }

    // 无会话 / 缓存过期：清干净，准备真正的重新登录
    await this.session.clear();
    this.jw = this.jwFactory();
    // 原地重置 UI 状态（不能整体替换，会断掉 @ObjectLink 绑定）
    this.state.reset();
    // 标记：登录页挂载后自动打开扫码，并在成功后自动同步
    this.pendingLoginThenSync = true;
  }

  /**
   * 登录页挂载时调用：若存在「重新登录后同步」的待办，返回 true 并消费标记。
   *
   * LoginScreen 据此自动打开 Web 登录，省掉用户第二次点击。
   */
  consumeAutoLoginFlag(): boolean {
    const flag: boolean = this.pendingLoginThenSync;
    this.pendingLoginThenSync = false;
    return flag;
  }

  /**
   * 设置页的「同步最新课表与成绩」。
   *
   * 静默刷新；如果这次失败是因为会话过期，就直接回到登录页（让用户重新扫码），
   * 而不是像自动加载那样继续挂着缓存 —— 因为是用户主动点的同步，他期待的是最新数据。
   *
   * ⚠️ 注意：「重新登录以同步」那个文案的场景请用 `reloginAndSync()`，
   * 它会真正触发登录流程；本方法只负责「有会话时的同步」。
   */
  async syncNow(): Promise<void> {
    this.weekToken++;
    // 没有会话时 jwFactory() 会返回 FakeJw —— 那样"同步"会悄悄加载演示数据，
    // 界面上却标着"已接入"。宁可回登录页，也不能给假数据。
    if (!this.session.isLoggedIn()) {
      await this.backToLogin('登录已过期，请重新扫码登录');
      return;
    }
    this.jw = this.jwFactory();
    this.explicitSync = true;
    await this.loadAll();
  }

  private async loadAll(): Promise<void> {
    // 非演示模式下没有会话：直接回登录页，避免拿到 FakeJw 的假数据
    if (!this.state.demoMode && !this.session.isLoggedIn()) {
      this.explicitSync = false;
      await this.backToLogin('登录已过期，请重新扫码登录');
      return;
    }

    this.state.loading = true;
    this.state.error = '';
    // 有号码就继续显示（刷新时不能把已有列表藏起来，那是另一种闪烁）
    this.state.examNumbersReady = this.state.examNumbers.size > 0;

    let loaded: WeekLoadResult;
    try {
      // 数据获取在 core/WeekLoader.ets（纯函数，可单测）：
      // 它负责拉 config + 当周 + 必要时拉明日 + 学期代码，
      // 不碰任何状态；本方法只负责「拿到结果后怎么写状态、出错怎么分流」。
      loaded = await loadWeekData(this.jw);
    } catch (e) {
      if (e instanceof SessionExpiredError) {
        if (this.explicitSync) {
          this.explicitSync = false;
          await this.backToLogin(e.message);
        } else {
          await this.onSessionExpired(e.message);
        }
        return;
      }
      // 网络错误：有缓存就继续显示缓存，只是标记为旧
      const hasData = this.state.hasData();
      this.state.loading = false;
      this.state.stale = hasData;
      this.state.error = hasData ? '' : describeError(e);
      // 这一轮不会再有号码了，放行考试列表，别一直转圈
      this.state.examNumbersReady = true;
      return;
    }

    const config: TimetableConfig = loaded.config;
    const courses: Course[] = loaded.courses;
    const nextCourses: Course[] = loaded.nextCourses;
    const current: number = loaded.current;
    const termCode: string = loaded.termCode;

    this.state.loading = false;
    this.state.config = config;
    this.state.scheduleCourses = courses;
    this.state.currentWeekCourses = courses;
    this.state.currentCoursesWeek = current;
    this.state.semesterCode = termCode;
    this.state.nextWeekCourses = nextCourses;
    this.state.currentWeek = current;
    this.state.selectedWeek = current;
    this.state.stale = false;
    this.state.cachedAt = Date.now();
    this.explicitSync = false;

    // 网考号：和考试安排一起就位。先并发发起，等 termCourses 也拿到后一次性更新，
    // 否则考试列表先渲染、号码过一秒再「跳」出来（看着像闪烁）。
    const numbersPromise = this.fetchExamNumbersWithTimeout();

    let term: Course[] | undefined;
    try {
      term = await this.jw.termCourses();
    } catch (e) {
      term = undefined;
    }
    const numbers = await numbersPromise;

    // termCourses 失败时保留上一份，不能把考试列表清空
    //
    // ⚠️ 不能直接 `this.state.termCourses = term` 整体覆盖！
    //
    // 整学期总表**不含 sknrjj（上课内容）**，实测 220 条里仅 43 条有值；
    // 而用户点「补全全部周」后，内存里的 termCourses 已经带有完整内容。
    // 若这里整体替换，补全成果会被这份「没内容」的新数据冲掉 ——
    // 表现为：刚补全时看得见，一同步/重启就全没了。
    //
    // 所以改成**按周合并**：以新拉到的整学期总表为骨架（它可能包含
    // 新增/调整的排课），但已有的 content / room 等富字段要从旧数据继承。
    if (term !== undefined) {
      this.state.termCourses = this.preserveRichFields(this.state.termCourses, term);
    }
    // 首次加载也要做一次合并：
    // `courses` 来自**按周查询**，带 `sknrjj`（上课内容）；
    // 而刚拿到的整学期总表缺这个字段。合并后内容才会落进缓存，
    // 离线看课表时也有内容可显示。
    this.mergeIntoTermCache(current, courses);

    if (numbers.size > 0) {
      this.state.examNumbers = numbers;
    }
    this.state.examNumbersReady = true;

    try {
      const g = await this.jw.grades();
      this.state.grades = g;
      this.state.gradesLoaded = true;
    } catch (e) {
      // 成绩失败不影响课表
    }

    this.persistCache();

    // ⚠️ 同步成功后必须主动让桌面卡片重绘 —— 这是**唯一收口点**。
    //
    // ## 为什么不能只靠 persistCache
    //
    // `persistCache()` 内部只调 `syncWidgetData()`，那只是把新数据
    // **写进 widget_data.json**；桌面上的卡片不会自己重读那个文件，
    // 要等系统每 30 分钟一次的定时刷新才会更新。
    //
    // ## 用户实际踩到的问题
    //
    // 换账号重新登录后，课表页已经显示新课表，**卡片还是旧课程**
    // （实测：课表第 13 周 26 节，卡片仍显示第 12 周周日 + 旧课）。
    //
    // ## 为什么放在这里而不是各调用方
    //
    // 会走到 `loadAll()` 的路径有：启动 bootstrap、登录成功 verifySession、
    // 手动同步 syncNow、重新登录 reloginAndSync、演示数据 enterDemo。
    // 之前是**每个调用方自己**决定要不要 refreshWidgets，
    // 结果 `reloginAndSync` 漏了 —— 这正是上面那个 bug 的成因。
    // 收口到 loadAll 内部，任何新加的同步路径都自动生效。
    await this.refreshWidgets();
  }

  private async fetchExamNumbersWithTimeout(): Promise<Map<string, string>> {
    const timeout = new Promise<Map<string, string>>((resolve) => {
      setTimeout(() => {
        resolve(new Map<string, string>());
      }, EXAM_NUMBERS_TIMEOUT_MS);
    });
    const actual = new Promise<Map<string, string>>((resolve) => {
      this.jw.examNumbers().then((m) => {
        resolve(m);
      }).catch(() => {
        resolve(new Map<string, string>());
      });
    });
    return await Promise.race([actual, timeout]);
  }

  /** 用户主动同步时失败：清掉登录态，直接回登录页 */
  private async backToLogin(message: string): Promise<void> {
    await this.session.clear();
    // 原地重置，不能整体替换（会断掉 UI 的 @ObjectLink 绑定）
    this.state.reset();
    this.state.error = message;
  }

  /**
   * 登录过期时的处理，分两种情况：
   * - 本地有缓存：保留数据，打上 stale 标记，等用户点「重新登录」
   * - 本地没缓存：只能回登录页（否则是一屏空白）
   */
  private async onSessionExpired(message: string): Promise<void> {
    await this.session.clear();
    const hasData = this.state.hasData();
    this.state.loading = false;
    this.state.stale = hasData;
    this.state.loggedIn = hasData || this.state.loggedIn;
    this.state.error = hasData ? '' : message;
    // 会话已失效，这一轮不会再拿到号码；考试列表照常显示（只是没有号码）
    this.state.examNumbersReady = true;
    if (!hasData) {
      this.state.loggedIn = false;
    }
  }

  async selectWeek(week: number): Promise<void> {
    const total = this.state.config !== undefined ? this.state.config.totalWeeks : week;
    const target = Semester.clampWeek(week, total);
    if (target === this.state.selectedWeek) {
      return;
    }
    this.state.selectedWeek = target;
    this.state.weekError = '';
    this.state.weekContentHint = '';
    await this.loadWeek(target);
  }

  async prevWeek(): Promise<void> {
    await this.selectWeek(this.state.selectedWeek - 1);
  }

  async nextWeek(): Promise<void> {
    await this.selectWeek(this.state.selectedWeek + 1);
  }

  /**
   * 用新拉到的整学期总表刷新缓存，同时保留旧数据里的富字段。
   *
   * 实现见 `core/CourseMerge.preserveRichFields`（纯函数，可单测）。
   *
   * ⚠️ 这是「补全内容一同步就丢」这个 bug 的修复点：
   * 整学期总表不含 sknrjj，直接覆盖会把补全成果冲掉。
   */
  private preserveRichFields(old: Course[], fresh: Course[]): Course[] {
    return preserveRichFields(old, fresh);
  }

  private async loadWeek(week: number): Promise<void> {
    // 请求序号：连点切周时，旧响应到达后要能识别并丢弃
    this.weekToken++;
    const myToken = this.weekToken;

    this.state.loading = true;
    this.state.error = '';

    // ① 先用本地整学期缓存渲染，秒开、且断网/登录失效时也能翻周
    const offline = this.offlineCoursesForWeek(week);
    if (offline.length > 0) {
      this.state.scheduleCourses = offline;
      this.state.loading = false;
      this.state.weekError = '';
      // 有本地数据就不必等网络；但若还有会话，仍去后台拉最新（下面继续）
      if (!this.session.isLoggedIn()) {
        this.state.stale = true;
        // ⚠️ 离线且本周课程缺上课内容时，标记一个**轻量提示**。
        //
        // 绝不能写进 weekError —— 那会让课表整块被错误页替换
        // （实测把整周网格都挤没了，课程看不见）。
        //
        // 背景：教务的 sknrjj（上课内容）**只有按周查询才返回**，
        // 整学期总表里 220 条仅 43 条有值。所以没联网拉过的那几周，
        // 课表只有课名和教室，看起来像"内容丢了"——其实是没拉过。
        this.state.weekContentHint = this.weekMissingContent(offline)
          ? '本周部分课程缺少上课内容，重新登录同步后可补全'
          : '';
        return;
      }
      // 在线时不显示该提示（马上就会联网补内容）
      this.state.weekContentHint = '';
    }

    // ② 没有本地数据，或仍有会话 → 联网拿这一周的最新数据
    try {
      const courses = await this.jw.timetable(week);
      if (myToken !== this.weekToken) {
        return; // 已被更新的请求取代
      }
      this.state.scheduleCourses = courses;
      this.state.loading = false;
      this.state.stale = false;
      this.state.weekError = '';
      // 把这一周并进整学期缓存，下次断网也能看
      this.mergeIntoTermCache(week, courses);
      this.persistCache();
    } catch (e) {
      if (myToken !== this.weekToken) {
        return;
      }
      if (e instanceof SessionExpiredError) {
        // 会话失效：只要本地有这一周的数据，就继续展示，只是打上「缓存」标记
        if (offline.length > 0) {
          this.state.scheduleCourses = offline;
          this.state.loading = false;
          this.state.stale = true;
          this.state.weekError = '';
          await this.onSessionExpired(e.message);
          return;
        }
        await this.onSessionExpired(e.message);
        return;
      }
      // 关键：失败不能表现成「该周 0 节」，否则用户会以为这周没课
      this.state.loading = false;
      if (offline.length > 0) {
        // 有本地数据就继续显示，不报错打断用户
        this.state.scheduleCourses = offline;
        this.state.stale = true;
        this.state.weekError = '';
      } else {
        this.state.weekError = describeError(e);
      }
    }
  }

  /**
   * 从**本地整学期缓存**里取出某一周的课。
   *
   * 这是「登录一次后记忆整学期课表」的基础：
   * 只要 `termCourses` 里有这一周的课，翻周就完全不需要网络。
   *
   * ⚠️ 注意源数据的两处差异：
   * - 整学期总表里的 `weeks` 是「这一行出现在哪几周」（可能多周），
   *   所以过滤条件是 `weeks 包含 week`，而不是等于；
   * - 但 UI 需要的是「这一周有哪些课」，两者语义一致，可以直接用。
   */
  private offlineCoursesForWeek(week: number): Course[] {
    const out: Course[] = [];
    for (const c of this.state.termCourses) {
      if (c.weeks.indexOf(week) >= 0) {
        // 拷贝一份并把 weeks 收窄成当前周，避免上游误用
        const copy: Course = {
          id: c.id,
          name: c.name,
          teacher: c.teacher,
          room: c.room,
          dayOfWeek: c.dayOfWeek,
          startSection: c.startSection,
          endSection: c.endSection,
          weeks: c.weeks,
          content: c.content,
          date: c.date,
          timeLabel: c.timeLabel,
          colorHex: c.colorHex,
          isSelfStudy: c.isSelfStudy,
          isExam: c.isExam
        };
        out.push(copy);
      }
    }
    return out;
  }

  /**
   * 把刚拉到的某一周课程并进 `termCourses`（整学期缓存）。
   *
   * 目的：**只要联网成功过一次某周，这一周就被永久记住**；
   * 同时把「按周查询才有」的字段（尤其**上课内容 `sknrjj`**）
   * 补进整学期数据，这样离线看课表也有内容。
   *
   * ## 为什么不能用 id 去重（原实现的 bug）
   *
   * 实测两种查询返回的 id **形态完全不同**：
   * - 整学期总表：`100037_TMP849_3_10_4`（用教务的课程码）
   * - 按周查询：`103868440_W117202601001_6_4_11`（另一种编码）
   *
   * 所以 `freshIds.has(c.id)` 永远匹配不上 → 旧条目不会被替换，
   * 新条目又被 append → **同一节课在缓存里出现两次**。
   *
   * ## 现在的匹配方式
   *
   * 用**业务键**（课程名 + 星期 + 起止节）定位同一节课，
   * 并且要求旧条目的 `weeks` 覆盖本次查询的周次。
   *
   * ## 安全性
   *
   * 这里**不做删除**：宁可多留一条旧数据，也不冒险误删用户课表。
   * 课程真的被教务删掉时，它只会作为历史数据留着，不影响显示
   * （按周过滤时若本学期没有它，就不会出现在任何一周）。
   */
  private mergeIntoTermCache(week: number, fresh: Course[]): void {
    if (fresh.length === 0) {
      return;
    }
    // 实际合并逻辑见 core/CourseMerge.ets（纯函数，有单测覆盖）
    this.state.termCourses = mergeWeekIntoTerm(this.state.termCourses, fresh, week);
  }

  /**
   * 用按周数据补全整学期条目的字段。
   *
   * 实现已移到 `core/CourseMerge.enrichCourse`（纯函数，可单测）。
   */
  private enrichCourse(base: Course, fresh: Course): Course {
    return enrichCourse(base, fresh);
  }

  /** 取第一个非空文本 */
  private pickText(a: string | undefined, b: string | undefined): string | undefined {
    return pickText(a, b);
  }


  /**
   * 把当前状态写入本地缓存。
   *
   * @param allowWithoutSession 允许在没有登录态时也写盘。
   *
   * ⚠️ 为什么需要这个开关：
   * 默认情况下「没有会话就不写盘」是安全的 —— 没会话时数据可能来自
   * FakeJw（演示数据），写进去会污染缓存。
   *
   * 但**补全全部周内容**的场景不同：补全过程中会话可能刚好过期，
   * 而已经拉到的那些周的 content 是**真实数据、非常宝贵**
   * （用户等了几十秒）。若此时因「无会话」直接 return，
   * 整轮补全成果全部丢失 —— 这正是「补全后离线又看不到内容」的成因之一。
   *
   * 所以补全路径显式传 `true`：数据来自真实接口，必须落盘。
   */
  private persistCache(allowWithoutSession: boolean = false): void {
    const s = this.state;
    const config = s.config;
    if (config === undefined) {
      return;
    }
    if (s.demoMode) {
      return; // 演示数据不要污染缓存
    }
    if (!allowWithoutSession && !this.session.isLoggedIn()) {
      return; // 没会话时拿到的可能是 FakeJw，更不能缓存
    }

    // 这次没拉到成绩（请求失败）→ 沿用上一份缓存，别把已有成绩冲成空
    let grades = s.grades;
    if (!s.gradesLoaded) {
      const old = this.cache.load();
      if (old !== undefined) {
        grades = snapshotToGrades(old);
      }
    }

    this.cache.save(
      makeSnapshot(
        config,
        s.scheduleWeekCourses(),
        s.currentWeekCourses,
        grades,
        s.upcomingExams(),
        s.selectedWeek,
        s.currentWeek,
        Date.now(),
        // 整学期课表全量落盘：登录一次就记住整个学期，
        // 登录失效后翻任意周都能本地还原，不会内容错乱。
        s.termCourses
      )
    );

    // 同步更新桌面卡片的数据文件。
    // 卡片运行在独立的 FormExtensionAbility 里、不能自己联网，
    // 所以应用每次持久化时把「今明两天的课」写一份给它。
    this.syncWidgetData();
  }

  /**
   * 把「今明两天的课」写入卡片数据文件。
   *
   * 失败不影响主流程（卡片是附加功能）。
   */
  private syncWidgetData(): void {
    try {
      const snap = this.state.buildWidgetSnapshot();
      saveWidgetSnapshot(this.filesDir, snap);
    } catch (e) {
      // 忽略：卡片数据写失败不应该影响 App
    }
  }

  /**
   * 主动刷新卡片显示。
   *
   * 应用在前台改动了数据（比如手动同步）时，除了写文件，
   * 还要让已添加到桌面的卡片立即重绘 —— 否则用户要等下一次
   * 定时刷新（30 分钟）才能看到新内容。
   *
   * 实现上用 `formProvider.reloadForms`：
   * 它会通知系统去重新拉起这些卡片的 `onUpdateForm`，
   * **不需要**我们自己枚举 formId（App 侧本来就拿不到运行中的 formId，
   * 那只有 FormExtensionAbility 在其回调里能收到）。
   *
   * 失败一律忽略：卡片是附加功能，不能影响主流程。
   */
  async refreshWidgets(): Promise<void> {
    // 先把最新数据落到文件，卡片被拉起时读到的是新数据
    this.syncWidgetData();
    try {
      const n = await formProvider.reloadForms(
        this.abilityContext,
        WIDGET_MODULE_NAME,
        WIDGET_ABILITY_NAME,
        WIDGET_FORM_NAME
      );
      hilog.info(0x0001, 'SmuPocketWidget', 'reloadForms ok, count=%{public}d', n);
    } catch (e) {
      // 没有卡片在桌面、或系统不允许时都会抛，属正常情况
      const err = e as BusinessError;
      hilog.warn(0x0001, 'SmuPocketWidget', 'reloadForms failed: %{public}s',
        err !== undefined && err.message !== undefined ? err.message : 'unknown');
    }
  }

  async logout(): Promise<void> {
    this.weekToken++;
    await this.session.clear();
    this.cache.clear();
    this.jw = this.jwFactory();
    // 原地重置，不能整体替换（会断掉 UI 的 @ObjectLink 绑定）
    this.state.reset();
  }

  /**
   * 本周课程是否缺上课内容（sknrjj）。
   *
   * 实现见 `core/CourseMerge.weekMissingContent`（纯函数，可单测）。
   */
  private weekMissingContent(courses: Course[]): boolean {
    return weekMissingContent(courses);
  }

  /**
   * 补全**全部周**的上课内容（sknrjj）。
   *
   * ## 为什么需要这个
   *
   * 教务的两个接口能力不对等：
   *
   * | 接口 | 覆盖周次 | 是否带 sknrjj（上课内容） |
   * |------|----------|--------------------------|
   * | 整学期总表（zc 为空） | 全部 20 周 | ❌ 220 条里仅 43 条有值 |
   * | 按周查询（zc=N）      | 只有第 N 周 | ✅ 当周全带 |
   *
   * 所以离线翻到没查过的周时，课程只有课名和教室，没有上课内容。
   *
   * ## 做法
   *
   * 逐周调用 `timetable(week)`，把返回的富字段合并进整学期缓存。
   * - 每拉完一周**立即合并并落盘**，中途失败也不丢已拉到的；
   * - 已有 content 的条目**跳过不重复拉**（省钱、省时间）；
   * - 全部失败也不抛错，只在结果里如实报告成功周数。
   *
   * ## 开销
   *
   * 一学期 20 周 = 最多 20 次请求。教务接口单次约 0.3–1 秒，
   * 所以整体约 10–20 秒，期间会持续更新进度回调。
   *
   * @param onProgress 进度回调 (已完成周数, 总周数)
   * @returns 实际补全的周数
   */
  async fillAllWeekContents(
    onProgress?: (done: number, total: number) => void
  ): Promise<number> {
    const config = this.state.config;
    if (config === undefined) {
      return 0;
    }
    if (!this.session.isLoggedIn()) {
      return 0;
    }

    const total: number = config.totalWeeks;
    if (total <= 0) {
      return 0;
    }

    // 找出「需要按周数据修正」的周
    //
    // 两种情形都算需要（见 CourseMerge.weekNeedsWeeklySync）：
    // 1. 缺上课内容
    // 2. room 是整学期总表的多教室拼接值（如 "207教室,403教室,408教室,604教室"），
    //    需要替换成当周精确教室（如 "604教室"）
    const missing: number[] = [];
    for (let w = 1; w <= total; w++) {
      const weekCourses = this.offlineCoursesForWeek(w);
      if (weekCourses.length > 0 && weekNeedsWeeklySync(weekCourses)) {
        missing.push(w);
      }
    }
    if (missing.length === 0) {
      onProgress?.(total, total);
      return 0;
    }

    let done: number = 0;
    let filledWeeks: number = 0;

    for (let i = 0; i < missing.length; i++) {
      const w: number = missing[i];
      try {
        const courses: Course[] = await this.jw.timetable(w);
        if (courses.length > 0) {
          // 合并进整学期缓存（内部会按业务键匹配、只补空字段）
          this.mergeIntoTermCache(w, courses);
          filledWeeks++;
        }
      } catch (e) {
        // 单周失败不影响其它周，继续下一个
        if (e instanceof SessionExpiredError) {
          // 会话失效就没必要再试了，直接停
          break;
        }
      }
      done++;
      onProgress?.(done, missing.length);
      // 每次合并后落盘：中途退出也不会白干。
      //
      // ⚠️ 传 true：补全过程中会话可能刚好过期，但已拉到的内容是真实数据，
      // 绝不能因「无会话」而丢弃（否则用户等了几十秒全白费）。
      this.persistCache(true);
    }

    // 重新载入当前选中周，让 UI 立刻反映新内容
    if (filledWeeks > 0) {
      await this.loadWeek(this.state.selectedWeek);
      // ⚠️ 收尾再存一次：循环里已逐周 persistCache，
      // 但 loadWeek 可能改动 scheduleCourses 等字段，
      // 这里补一次确保「补全成果 + 当前视图」整体落盘，
      // 避免用户补全后立刻杀进程导致最后一次改动丢失。
      this.persistCache(true);
      this.syncWidgetData();
    }
    return filledWeeks;
  }
}

/** 把异常转成给用户看的话 */
function describeError(e: Object): string {
  if (e instanceof Error) {
    const msg = e.message;
    if (msg !== undefined && msg.length > 0) {
      return msg;
    }
  }
  return '加载失败，请检查网络后重试';
}
