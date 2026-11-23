/**
 * 课表页。
 *
 * 关键设计（必须保留，都是原版踩坑换来的）：
 *
 * 1. **永远固定渲染 14 行**，哪怕这一周 11~14 节完全没课。
 *    行数不跟 config.periods 走，所以旧缓存（只有 10 条作息）也不会把晚课截掉。
 * 2. **跨节课程合并成一整块**：4 节课的课程是一整块色块，
 *    而不是「一格有色 + 三格空白」。
 * 3. **左侧节次列和 7 天网格在同一个滚动容器里**，
 *    上下滑动时数字和色块始终对得齐。
 * 4. **加载失败不能说「该周 0 节」** —— 那会让用户以为这周真的没课。
 *
 * 移植自 Android 版 ui/schedule/ScheduleScreen.kt。
 */
import { Course, TOTAL_SECTIONS } from '../../core/Models';
import { Theme } from '../../theme/Theme';
import { AppState } from '../../core/AppViewModel';
import { dayOfMonth, monthOf, todayStart } from '../../core/DateUtils';
import { assignCourseColors, courseColor, COURSE_PALETTE, stableHash } from '../../core/CourseColors';
import { DefaultPeriods } from '../../core/Periods';
import { FontSize } from '../../theme/Typography';
// 课表格子已拆到独立文件（见 CourseCellView.ets 文件头的拆分原因）
import { CourseCellView } from './CourseCellView';

/**
 * 一节课的基础高度（vp）。
 *
 * 这是「最小高度」：在长屏机型（如 Mate 80 Pro Max，1320×2848，比例 2.16）
 * 上会把多余高度均摊给每一节，让课表更舒展、看得更清楚；
 * 在矮屏机型（比例 1.7 左右）上则维持这个基准，靠滚动查看全部 14 节。
 *
 * 实际高度由 cellHeight 在每次布局时按可用高度算出。
 */
const CELL_HEIGHT_BASE: number = 62;
const TIME_COL_WIDTH: number = 26;

/** 14 节课的固定行数 */
const SECTIONS: number = 14;

/**
 * 课程色块调色板。
 *
 * 选取原则：
 * - **色相分散**：蓝/绿/橙/红/紫/青/棕/玫红/靛/蓝绿/褐/黄绿/洋红…，
 *   相邻两色在视觉上能立刻区分；
 * - **明度适中偏深**：保证白字可读（`Theme.onCourseColor` 会自动判明暗，
 *   亮色配深字、深色配白字，所以这里不必拘泥于深浅，但整组统一更耐看）；
 * - **不刺眼**：饱和度控制在中档，长时间看课表不累。
 *
 * 14 色可容纳 14 门不同课程；超过时循环使用（哈希取模），
 * 实测本人课表 11 门课 → 每门颜色都不同。
 */


/**
 * 字符串的确定性哈希（FNV-1a 变体）。
 *
 * 要求：**同样的输入永远得到同样的值**（跨进程、跨设备一致），
 * 这样同一门课的颜色不会因为重启 App 而变化。
 *
 * 注意不要用 `Math.random()` 或对象遍历顺序之类的非确定因素。
 */

/** 一个格子的描述 */
interface GridCell {
  /** undefined 表示空格子 */
  course: Course | null;
  /** 占几节的高度 */
  span: number;
  section: number;
}

/** 星期表头的一项：星期几 + 该天日期 + 状态标记 */
interface DayHeaderItem {
  /** "一".."日" */
  label: string;
  /** 日期数字，如 "13"；拿不到日期时为空串 */
  dayText: string;
  isToday: boolean;
  /** 是否周末（六、日） */
  isWeekend: boolean;
  /** 该天是否跨月（月份 ≠ 本周标题月份） */
  crossMonth: boolean;
}

@Component
export struct ScheduleScreen {
  @ObjectLink state: AppState;
  @Prop isDark: boolean = false;

  /** 由父组件注入 */
  onSelectWeek: (week: number) => void = () => {};
  onPrevWeek: () => void = () => {};
  onNextWeek: () => void = () => {};

  /**
   * 课表网格的可用高度（vp），由 onAreaChange 测出来。
   *
   * 用途：把「屏幕高出来的那部分」均摊到 14 节上。
   * 例：Mate 80 Pro Max 上可用约 620vp，620/14≈44，低于基准 62，
   * 所以仍用 62（靠滚动）；而在更长的屏上若 620 足够，就取更大值让格子更舒展。
   *
   * 初值 0 表示「还没测到」，此时用基准高度。
   */
  @State gridAreaHeight: number = 0;

  /**
   * 当前正在查看详情的课程；null 表示没有选中。
   *
   * ⚠️ 不能用它直接控制 bindSheet：
   * bindSheet 的签名是 `bindSheet(isShow: boolean, ...)`，
   * 只接受布尔值，传 `Course | null` 会**静默失效**（弹层永远不出现，
   * 也没有任何报错）。所以另设 showDetail 布尔字段控制显隐。
   */
  @State detailCourse: Course | null = null;
  /** 详情弹层是否显示（bindSheet 要求布尔值） */
  @State showDetail: boolean = false;

  /** 「课程名 → 颜色」映射缓存（见 buildColorMap） */
  private colorMapCache: Map<string, string> = new Map<string, string>();
  /** 缓存对应的课程数量，用来判断是否需要重算 */
  private colorMapKey: number = -1;

  /**
   * 单节高度。
   *
   * 规则：
   * - 若可用高度能让 14 节都放下（含一点余量），就均摊，让课表铺满屏幕；
   * - 否则用基准高度，超出部分靠滚动。
   * - 上限 96vp，避免极长屏把格子拉得过于空旷。
   */
  private cellHeight(): number {
    if (this.gridAreaHeight <= 0) {
      return CELL_HEIGHT_BASE;
    }
    // 留 8vp 余量，避免刚好卡满导致最后一行被裁
    const fit = (this.gridAreaHeight - 8) / SECTIONS;
    if (fit <= CELL_HEIGHT_BASE) {
      return CELL_HEIGHT_BASE;
    }
    return Math.min(fit, 96);
  }

  build() {
    Column() {
      // 标题：加载失败时别说「该周 0 节」，那是骗人的
      Column() {
        Text(this.titleText())
          .fontSize(FontSize.headlineLarge)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.colors(this.isDark).onSurface)
        Text(this.subtitleText())
          .fontSize(FontSize.smallBody)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .margin({ top: 3 })
          .maxLines(2)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 16, bottom: 10 })

      if (this.state.config === undefined) {
        Text('还没有课表数据，请先登录')
          .fontSize(FontSize.body)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding(24)
      } else {
        this.WeekStrip()

        // 轻量提示：本周部分课程缺少上课内容（离线且未拉取过该周时出现）
        //
        // ⚠️ 刻意**不用 weekError**：那会让下面整块课表被错误页替换、
        //    课程网格直接消失。这里只是一行小字，不影响网格渲染。
        if (this.state.weekContentHint.length > 0) {
          Text(this.state.weekContentHint)
            .fontSize(FontSize.small)
            .fontColor(Theme.colors(this.isDark).warning)
            .width('100%')
            .padding({ left: 12, right: 12, top: 2, bottom: 2 })
            .maxLines(2)
        }

        if (this.state.weekError.length > 0) {
          Column() {
            Text(`第 ${this.state.selectedWeek} 周加载失败`)
              .fontSize(FontSize.bodyStrong)
              .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
            Text(this.state.weekError)
              .fontSize(FontSize.smallBody)
              .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
              .margin({ top: 6 })
              .textAlign(TextAlign.Center)
            Text('检查网络后，重新点一下这一周')
              .fontSize(FontSize.smallBody)
              .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
              .margin({ top: 6 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 32, right: 32 })
        } else {
          this.DayHeader()
          this.TimetableGrid()
        }

        this.WeekNav()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.colors(this.isDark).background)
  }

  /**
   * 大标题：`第 N 周 · M月`
   *
   * 月份取**该周周一所在的月份**。这样跨月的周（例如周一在 10/30、周日在 11/5），
   * 标题显示前一个月份（10月），而下方各天的日期照常显示自己的日。
   */
  private titleText(): string {
    const month = this.state.selectedWeekTitleMonth();
    if (month <= 0) {
      return `第 ${this.state.selectedWeek} 周`;
    }
    return `第 ${this.state.selectedWeek} 周 · ${month}月`;
  }

  private subtitleText(): string {
    const cfg = this.state.config;
    if (cfg === undefined) {
      return '尚未连接到教务系统';
    }
    const tail = this.state.weekError.length > 0 ? '加载失败' : `该周 ${this.state.selectedWeekTotal()} 节`;
    // 正在看本地缓存时明确标出来：数据是对的，但可能不是最新的
    const cacheTag = this.state.stale ? ' · 离线缓存' : '';
    return `${cfg.termName} · 共 ${cfg.totalWeeks} 周 · ${tail}${cacheTag}`;
  }

  // ---- 周次横向条 ----
  @Builder
  WeekStrip() {
    Scroll() {
      Row() {
        ForEach(this.weekList(), (week: number) => {
          Text(week === this.state.currentWeek ? `${week}·今` : `${week}`)
            .fontSize(FontSize.smallBody)
            .fontColor(week === this.state.selectedWeek
              ? Theme.colors(this.isDark).onPrimary
              : Theme.colors(this.isDark).onSurface)
            .padding({ left: 11, right: 11, top: 5, bottom: 5 })
            .backgroundColor(week === this.state.selectedWeek
              ? Theme.colors(this.isDark).primary
              : Theme.colors(this.isDark).surfaceVariant)
            .borderRadius(14)
            .margin({ right: 6 })
            .onClick(() => {
              this.onSelectWeek(week);
            })
        }, (week: number) => `week_${week}`)
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  private weekList(): number[] {
    const total = this.state.config?.totalWeeks ?? 0;
    const out: number[] = [];
    for (let i = 1; i <= total; i++) {
      out.push(i);
    }
    return out;
  }

  // ---- 星期表头（含日期） ----
  /**
   * 表头两行：上排「一 二 三 四 五 六 日」，下排对应日期数字。
   *
   * 视觉规则：
   * - 今天：日期换成**实心圆底 + 白字**，一眼能找到今天；
   * - 跨月的那天（该天月份 ≠ 本周标题月份）：日期右上角加一个小圆点提示；
   * - 周末（六/日）的星期字用略淡的颜色，和平时区分。
   *
   * 日期与左侧节次列共用同一套宽度对齐：左侧留 TIME_COL_WIDTH 占位。
   */
  @Builder
  DayHeader() {
    Column() {
      Row() {
        Blank().width(TIME_COL_WIDTH)
        ForEach(this.dayHeaders(), (item: DayHeaderItem, idx: number) => {
          Column() {
            // 星期几
            Text(item.label)
              .fontSize(FontSize.small)
              .fontColor(item.isToday
                ? Theme.colors(this.isDark).primary
                : (item.isWeekend
                  ? Theme.colors(this.isDark).onSurfaceVariant
                  : Theme.colors(this.isDark).onSurfaceVariant))
              .fontWeight(item.isToday ? FontWeight.Medium : FontWeight.Normal)

            // 日期：今天用实心圆底
            Stack() {
              if (item.isToday) {
                Row()
                  .width(24)
                  .height(24)
                  .borderRadius(12)
                  .backgroundColor(Theme.colors(this.isDark).primary)
              }
              Text(item.dayText)
                .fontSize(item.isToday ? 12 : 12)
                .fontWeight(item.isToday ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(item.isToday
                  ? Theme.colors(this.isDark).onPrimary
                  : Theme.colors(this.isDark).onSurface)
            }
            .width(24)
            .height(24)
            .alignContent(Alignment.Center)
            .margin({ top: 2 })

            // 跨月提示小圆点
            Row()
              .width(4)
              .height(4)
              .borderRadius(2)
              .backgroundColor(item.crossMonth
                ? Theme.colors(this.isDark).primary
                : Color.Transparent)
              .margin({ top: 1 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)
        }, (item: DayHeaderItem, idx: number) => `day_${item.label}_${item.dayText}`)
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 4, bottom: 2 })
      .alignItems(VerticalAlign.Center)

      // 表头与网格的分隔线
      Divider()
        .color(Theme.colors(this.isDark).outline)
        .margin({ left: 8, right: 8, top: 2, bottom: 4 })
    }
    .width('100%')
  }

  /**
   * 构造表头的 7 项：星期 label + 日期数字 + 是否今天 + 是否跨月。
   *
   * 拿不到日期时（未登录 / 无 config），dayText 留空，
   * 表头仍然显示「一二三…」，不会因为缺数据而消失。
   */
  private dayHeaders(): DayHeaderItem[] {
    const labels: string[] = ['一', '二', '三', '四', '五', '六', '日'];
    const dates = this.state.selectedWeekDates();
    const today = todayStart();
    // 本周标题所用月份（周一所在月），用来判断哪些天跨月
    const titleMonth = this.state.selectedWeekTitleMonth();
    const out: DayHeaderItem[] = [];
    for (let i = 0; i < 7; i++) {
      let dayText = '';
      let isToday = false;
      let crossMonth = false;
      if (i < dates.length) {
        const d = dates[i];
        dayText = `${dayOfMonth(d)}`;
        isToday = d === today;
        if (titleMonth > 0) {
          crossMonth = monthOf(d) !== titleMonth;
        }
      }
      out.push({
        label: labels[i],
        dayText: dayText,
        isToday: isToday,
        isWeekend: i >= 5,
        crossMonth: crossMonth
      });
    }
    return out;
  }

  // ---- 课表网格 ----
  @Builder
  TimetableGrid() {
    Scroll() {
      Row() {
        // 左列只显示纯数字 1..14，不显示具体时刻
        Column() {
          ForEach(this.sectionList(), (index: number) => {
            Row() {
              Text(`${index}`)
                .fontSize(FontSize.caption)
                .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
            }
            .width('100%')
            .height(this.cellHeight())
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Top)
            .padding({ top: 4 })
          }, (index: number) => `sec_${index}_${this.cellHeight()}`)
        }
        .width(TIME_COL_WIDTH)

        // 7 天，每天一个 Column；跨节课程渲染成 span * 单节高度 的色块
        ForEach(this.days(), (day: number) => {
          Column() {
            // ⚠️ 键必须包含「课程内容标识」，不能只用 「星期_序号」：
            // 切周时格子数量/内容会变，但星期和序号不变，
            // ArkUI 会认为「键相同 = 同一批组件」而直接复用旧节点，
            // 表现为：标题和「该周 N 节」都更新了，网格却一动不动。
            // 所以键里带上课程 id 与跨度；空格子带上它所在的节次。
            // 另外键里也带上单节高度：屏幕尺寸变化时也要重建。
            ForEach(this.cellsOfDay(day), (cell: GridCell, idx: number) => {
              if (cell.course !== null) {
                this.CourseCell(cell.course, this.cellHeight() * cell.span)
              } else {
                Row()
                  .width('100%')
                  .height(this.cellHeight())
                  .padding(1)
                  .borderRadius(6)
                  .backgroundColor(Theme.colors(this.isDark).surfaceVariant)
                  .opacity(0.25)
              }
            }, (cell: GridCell, idx: number) => `${this.cellKey(day, cell, idx)}_h${this.cellHeight()}`)
          }
          .layoutWeight(1)
        }, (day: number) => `col_${day}`)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ left: 8, right: 8 })
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .layoutWeight(1)
    .width('100%')
    // 测量网格可用高度：长屏机型据此把格子拉高、铺满屏幕；
    // 矮屏机型测得高度不足时仍用基准值，靠滚动查看。
    .onAreaChange((_oldValue: Area, newValue: Area) => {
      const h = newValue.height as number;
      // 变化超过 8vp 才更新，避免微小抖动引发反复重排
      if (Math.abs(h - this.gridAreaHeight) > 8) {
        this.gridAreaHeight = h;
      }
    })
    // ---- 课程详情弹窗 ----
    //
    // ⚠️ 第一个参数必须是 **boolean**：bindSheet(isShow: boolean, ...)。
    //    传对象/可空值会静默失效（弹层不出现且无报错）。
    // 用 bindSheet 而不是 CustomDialog：底部卡片式更符合移动端习惯，
    // 且自带遮罩与下滑关闭，不需要自己管动画和返回键。
    .bindSheet(this.showDetail, this.CourseDetailSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      backgroundColor: Theme.colors(this.isDark).surface,
      onDisappear: () => {
        this.showDetail = false;
        this.detailCourse = null;
      }
    })
  }

  /**
   * 课程详情弹层。
   *
   * ## 为什么需要它
   *
   * 课表格子受「单节高度 × 跨几节」限制，一格能显示的字数非常有限：
   * 长课名、多个老师、大段上课内容都会被省略成「…」。
   * 点开这里能看到**该课程的全部信息**，不受格子高度约束。
   *
   * 内容按重要性排列：课名 → 时间/星期/节次 → 地点 → 老师 → 上课内容。
   */
  @Builder
  CourseDetailSheet() {
    Column() {
      if (this.detailCourse !== null) {
        // ---- 顶部：色条 + 课名 ----
        Row() {
          Row()
            .width(4)
            .height(26)
            .borderRadius(2)
            .backgroundColor(this.cellColor(this.detailCourse as Course))
          Text((this.detailCourse as Course).name)
            .fontSize(FontSize.titleLarge)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.colors(this.isDark).onSurface)
            .margin({ left: 10 })
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // ---- 时间信息 ----
        Column() {
          this.DetailRow('时间', this.detailTime())
          this.DetailRow('节次', this.detailSections())
          if (this.detailCourse !== null && (this.detailCourse as Course).room !== undefined
            && ((this.detailCourse as Course).room as string).length > 0) {
            this.DetailRow('地点', (this.detailCourse as Course).room as string)
          }
          if (this.detailCourse !== null && (this.detailCourse as Course).teacher !== undefined
            && ((this.detailCourse as Course).teacher as string).length > 0) {
            this.DetailRow('老师', (this.detailCourse as Course).teacher as string)
          }
          this.DetailRow('周次', this.detailWeeks())
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 14 })

        // ---- 上课内容（完整显示，不截断） ----
        if (this.detailCourse !== null && (this.detailCourse as Course).content !== undefined
          && ((this.detailCourse as Course).content as string).length > 0) {
          Column() {
            Text('上课内容')
              .fontSize(FontSize.small)
              .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
              .width('100%')
            Text((this.detailCourse as Course).content as string)
              .fontSize(FontSize.body)
              .fontColor(Theme.colors(this.isDark).onSurface)
              .lineHeight(21)
              .width('100%')
              .margin({ top: 6 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 12 })
          .margin({ top: 12 })
          .border({ width: { top: 1 }, color: Theme.colors(this.isDark).outline })
        }

        Blank()

        Button('关闭')
          .width('100%')
          .fontSize(FontSize.subtitle)
          .backgroundColor(Theme.colors(this.isDark).surfaceVariant)
          .fontColor(Theme.colors(this.isDark).onSurface)
          .onClick(() => {
            this.showDetail = false;
            this.detailCourse = null;
          })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 20 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 详情里的一行「标签 — 值」 */
  @Builder
  DetailRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(FontSize.small)
        .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        .width(48)
      Text(value)
        .fontSize(FontSize.body)
        .fontColor(Theme.colors(this.isDark).onSurface)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 5, bottom: 5 })
  }

  /** 详情里的时间：优先教务给的 timeLabel，否则按作息表拼 */
  private detailTime(): string {
    const c = this.detailCourse;
    if (c === null) {
      return '—';
    }
    if (c.timeLabel !== undefined && c.timeLabel.length > 0) {
      return c.timeLabel;
    }
    const start = DefaultPeriods.at(c.startSection);
    const end = DefaultPeriods.at(c.endSection);
    if (start !== undefined && end !== undefined) {
      return `${start.start} - ${end.end}`;
    }
    return '—';
  }

  /** 详情里的节次：`第 1-2 节` */
  private detailSections(): string {
    const c = this.detailCourse;
    if (c === null) {
      return '—';
    }
    const dayNames: string[] = ['一', '二', '三', '四', '五', '六', '日'];
    const day = c.dayOfWeek >= 1 && c.dayOfWeek <= 7 ? dayNames[c.dayOfWeek - 1] : '?';
    if (c.startSection === c.endSection) {
      return `周${day}　第 ${c.startSection} 节`;
    }
    return `周${day}　第 ${c.startSection}-${c.endSection} 节`;
  }

  /** 详情里的周次：`第 1-16 周` 或列出具体周 */
  private detailWeeks(): string {
    const c = this.detailCourse;
    if (c === null || c.weeks.length === 0) {
      return '—';
    }
    const w = c.weeks;
    if (w.length === 1) {
      return `第 ${w[0]} 周`;
    }
    return `第 ${w[0]}-${w[w.length - 1]} 周（共 ${w.length} 周）`;
  }

  private sectionList(): number[] {
    const out: number[] = [];
    for (let i = 1; i <= TOTAL_SECTIONS; i++) {
      out.push(i);
    }
    return out;
  }

  private days(): number[] {
    return [1, 2, 3, 4, 5, 6, 7];
  }

  /**
   * 生成 ForEach 的键。
   *
   * 必须包含**能反映格子内容**的信息，否则切周时 ArkUI 会复用旧组件、
   * 导致网格看起来「不刷新」。
   *
   * 键的构成：
   * - 有课：`c_<星期>_<节次>_<课程id>_<跨度>` —— 课程 id 里含课程码/周次，切周必变
   * - 空课：`e_<星期>_<节次>` —— 空格子无内容可辨，用节次区分即可
   */
  private cellKey(day: number, cell: GridCell, idx: number): string {
    if (cell.course !== null) {
      return `c_${day}_${cell.section}_${cell.course.id}_${cell.span}`;
    }
    return `e_${day}_${cell.section}_${idx}`;
  }

  /**
   * 计算某一天要渲染的格子序列。
   *
   * 规则：从第 1 节往下走；
   * - 若第 i 节有课 → 渲染一块高 span 的色块，跳过它覆盖的后续几节
   * - 若第 i 节被前面的课覆盖 → 跳过
   * - 否则渲染一个空格子
   */
  private cellsOfDay(day: number): GridCell[] {
    const week = this.state.selectedWeek;
    const dayCourses: Course[] = [];
    for (const c of this.state.scheduleCourses) {
      if (c.dayOfWeek === day && c.weeks.indexOf(week) >= 0) {
        dayCourses.push(c);
      }
    }

    // 起始节 → 课程
    const starts = new Map<number, Course>();
    for (const c of dayCourses) {
      starts.set(c.startSection, c);
    }
    const covered: number[][] = [];
    for (const c of dayCourses) {
      covered.push([c.startSection, c.endSection]);
    }

    const out: GridCell[] = [];
    let i = 1;
    while (i <= TOTAL_SECTIONS) {
      const course = starts.get(i);
      if (course !== undefined) {
        const rawSpan = course.endSection - course.startSection + 1;
        const maxSpan = TOTAL_SECTIONS - i + 1;
        const span = Math.max(1, Math.min(rawSpan, maxSpan));
        out.push({ course: course, span: span, section: i });
        i += span;
        continue;
      }
      // 是否被前面的课覆盖
      let inCovered = false;
      for (const range of covered) {
        if (i >= range[0] && i <= range[1]) {
          inCovered = true;
          break;
        }
      }
      if (inCovered) {
        i++;
        continue;
      }
      out.push({ course: null, span: 1, section: i });
      i++;
    }
    return out;
  }

  // ---- 一节课的色块 ----
  /**
   * 渲染一节课的色块。
   *
   * ⚠️ 这里刻意**不**用 @Builder 直接画，而是转给独立的 CourseCellView 组件：
   * @Builder 生成的是当前组件内的一个 UI 片段，ForEach 复用时
   * 参数（course）变了也未必重新求值；而 @Prop 组件的入参变化
   * 有明确的刷新语义，能保证切周后内容真的更新。
   */
  @Builder
  CourseCell(course: Course, height: number) {
    CourseCellView({
      name: course.name,
      room: course.room !== undefined ? course.room : '',
      teacher: course.teacher !== undefined ? course.teacher : '',
      content: course.content !== undefined ? course.content : '',
      isSelfStudy: course.isSelfStudy === true,
      color: this.cellColor(course),
      onColor: Theme.onCourseColor(this.cellColor(course)),
      cellHeight: height,
      isDark: this.isDark,
      // 点色块弹出详情：格子里放不下的老师、上课内容在弹窗里完整展示
      //
      // ⚠️ 回调必须作为**组件参数**传进去，不能写成
      //    CourseCellView({...}).onClick(...) —— @Builder 调用后的
      //    属性链式调用不生效（实测点击无任何反应、也无报错）。
      //    组件内部在自己的根容器上 .onClick 才可靠。
      onTap: () => {
        this.detailCourse = course;
        this.showDetail = true;
      }
    })
  }

  /**
   * 一节课的色块颜色。
   *
   * ## 为什么不能直接用教务的 bgcolor
   *
   * 实测真实数据（220 条整学期课程）：
   * - 教务**只给了 4 种颜色**，其中 `#1f86c7` 一个就占了 131 条（60%）；
   * - 更糟的是**同一门课在不同周颜色还会变**：
   *   「呼吸系统」出现过 4 种颜色，「综合高级英语」出现过 3 种。
   *
   * 结果就是整张课表大片同色、且同一门课每周换色，完全看不出区分。
   *
   * ## 现在的策略：课程名 → 唯一的颜色
   *
   * 见 [buildColorMap]：哈希定位 + 冲突探测，保证
   * **同一门课永远同色、不同课程颜色互不相同**。
   *
   * 教务 bgcolor 仅在「课程名为空」时作为兜底。
   */
  private cellColor(course: Course): string {
    const name = course.name.trim();
    if (name.length === 0) {
      const parsed = Theme.parseHex(course.colorHex);
      return parsed !== undefined ? parsed : Theme.colors(this.isDark).primary;
    }
    // 具体取色见 CourseColors.courseColor（表里没有时内部会退回哈希取模）
    return courseColor(name, this.buildColorMap());
  }

  /**
   * 构建「课程名 → 颜色」映射。
   *
   * ## 分配策略
   *
   * 1. 收集整学期所有不重复课程名；
   * 2. 每门课先用哈希算出一个首选色位；
   * 3. 若该色位已被占用，就往后探测第一个空位。
   *
   * 这样得到的性质：
   * - **无冲突**：只要课程数 ≤ 调色板容量（14），每门课颜色都不同；
   * - **确定**：同样的课程集合永远得到同样的分配，重启 App 不换色；
   * - **较稳**：新增一门课只可能影响它后面的少数课程，不会整表重排。
   *
   * 结果做了缓存：只有课程集合规模变化时才重算，
   * 避免每次渲染都遍历一遍学期课程。
   */
  private buildColorMap(): Map<string, string> {
    const courses = this.state.termCourses;
    const key = courses.length;
    if (key === this.colorMapKey && this.colorMapCache.size > 0) {
      return this.colorMapCache;
    }

    // 收集不重复课程名（具体分配算法见 CourseColors.assignCourseColors）
    const names: string[] = [];
    const seen = new Set<string>();
    for (const c of courses) {
      const n = c.name.trim();
      if (n.length > 0 && !seen.has(n)) {
        seen.add(n);
        names.push(n);
      }
    }

    const map = assignCourseColors(names);
    this.colorMapCache = map;
    this.colorMapKey = key;
    return map;
  }

  // ---- 底部翻周 ----
  @Builder
  WeekNav() {
    Row() {
      Button('← 上一周')
        .fontSize(FontSize.body)
        .fontColor(Theme.colors(this.isDark).primary)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onPrevWeek();
        })
      Button('下一周 →')
        .fontSize(FontSize.body)
        .fontColor(Theme.colors(this.isDark).primary)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.onNextWeek();
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
  }
}
