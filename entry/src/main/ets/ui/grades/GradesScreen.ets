/**
 * 成绩页。
 *
 * 结构：**List + 按学期折叠**。用 `xnxqmc`（领域模型里的 Grade.term）分组，
 * 每个学期一个可点击 Header，展开/收起。
 *
 * 视觉设计要点：
 * 1. 顶部汇总区用大字号数字 + 细分隔，形成清晰的视觉焦点；
 * 2. 学期卡片统一用 CardBox 包裹，箭头在容器内右对齐，不会被屏幕边缘截断；
 * 3. 分数按高低着色（>=90 绿 / >=80 蓝 / >=60 橙 / <60 红），一眼看出薄弱科目；
 * 4. 展开后每门课一行，分数与学分右对齐，行间用极淡的分隔线。
 *
 * 两个实现细节（原版踩坑）：
 * - 默认**全部收起**，用户点了哪个就展开哪个；
 * - `null` 统一显示成「—」，绝不显示 0 —— 0 分和「没有这项」是两件事。
 *
 * 移植自 Android 版 ui/grades/GradesScreen.kt。
 */
import { Grade } from '../../core/Models';
import { Theme } from '../../theme/Theme';
import { AppState } from '../../core/AppViewModel';
import { CardBox, EmptyHint } from '../components/Common';
import { FontSize } from '../../theme/Typography';

@Component
export struct GradesScreen {
  @ObjectLink state: AppState;
  @Prop isDark: boolean = false;

  /** 已展开的学期名集合 */
  @State expanded: string[] = [];

  build() {
    Column() {
      // ---- 页面标题 ----
      Column() {
        Text('成绩')
          .fontSize(FontSize.display)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.colors(this.isDark).onSurface)
        Text(this.subtitleText())
          .fontSize(FontSize.smallBody)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      if (this.state.grades.length === 0) {
        EmptyHint({ text: '还没有成绩数据', isDark: this.isDark })
      } else {
        List({ space: 0 }) {
          // ---- 汇总卡片 ----
          ListItem() {
            this.SummaryCard()
          }

          // ---- 学期分组 ----
          // 键里带上「是否展开」：展开状态变化时 ForEach 会重建这一项，
          // 确保展开后的课程列表真的出现（否则 List 可能复用旧节点）。
          ForEach(this.termKeys(), (term: string, idx: number) => {
            ListItem() {
              this.TermHeader(term, this.gradesOfTerm(term))
            }

            if (this.isExpanded(term)) {
              ListItem() {
                this.TermBody(term, this.gradesOfTerm(term))
              }
            }
          }, (term: string, idx: number) => `term_${term}_${idx}_${this.isExpanded(term) ? 'open' : 'shut'}`)

          ListItem() {
            Row().height(24).width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ bottom: 8 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.colors(this.isDark).background)
  }

  private subtitleText(): string {
    const terms = this.termKeys().length;
    return `共 ${this.state.grades.length} 门 · ${terms} 个学期 · 总学分 ${this.fmt(this.state.totalCredit(), 1)}`;
  }

  private termKeys(): string[] {
    const out: string[] = [];
    this.state.gradesByTerm().forEach((_list: Grade[], key: string) => {
      out.push(key);
    });
    return out;
  }

  private gradesOfTerm(term: string): Grade[] {
    const list = this.state.gradesByTerm().get(term);
    return list !== undefined ? list : [];
  }

  private isExpanded(term: string): boolean {
    return this.expanded.indexOf(term) >= 0;
  }

  private toggle(term: string): void {
    const idx = this.expanded.indexOf(term);
    const next: string[] = this.expanded.slice();
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(term);
    }
    this.expanded = next;
  }

  // ---- 汇总 ----
  /**
   * 顶部汇总：四个关键指标横排。
   *
   * 视觉层级：数字大（20px 粗体）+ 标签小（10px 灰）；
   * 中间用极淡的竖线分隔，让四组数字各自独立又不散。
   */
  @Builder
  SummaryCard() {
    CardBox({ isDark: this.isDark }) {
      Column() {
        Row() {
          this.Stat('加权绩点', this.fmt(this.state.weightedGpa(), 2), true)
          this.StatDivider()
          this.Stat('加权平均', this.fmt(this.state.weightedScore(), 1), false)
          this.StatDivider()
          this.Stat('总学分', this.fmt(this.state.totalCredit(), 1), false)
          this.StatDivider()
          this.Stat('门数', `${this.state.grades.length}`, false)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.hasLevelOnlyGrade()) {
          Text('含等级制课程（无百分制分数），加权平均只统计有分数的课程')
            .fontSize(FontSize.caption)
            .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
            .margin({ top: 12 })
            .maxLines(2)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 汇总里两组数字之间的细分隔线 */
  @Builder
  StatDivider() {
    Row()
      .width(1)
      .height(28)
      .backgroundColor(Theme.colors(this.isDark).outline)
      .opacity(0.6)
  }

  /**
   * 单个指标。
   * @param emphasize 用主色强调（加权绩点是最常看的一项）
   */
  @Builder
  Stat(label: string, value: string, emphasize: boolean) {
    Column() {
      Text(value)
        .fontSize(FontSize.headline)
        .fontWeight(FontWeight.Bold)
        .fontColor(emphasize
          ? Theme.colors(this.isDark).primary
          : Theme.colors(this.isDark).onSurface)
        .maxLines(1)
      Text(label)
        .fontSize(FontSize.caption)
        .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        .margin({ top: 3 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  private hasLevelOnlyGrade(): boolean {
    for (const g of this.state.grades) {
      if (g.score === undefined) {
        return true;
      }
    }
    return false;
  }

  // ---- 学期头 ----
  /**
   * 学期卡片头：左「学期名 + 门数/均分」，右箭头。
   *
   * ⚠️ 外层用 CardBox 提供统一的左右边距，
   * 这里**不再自己加 margin** —— 否则会和容器边距叠加，
   * 导致右侧箭头被推出屏幕（旧版就是这个问题）。
   *
   * ⚠️ onClick 必须挂在 CardBox **内部**那一层 Row 上：
   * CardBox 是独立的 @Component，挂在外层不会穿透进去。
   */
  @Builder
  TermHeader(term: string, list: Grade[]) {
    CardBox({ isDark: this.isDark }) {
      Row() {
        // 左侧：学期名 + 统计
        Column() {
          Text(term.length > 0 ? term : '未知学期')
            .fontSize(FontSize.subtitle)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.colors(this.isDark).onSurface)
          Text(this.termSummary(list))
            .fontSize(FontSize.small)
            .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
            .margin({ top: 3 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // 右侧：均分徽标 + 箭头
        if (this.termAverage(list) !== undefined) {
          Text(this.fmt(this.termAverage(list), 1))
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.scoreColor(this.termAverage(list)))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor(this.scoreBgColor(this.termAverage(list)))
            .borderRadius(6)
            .margin({ right: 10 })
        }

        Text(this.isExpanded(term) ? '⌃' : '⌄')
          .fontSize(FontSize.subtitleEmphasis)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .width(20)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.toggle(term);
      })
    }
  }

  /**
   * 学期均分；没有百分制成绩时返回 undefined。
   * 返回值同时用于「学期头徽标」和「是否显示徽标」的判断。
   */
  private termAverage(list: Grade[]): number | undefined {
    let sum = 0;
    let count = 0;
    for (const g of list) {
      if (g.score !== undefined) {
        sum += g.score;
        count++;
      }
    }
    return count > 0 ? sum / count : undefined;
  }

  private termSummary(list: Grade[]): string {
    const avg = this.termAverage(list);
    if (avg === undefined) {
      return `${list.length} 门`;
    }
    return `${list.length} 门`;
  }

  // ---- 学期展开后的课程列表 ----
  /**
   * 展开后的课程表。
   *
   * 用一个卡片包住整组课程，而不是散落的行 ——
   * 这样「展开」在视觉上是一个整体，和头部形成从属关系。
   */
  @Builder
  TermBody(term: string, list: Grade[]) {
    Column() {
      ForEach(list, (g: Grade, i: number) => {
        this.GradeRow(g, i === list.length - 1)
      }, (g: Grade, i: number) => `grade_${term}_${i}_${g.course}`)
    }
    // 同 CardBox：不能用 width('100%') + 左右 margin，否则右侧溢出一截
    .width('auto')
    .padding({ left: 14, right: 14, top: 4, bottom: 8 })
    .margin({ left: 14, right: 14, bottom: 10 })
    .backgroundColor(Theme.colors(this.isDark).surface)
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
  }

  // ---- 一门成绩 ----
  /**
   * 成绩行：课名（+ 类型标签）在左，分数 + 学分在右。
   *
   * 分数用色块背景 + 对应颜色文字，扫一眼就知道这门课考得怎么样。
   */
  @Builder
  GradeRow(g: Grade, isLast: boolean) {
    Column() {
      Row() {
        // 左：课名 + 类型
        Column() {
          Text(g.course)
            .fontSize(FontSize.bodyStrong)
            .fontColor(Theme.colors(this.isDark).onSurface)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (g.kind !== undefined && g.kind.length > 0) {
            Text(g.kind)
              .fontSize(FontSize.caption)
              .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
              .margin({ top: 2 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // 右：分数
        Text(this.scoreText(g))
          .fontSize(FontSize.subtitle)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isLevelGrade(g) ? Theme.colors(this.isDark).scoreExcellent : this.scoreColor(g.score))
          .width(46)
          .textAlign(TextAlign.Center)

        // 右：学分（宽度要够放「10.0 学分」，否则会被截断）
        Text(`${this.fmt(g.credit, 1)} 学分`)
          .fontSize(FontSize.small)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .width(58)
          .textAlign(TextAlign.End)
          .maxLines(1)
      }
      .width('100%')
      .padding({ top: 9, bottom: 9 })
      .alignItems(VerticalAlign.Center)

      // 行间分隔线（最后一行不画）
      if (!isLast) {
        Divider()
          .color(Theme.colors(this.isDark).outline)
          .opacity(0.5)
      }
    }
    .width('100%')
  }

  /** 等级制课程（优/良/中/及格…）：没有百分制分数 */
  private isLevelGrade(g: Grade): boolean {
    return g.score === undefined && g.level !== undefined && g.level.length > 0;
  }

  /** 成绩显示文本：等级制显示等级，否则显示整数分数 */
  private scoreText(g: Grade): string {
    if (this.isLevelGrade(g)) {
      return g.level !== undefined ? g.level : '—';
    }
    return this.fmt(g.score, 0);
  }

  /**
   * 分数对应的颜色。
   *
   * 用教务成绩的常见分档：
   * >= 90 优秀（绿）/ >= 80 良好（蓝）/ >= 60 及格（橙）/ < 60 不及格（红）
   * 拿不到分数时用普通文字色。
   */
  private scoreColor(score: number | undefined): string {
    if (score === undefined) {
      return Theme.colors(this.isDark).onSurface;
    }
    const c = Theme.colors(this.isDark);
    if (score >= 90) {
      return c.scoreExcellent;
    }
    if (score >= 80) {
      return c.scoreGood;
    }
    if (score >= 60) {
      return c.scoreFair;
    }
    return c.scorePoor;
  }

  /** 分数徽标背景色（学期头用，浅一档） */
  private scoreBgColor(score: number | undefined): string {
    if (score === undefined) {
      return Theme.colors(this.isDark).surfaceVariant;
    }
    const c = Theme.colors(this.isDark);
    if (score >= 90) {
      return c.badgeExcellent;
    }
    if (score >= 80) {
      return c.badgeGood;
    }
    if (score >= 60) {
      return c.badgeFair;
    }
    return c.badgePoor;
  }

  /** null 统一显示成「—」，绝不显示 0 */
  private fmt(value: number | undefined, digits: number): string {
    if (value === undefined) {
      return '—';
    }
    return value.toFixed(digits);
  }
}
