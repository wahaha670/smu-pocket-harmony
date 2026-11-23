/**
 * 「一次性加载当前周 + 明日」的纯函数。
 *
 * ## 为什么从 loadAll() 里抽出来
 *
 * 基线 v1.5.0 的 `loadAll()` 有 125 行，同时做三件事：
 *   1. 会话检查（没有会话直接回登录页）
 *   2. 错误处理（SessionExpiredError / 网络错误 / 其它异常）
 *   3. **数据获取**（拉 config + 当周 + 必要时拉明日 + 学期代码）
 *
 * 第 3 块是**纯计算**，和 ArkUI 状态无关，所以抽出来：
 * - 可以用 Node 直接单测（不需要真实教务、不需要设备）；
 * - loadAll() 只负责「状态机」（成功 → 写状态、失败 → 分流错误），
 *   层次清楚；
 * - 「周日要额外拉明日」这条业务规则有独立测试覆盖。
 *
 * ## 返回值
 *
 * 用 `LoadResult` 显式区分「拿到数据」和「未拿到」，
 * 调用方据此决定是渲染新数据还是回退缓存。
 */
import { Course, TimetableConfig } from './Models';
import { Semester } from './Semester';
import { addDays, todayStart } from './DateUtils';
import { JwService } from '../data/RealJw';

/**
 * 教务数据源类型。
 *
 * ⚠️ 这里**不用接口** `WeekDataSource` —— ArkTS 不支持结构化类型
 * （`arkts-no-structural-typing`），把 JwService 赋给接口变量会编译失败。
 * 参数直接用 `JwService` 类，它是完整的真实类型，包含全部所需方法。
 */

/** 一次加载的结果 */
export interface WeekLoadResult {
  config: TimetableConfig;
  /** 当周课程 */
  courses: Course[];
  /** 明日课程（仅当明天跨周时才有值，否则为空数组） */
  nextCourses: Course[];
  /** 当前周次 */
  current: number;
  /** 学期代码（失败时为空串） */
  termCode: string;
}

/**
 * 拉取「当前周课表 + 明日课表 + 学期配置」。
 *
 * @param jw 数据源（真实教务或 FakeJw，由调用方决定）
 * @returns 所有原始数据；**不修改任何状态**，由调用方负责写入
 * @throws 原样抛出数据源异常（SessionExpiredError / 网络错误等），
 *        由调用方决定如何展示 —— 这样错误分流逻辑留在上层，
 *        纯函数本身保持简单
 */
export async function loadWeekData(jw: JwService): Promise<WeekLoadResult> {
  const config: TimetableConfig = await jw.timetableConfig();
  const current: number = Semester.clampWeek(
    Semester.weekOf(todayStart(), config.firstMonday),
    config.totalWeeks
  );
  const courses: Course[] = await jw.timetable(current);

  // ⚠️ 边界：今天是周日 → 明天属于下一周，必须单独拉一次
  //
  // 为什么单独拉：`timetable(current)` 只覆盖本周；
  // 周日 23:00 看「明日课程」时，明天的课在第 current+1 周，
  // 不单独拉就会显示「明日无课」的假空。
  const tomorrowWeek: number = Semester.clampWeek(
    Semester.weekOf(addDays(todayStart(), 1), config.firstMonday),
    config.totalWeeks
  );
  let nextCourses: Course[] = [];
  if (tomorrowWeek !== current) {
    try {
      nextCourses = await jw.timetable(tomorrowWeek);
    } catch (e) {
      // 明日拉取失败不是致命错误：保留空数组，让「明日」区块显示空
      nextCourses = [];
    }
  }

  // 学期代码失败同样不致命：设置页显示「—」即可
  let termCode = '';
  try {
    const code = await jw.semesterCode();
    termCode = code !== undefined ? code : '';
  } catch (e) {
    termCode = '';
  }

  return {
    config,
    courses,
    nextCourses,
    current,
    termCode,
  };
}
