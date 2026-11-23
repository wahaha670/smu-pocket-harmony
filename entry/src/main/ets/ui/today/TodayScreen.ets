/**
 * 今日页。
 *
 * 内容：日期标题 / 今日课程 / 明日课程 / 本周概览柱状图 / 考试安排（含网考号）。
 *
 * 两个关键点：
 * 1. **今日与课表解耦** —— 在课表翻到第 8 周，「今日」仍然是真实当前周的课。
 * 2. **明日跨周要单独处理** —— 今天是周日时，明天属于下一周。
 *
 * 移植自 Android 版 ui/today/TodayScreen.kt。
 */
import { Course, Period } from '../../core/Models';
import { Theme } from '../../theme/Theme';
import { FontSize } from '../../theme/Typography';
import { AppState } from '../../core/AppViewModel';
import { CardBox, SelfStudyChip } from '../components/Common';
import {
  cnWeekday,
  dayOfWeek,
  dayOfMonth,
  monthOf,
  todayStart,
  addDays,
  formatDate
} from '../../core/DateUtils';

const DAY_LABELS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

@Component
export struct TodayScreen {
  @ObjectLink state: AppState;
  @Prop isDark: boolean = false;

  /**
   * 当前显示的「今天」（当天 00:00 的时间戳）。
   *
   * 它的唯一作用是**触发刷新**：一旦跨过零点，这个值变化，
   * 依赖它的 dateTitle / todayCourses / dailyCounts 就会全部重算。
   *
   * 如果没有它，App 在后台放一夜、第二天早上打开，
   * 页面还停留在昨天的数据上（ArkUI 不会自动感知日期变了）。
   */
  @State todayStamp: number = todayStart();

  /** 跨天检测定时器 */
  private dayTimer: number = -1;

  aboutToAppear(): void {
    this.todayStamp = todayStart();
    this.startDayWatcher();
  }

  aboutToDisappear(): void {
    this.stopDayWatcher();
  }

  /** 页面重新可见时（从后台切回）立刻校正一次，避免定时器被系统挂起后错过跨天 */
  onPageShow(): void {
    this.refreshToday();
    this.startDayWatcher();
  }

  onPageHide(): void {
    this.stopDayWatcher();
  }

  /**
   * 每 30 秒检查一次是否跨天。
   *
   * 为什么不是每分钟整点触发：定时器在后台可能被延迟，
   * 用「轮询检测日期是否变化」比「算出距零点的毫秒数再定时」更稳，
   * 因为它对系统时间调整、时区变化、定时器漂移都免疫。
   */
  private startDayWatcher(): void {
    if (this.dayTimer !== -1) {
      return;
    }
    this.dayTimer = setInterval(() => {
      this.refreshToday();
    }, 30000);
  }

  private stopDayWatcher(): void {
    if (this.dayTimer !== -1) {
      clearInterval(this.dayTimer);
      this.dayTimer = -1;
    }
  }

  /** 若日期已变，更新 todayStamp 触发整页重算 */
  private refreshToday(): void {
    const now = todayStart();
    if (now !== this.todayStamp) {
      this.todayStamp = now;
    }
  }

  build() {
    Scroll() {
      Column() {
        // 直接把日期作为页面主标题
        Text(this.dateTitle())
          .fontSize(FontSize.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.colors(this.isDark).onSurface)
          .width('100%')
          .padding({ left: 20, right: 20, top: 20, bottom: 8 })

        // ---- 今日课程 ----
        CardBox({ isDark: this.isDark }) {
          this.TodayCard(this.todayStamp)
        }

        // ---- 明日课程 ----
        CardBox({ isDark: this.isDark }) {
          this.TomorrowCard(this.todayStamp)
        }

        // ---- 本周概览 ----
        if (this.state.weekTotal() > 0) {
          CardBox({ isDark: this.isDark }) {
            this.WeekOverviewCard(this.todayStamp)
          }
        }

        // ---- 考试安排 ----
        CardBox({ isDark: this.isDark }) {
          this.ExamCard()
        }

        if (this.state.loading) {
          CardBox({ isDark: this.isDark }) {
          this.LoadingCard()
        }
        }

        if (this.state.error.length > 0) {
          CardBox({ isDark: this.isDark }) {
          this.ErrorCard()
        }
        }

        Blank().height(20)
      }
      .width('100%')
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Off)
    .width('100%')
    .height('100%')
    // 显式顶部对齐：Scroll 默认居中，内容短于视口时会被压低
    //（例如假期没有课、也没有考试时，今日页内容会变短）
    .align(Alignment.Top)
    .backgroundColor(Theme.colors(this.isDark).background)
  }

  private dateTitle(): string {
    // 用 todayStamp（响应式）而不是直接调 todayStart()：
    // 跨天时 todayStamp 变化会触发本方法重算，标题才会跟着更新。
    const today = this.todayStamp;
    // 周次也按今天实时算，不用缓存快照里的 currentWeek
    const week = this.state.liveCurrentWeek();
    return `${formatDate(today)} · 星期${cnWeekday(today)} · 第 ${week} 周`;
  }

  @Builder
  LoadingCard() {
    Text('正在加载…')
      .fontSize(FontSize.small)
      .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
  }

  @Builder
  ErrorCard() {
    Text(this.state.error)
      .fontSize(FontSize.small)
      .fontColor(Theme.colors(this.isDark).error)
  }

  // ---- 今日 ----
  @Builder
  TodayCard(dayStamp: number) {
    Column() {
      Row() {
        Text(`今日课程 ${this.state.todayCourses().length} 节`)
          .fontSize(FontSize.bodyStrong)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.colors(this.isDark).onSurface)
          .layoutWeight(1)
        // 离线时标注数据来源：让用户知道课程是按本地缓存的整学期课表实时算出来的
        if (this.state.stale) {
          Text('离线缓存')
            .fontSize(FontSize.tiny)
            .fontColor(Theme.colors(this.isDark).primary)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .backgroundColor(Theme.colors(this.isDark).surfaceVariant)
            .borderRadius(4)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (!this.state.todayDataReady()) {
        Text(`课表还没更新到本周（当前是第 ${this.state.liveCurrentWeek()} 周）`)
          .fontSize(FontSize.body)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .margin({ top: 6 })
      } else if (this.state.todayCourses().length === 0) {
        Text('今天没有课。')
          .fontSize(FontSize.body)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .margin({ top: 6 })
      } else {
        Column() {
          ForEach(this.state.todayCourses(), (course: Course, idx: number) => {
            this.CourseRow(course, idx > 0)
          }, (course: Course, idx: number) => `today_${course.id}_${idx}`)
        }
        .width('100%')
        .margin({ top: 8 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 明日 ----
  @Builder
  TomorrowCard(dayStamp: number) {
    Column() {
      Row() {
        Text('明日课程')
          .fontSize(FontSize.bodyStrong)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.colors(this.isDark).onSurface)
          .layoutWeight(1)
        Text(this.tomorrowLabel())
          .fontSize(FontSize.caption)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (!this.state.tomorrowDataReady()) {
        Text(`明天是第 ${this.state.tomorrowWeek()} 周，那周的课表还没加载`)
          .fontSize(FontSize.body)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .margin({ top: 6 })
      } else if (this.state.tomorrowCourses().length === 0) {
        Text(this.tomorrowEmptyHint())
          .fontSize(FontSize.body)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .margin({ top: 6 })
      } else {
        Column() {
          ForEach(this.state.tomorrowCourses(), (course: Course, idx: number) => {
            this.CourseRow(course, idx > 0)
          }, (course: Course, idx: number) => `tom_${course.id}_${idx}`)
        }
        .width('100%')
        .margin({ top: 8 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private tomorrowLabel(): string {
    const d = addDays(todayStart(), 1);
    return `明天 · ${monthOf(d)}月${dayOfMonth(d)}日 星期${cnWeekday(d)}`;
  }

  private tomorrowEmptyHint(): string {
    const wd = dayOfWeek(addDays(todayStart(), 1));
    if (wd === 6) {
      return '明天是周六，没有课，睡个懒觉吧';
    }
    if (wd === 7) {
      return '明天是周日，没有课，好好休息';
    }
    return '明天没有课，好好休息';
  }

  // ---- 本周概览 ----
  @Builder
  WeekOverviewCard(dayStamp: number) {
    Column() {
      Row() {
        Text('本周概览')
          .fontSize(FontSize.bodyStrong)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.colors(this.isDark).onSurface)
          .layoutWeight(1)
        Text(`共 ${this.state.weekTotal()} 节`)
          .fontSize(FontSize.small)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        ForEach(this.state.dailyCounts(), (count: number, idx: number) => {
          Column() {
            Text(`${count}`)
              .fontSize(FontSize.caption)
              .fontColor(idx + 1 === dayOfWeek(todayStart())
                ? Theme.colors(this.isDark).primary
                : Theme.colors(this.isDark).onSurfaceVariant)
            Blank().height(4)
            // 柱子：高度按比例，0 时留细条
            Row()
              .width('100%')
              .height(this.barHeight(count))
              .backgroundColor(idx + 1 === dayOfWeek(todayStart())
                ? Theme.colors(this.isDark).primary
                : Theme.colors(this.isDark).surfaceVariant)
              .borderRadius({ topLeft: 4, topRight: 4 })
            Blank().height(6)
            Text(DAY_LABELS[idx])
              .fontSize(FontSize.caption)
              .fontColor(idx + 1 === dayOfWeek(todayStart())
                ? Theme.colors(this.isDark).primary
                : Theme.colors(this.isDark).onSurfaceVariant)
          }
          .layoutWeight(1)
          .height('100%')
          .justifyContent(FlexAlign.End)
          .alignItems(HorizontalAlign.Center)
          .margin({ right: 6 })
        }, (count: number, idx: number) => `bar_${idx}`)
      }
      .width('100%')
      .height(104)
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 12 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 柱子高度：按当天课数占最大值的比例，最少 3（0 节课）或 8 */
  private barHeight(count: number): number {
    let max = 1;
    const counts = this.state.dailyCounts();
    for (const c of counts) {
      if (c > max) {
        max = c;
      }
    }
    const ratio = count / max;
    const minH = count === 0 ? 3 : 8;
    const h = 56 * ratio;
    return h > minH ? h : minH;
  }

  // ---- 考试安排 ----
  @Builder
  ExamCard() {
    Column() {
      Row() {
        Text('考试安排')
          .fontSize(FontSize.bodyStrong)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.colors(this.isDark).onSurface)
          .layoutWeight(1)
        if (this.state.examNumbersReady && this.state.upcomingExams().length > 0) {
          Text(`共 ${this.state.upcomingExams().length} 场`)
            .fontSize(FontSize.small)
            .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (!this.state.examNumbersReady) {
        // 网考号还没回来：整张考试列表先别画，否则列表先渲染、号码过后再「跳」出来
        Row() {
          LoadingProgress()
            .width(14)
            .height(14)
            .color(Theme.colors(this.isDark).primary)
          Text('正在加载考试安排…')
            .fontSize(FontSize.caption)
            .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
            .margin({ left: 8 })
        }
        .margin({ top: 8 })
        .alignItems(VerticalAlign.Center)
      } else if (this.state.upcomingExams().length === 0) {
        Text('近期暂无考试安排')
          .fontSize(FontSize.body)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .margin({ top: 6 })
      } else {
        Column() {
          ForEach(this.state.upcomingExams(), (exam: Course, idx: number) => {
            this.ExamRow(exam, idx > 0)
          }, (exam: Course, idx: number) => `exam_${exam.id}_${idx}`)
        }
        .width('100%')
        .margin({ top: 8 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ExamRow(exam: Course, withTopGap: boolean) {
    Row() {
      // 日期列
      Column() {
        Text(`${monthOf(exam.date ?? todayStart())}月${dayOfMonth(exam.date ?? todayStart())}日`)
          .fontSize(FontSize.small)
          .fontColor(Theme.colors(this.isDark).primary)
        Text(`周${cnWeekday(exam.date ?? todayStart())}`)
          .fontSize(FontSize.caption)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
      }
      .width(72)
      .alignItems(HorizontalAlign.Start)

      // 课名 + 网考号 + 地点
      Column() {
        Row() {
          Text(exam.name)
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.colors(this.isDark).onSurface)
          // 网考号：灰色小字，跟课名在同一行
          if (this.examNumberOf(exam).length > 0) {
            Text(` [网考号：${this.examNumberOf(exam)}]`)
              .fontSize(FontSize.caption)
              .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          }
        }
        .alignItems(VerticalAlign.Center)

        Text(this.examWhere(exam))
          .fontSize(FontSize.caption)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: withTopGap ? 10 : 0 })
  }

  /** 课程名 → 网考号；没有就返回空串，不留空括号 */
  private examNumberOf(exam: Course): string {
    const table = this.state.examNumbers;
    let v = table.get(exam.name);
    if (v === undefined) {
      v = table.get(exam.name.trim());
    }
    if (v === undefined) {
      return '';
    }
    return v.trim();
  }

  private examWhere(exam: Course): string {
    const room = exam.room !== undefined && exam.room.length > 0 ? exam.room : '地点待定';
    if (exam.timeLabel !== undefined && exam.timeLabel.length > 0) {
      return `${room} · ${exam.timeLabel}`;
    }
    return room;
  }

  // ---- 一节课的行 ----
  @Builder
  CourseRow(course: Course, withTopGap: boolean) {
    Row() {
      // 时间轴：优先用教务给的 qssj/jssj，拿不到退回本地作息表，再退到「第 N 节」
      Column() {
        Text(this.startText(course))
          .fontSize(FontSize.small)
          .fontColor(Theme.colors(this.isDark).primary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.endText(course))
          .fontSize(FontSize.caption)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
      }
      .width(64)
      .alignItems(HorizontalAlign.Start)

      Column() {
        Row() {
          Text(course.name)
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.colors(this.isDark).onSurface)
            .maxLines(2)
          if (course.isSelfStudy === true) {
            SelfStudyChip({ compact: false, isDark: this.isDark })
              .margin({ left: 6 })
          }
        }
        .alignItems(VerticalAlign.Center)

        Text(this.courseSubtitle(course))
          .fontSize(FontSize.caption)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: withTopGap ? 10 : 0 })
  }

  private startText(course: Course): string {
    const label = course.timeLabel;
    if (label !== undefined && label.indexOf('-') > 0) {
      const s = label.substring(0, label.indexOf('-'));
      if (s.length > 0) {
        return s;
      }
    }
    const p = this.periodAt(course.startSection);
    if (p !== undefined) {
      return p.start;
    }
    return `第${course.startSection}节`;
  }

  private endText(course: Course): string {
    const label = course.timeLabel;
    if (label !== undefined && label.indexOf('-') > 0) {
      const e = label.substring(label.indexOf('-') + 1);
      if (e.length > 0) {
        return e;
      }
    }
    const p = this.periodAt(course.endSection);
    if (p !== undefined) {
      return p.end;
    }
    return `第${course.endSection}节`;
  }

  private periodAt(section: number): Period | undefined {
    const cfg = this.state.config;
    if (cfg === undefined) {
      return undefined;
    }
    for (const p of cfg.periods) {
      if (p.index === section) {
        return p;
      }
    }
    return undefined;
  }

  /** 副标题：地点 · 老师 · 上课内容；自主学习显示「无需前往教室」 */
  private courseSubtitle(course: Course): string {
    const parts: string[] = [];
    if (course.isSelfStudy === true) {
      parts.push('无需前往教室');
    } else if (course.room !== undefined && course.room.length > 0) {
      parts.push(course.room);
    }
    const teachers = this.shortTeachers(course.teacher);
    if (teachers.length > 0) {
      parts.push(teachers);
    }
    if (course.content !== undefined && course.content.length > 0) {
      parts.push(course.content);
    }
    return parts.join(' · ');
  }

  /** 教务把多个老师的名字拼在一个字段里，卡片上只显示前 3 个 */
  private shortTeachers(raw: string | undefined): string {
    if (raw === undefined || raw.trim().length === 0) {
      return '';
    }
    const names: string[] = [];
    for (const piece of raw.split(/[,，、]/)) {
      const t = piece.trim();
      if (t.length > 0) {
        names.push(t);
      }
    }
    if (names.length === 0) {
      return '';
    }
    if (names.length <= 3) {
      return names.join('、');
    }
    const head: string[] = [];
    for (let i = 0; i < 3; i++) {
      head.push(names[i]);
    }
    return `${head.join('、')} 等${names.length}人`;
  }
}

