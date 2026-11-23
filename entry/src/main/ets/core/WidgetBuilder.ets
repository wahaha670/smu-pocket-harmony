/**
 * 卡片数据构建（纯函数）。
 *
 * ## 为什么从 AppViewModel 里抽出来
 *
 * 基线版本 v1.5.0 的 `AppViewModel.ets` 有 **1513 行 / 60+ 方法**，
 * 同时负责：会话生命周期、缓存读写、课表合并、颜色分配、卡片数据构建。
 * 其中「把课程转成卡片条目」这 5 个方法（113 行）**只做数据变换、
 * 不碰任何状态**，是典型的可抽出部分。
 *
 * 抽出的好处：
 * 1. 这层逻辑可以用 Node 直接单测（不需要 ArkUI 运行时）；
 * 2. AppViewModel 少一块职责，可读性提升；
 * 3. 卡片渲染的字段约定集中在一处，改卡片只改这里。
 *
 * ## 设计原则
 *
 * 全部是**纯函数**：输入相同 → 输出相同，不读全局状态、不写文件。
 * 依赖的外部信息（作息表、颜色映射）通过参数传入。
 */
import { Course, Period } from './Models';
import { WidgetCourse } from './WidgetData';
import { courseColor } from './CourseColors';

/**
 * 课程 → 卡片条目。
 *
 * @param list 课程列表
 * @param colors 课程名 → 颜色映射（由调用方的 courseColorMap 提供）
 * @param periods 作息表；为空时时间退化成「第 N 节」
 */
export function toWidgetCourses(
  list: Course[],
  colors: Map<string, string>,
  periods: Period[]
): WidgetCourse[] {
  const out: WidgetCourse[] = [];
  for (const c of list) {
    out.push({
      name: c.name,
      time: widgetTime(c, periods),
      room: c.isSelfStudy === true ? '自主学习' : (c.room !== undefined ? c.room : ''),
      color: courseColor(c.name, colors),
      // 老师与上课内容：卡片上要一起展示，所以一并带过去。
      // 内容字段（sknrjj）只有按周查询才有，整学期缓存里可能为空。
      teacher: c.teacher !== undefined ? c.teacher : '',
      content: c.content !== undefined ? c.content : ''
    });
  }
  return out;
}

/**
 * 卡片上显示的时间文本。
 *
 * 三层兜底，保证卡片上不会出现空白：
 * 1. 教务给的真实时刻（`qssj-jssj`）—— 最准
 * 2. 本地作息表按节次查
 * 3. 退化成「第 N 节」
 */
export function widgetTime(c: Course, periods: Period[]): string {
  const label = c.timeLabel;
  if (label !== undefined && label.length > 0) {
    return label;
  }
  for (const p of periods) {
    if (p.index === c.startSection) {
      return p.start;
    }
  }
  return `第${c.startSection}节`;
}

/**
 * 从整学期课表 + 额外的当日课程收集课程名，分配给独立颜色。
 *
 * 与课表页共用 `CourseColors` 的分配算法（哈希 + 冲突探测），
 * 保证**卡片上的色点与课表页的色块颜色一致**。
 *
 * @param termCourses 整学期课表
 * @param extraCourses 额外要纳入的课程（今日/明日的课可能还没并进 termCourses）
 * @param assign 颜色分配函数（由调用方传入，避免本模块依赖颜色算法实现）
 */
export function collectCourseColors(
  termCourses: Course[],
  extraCourses: Course[],
  assign: (names: string[]) => Map<string, string>
): Map<string, string> {
  const names: string[] = [];
  const seen = new Set<string>();
  const add = (c: Course): void => {
    const n = c.name.trim();
    if (n.length > 0 && !seen.has(n)) {
      seen.add(n);
      names.push(n);
    }
  };
  for (const c of termCourses) {
    add(c);
  }
  // ⚠️ 不能省这一步：今日/明日的课可能还没并进 termCourses，
  //    漏掉它们会导致这些课的颜色与课表页不一致。
  for (const c of extraCourses) {
    add(c);
  }
  return assign(names);
}
