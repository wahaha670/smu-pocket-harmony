import { FontSize } from '../../theme/Typography';
/**
 * 桌面卡片：今明两天课程（长条横向卡片，左右分栏 + 可下滑）。
 *
 * ## 布局
 *
 * ```
 * ┌──────────────────────────────────────────────────────┐
 * │  第 6 周                                    周一       │  ← 固定不滚动
 * ├─────────────────────────┬────────────────────────────┤
 * │  今天 · 3 节             │  明天 · 11/24 周二 · 2 节   │  ← 以下可上下滑动
 * │  ● 系统解剖学             │  ● 大学英语                 │
 * │    08:00-09:25           │    08:00-09:25             │
 * │    王老师                 │    陈老师                   │
 * │    纵隔与胸膜             │    外语楼 402              │
 * └─────────────────────────┴────────────────────────────┘
 * ```
 *
 * 每门课四行信息，按重要性递减（详见 CardCourseRow 注释）：
 * 课名（最粗最大）→ 时间（靠右小字）→ 老师 → 上课内容（最浅）。
 *
 * ## 三个必须遵守的写法（都踩过坑）
 *
 * ### 1. 课程行必须是 @Component，不能用 @Builder 带参数
 *
 * ArkUI 的 `@Builder` **按值传参时不会随参数变化重新求值**。
 * 卡片首次渲染时 `@LocalStorageProp` 还是默认值（`'[]'`），
 * `@Builder` 就把空值捕获死了；等真实数据到达、`build()` 重跑时，
 * 它的参数并不会更新 —— 表现是「标题有数据、课程列表永远是空的」。
 *
 * `@Prop` 组件有明确的「入参变 → 重新渲染」语义，所以拆成组件。
 *
 * ### 2. 两栏内容内联在 build() 里，不抽 @Builder
 *
 * 同理：栏目也要直接读 `this.todayJson` / `this.tomorrowJson`，
 * 不能经 @Builder 参数中转。
 *
 * ### 3. 滑动只能用 List，不能用 Scroll
 *
 * 编译器明确拒绝 `Scroll`：`'Scroll' can't support form application`。
 * 改用 `List`（官方也建议控制 list-item 数量以获得好的卡片交互体验）。
 * 两栏各放一个 `List`，就能各自独立滑动；标题留在 List 外面保持可见。
 *
 * ## 为什么不 import 主应用的模块
 *
 * 卡片对可用 API 有严格限制（不能用文件、网络等能力）。
 * `WidgetData.ets` 里 import 了 `@ohos.file.fs`，
 * 一旦被卡片引用，**编译卡片时就会报错**。
 * 所以这里只保留纯 JSON 解析，字段与主应用写入的保持一致。
 */

/** 卡片上的一门课 */
interface CardCourse {
  name: string;
  time: string;
  room: string;
  color: string;
  teacher: string;
  content: string;
}

/**
 * 解析课程列表 JSON。
 *
 * 任何异常都退化成空数组 —— 卡片白屏比显示「暂无课程」更糟。
 * 字段名与主应用 WidgetData.WidgetCourse 严格一致。
 */
function parseCourses(json: string): CardCourse[] {
  const out: CardCourse[] = [];
  if (json === undefined || json === null || json.length === 0) {
    return out;
  }
  try {
    const arr: Object = JSON.parse(json) as Object;
    if (!Array.isArray(arr)) {
      return out;
    }
    for (const item of arr as Object[]) {
      if (item === null || item === undefined || typeof item !== 'object') {
        continue;
      }
      const o = item as Record<string, Object>;
      const c: CardCourse = {
        name: textOf(o['name']),
        time: textOf(o['time']),
        room: textOf(o['room']),
        color: textOf(o['color']),
        teacher: textOf(o['teacher']),
        content: textOf(o['content'])
      };
      if (c.name.length > 0) {
        out.push(c);
      }
    }
  } catch (e) {
    return [];
  }
  return out;
}

function textOf(v: Object | undefined): string {
  if (v === undefined || v === null) {
    return '';
  }
  if (typeof v === 'string') {
    return v as string;
  }
  return '';
}

// ---------------------------------------------------------------------------
// 课程行共用逻辑（抽成模块级纯函数）
//
// ⚠️ 为什么抽出来：卡片有两种课程行组件 ——
//    `CompactCourseRow`（2*2 紧凑）与 `CardCourseRow`（2*4/4*4 标准），
//    它们各自持有一份**完全相同的** teacherRoomText / startTime / dotColor。
//    同一份逻辑写两遍，改一处忘另一处就会导致两种卡片表现不一致。
//    所以统一到这里，两个组件共用。
// ---------------------------------------------------------------------------

/**
 * 「老师 · 地点」合并成一行。
 *
 * 两端都可能为空（自主学习没教室、教务没填老师），
 * 所以用数组拼再用 `·` 连接，避免出现「 · 504教室」这种孤立分隔符。
 */
function teacherRoomTextOf(teacher: string, room: string): string {
  const parts: string[] = [];
  if (teacher.length > 0) {
    parts.push(teacher);
  }
  if (room.length > 0) {
    parts.push(room);
  }
  return parts.join(' · ');
}

/** 只取开始时间：`08:00-10:30` → `08:00`（窄栏放不下完整区间） */
function startTimeOf(time: string): string {
  if (time.length === 0) {
    return '';
  }
  const idx = time.indexOf('-');
  if (idx > 0) {
    return time.substring(0, idx);
  }
  return time;
}

/**
 * 色点颜色：课程原色优先，缺失时用主题强调色。
 *
 * ⚠️ 兜底色必须走主题资源（`app.color.card_accent`）而不是硬编码蓝，
 *    否则深色模式下这个兜底色偏暗（曾经踩过）。
 *    资源引用由调用方传入，保持本函数纯净。
 */
function dotColorOf(color: string, fallback: ResourceColor): ResourceColor {
  return color.length > 0 ? color : fallback;
}

let storage: LocalStorage = new LocalStorage();

/**
 * 卡片尺寸（2*2 / 2*4 / 4*4）。
 *
 * ⚠️ 不能靠屏幕宽度猜——同一台手机上 2*2 和 2*4 的**宽度完全相同**，
 * 只有高度不同，而卡片根节点用的就是被系统裁好的固定高度。
 * 所以尺寸必须由系统通过 want 参数告知，见 EntryFormAbility.onAddForm：
 *   want.parameters[DIMENSION_KEY] = FormDimension
 * 再由能力层写进绑定数据，这里通过 @LocalStorageProp 读。
 */
@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('weekText') weekText: string = '南医大口袋';
  @LocalStorageProp('dayText') dayText: string = '';
  @LocalStorageProp('tomorrowLabel') tomorrowLabel: string = '明天';
  @LocalStorageProp('todayJson') todayJson: string = '[]';
  @LocalStorageProp('tomorrowJson') tomorrowJson: string = '[]';
  /**
   * 是否紧凑布局（2*2）。
   * 1 = 紧凑（只显示今天），0 = 标准（今明两栏）。
   */
  @LocalStorageProp('compact') compactFlag: number = 0;

  /** 是否走 2*2 紧凑布局 */
  private isCompact(): boolean {
    return this.compactFlag === 1;
  }

  build() {
    Column() {
      if (this.isCompact()) {
        this.buildCompact()
      } else {
        this.buildStandard()
      }
    }
    .width('100%')
    .height('100%')
    // 2*2 空间紧张，内边距从 12 收到 10，多给内容 4vp
    .padding(this.isCompact() ? 10 : 14)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
    // 点卡片任意位置打开 App
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { from: 'card' }
      });
    })
  }

  /**
   * 2*2 紧凑布局：只显示今天的课程。
   *
   * 空间只有长条卡片的四分之一，所以砍掉「明天」整栏，只留：
   *   顶部：周次 + 星期 + 节数
   *   下面：今天的课程列表（可滑动）
   *
   * 课程行用更紧凑的样式（见 CompactCourseRow）：课名 + 时间，
   * 不再显示老师与上课内容——它们在小尺寸里会把课名挤到看不清。
   */
  @Builder
  buildCompact() {
    Column() {
      // ---- 顶部：单行紧凑标题 ----
      //
      // ⚠️ 2*2 的高度只有长条卡片的一半，头部每多占一行，
      //    List 可视区就少 17vp —— 实测把它压到连第一门课的
      //    课名都显示不全（只露出下半截）。
      //    所以这里把「周次 + 星期 + 节数」合并成一行。
      Row() {
        Text(this.weekText)
          .fontSize(FontSize.bodyStrong)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.card_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .flexShrink(1)
        if (this.dayText.length > 0) {
          Text(this.dayText)
            .fontSize(FontSize.smallBody)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.card_title'))
            .maxLines(1)
            .flexShrink(0)
            .margin({ left: 6 })
        }
        Blank()
        Text(this.compactCount())
          .fontSize(FontSize.small)
          .fontColor($r('app.color.card_accent'))
          .maxLines(1)
          .flexShrink(0)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // ---- 今天的课程（完整内容，可上下滑动） ----
      //
      // 2*2 只有 2 格宽 × 2 格高，一屏放不下多节课。
      // 但 List 本身可以滚动，所以**不必为了塞下而砍掉老师与上课内容**——
      // 让用户下滑即可看到全部，比强行截断更有用。
      if (parseCourses(this.todayJson).length === 0) {
        CompactEmptyHint()
      } else {
        List() {
          ForEach(parseCourses(this.todayJson), (c: CardCourse, idx: number) => {
            ListItem() {
              CompactCourseRow({
                name: c.name,
                time: c.time,
                room: c.room,
                color: c.color,
                teacher: c.teacher,
                content: c.content,
                withGap: idx > 0
              })
            }
          }, (c: CardCourse, idx: number) => `c_${idx}_${c.name}_${c.time}`)
        }
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 4 })
        // 硬裁切：滚动区之外的 ListItem 不可见，避免半截文字露在边缘
        .clip(true)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 紧凑卡片的节数：`4 节` / `无课` */
  private compactCount(): string {
    const n = parseCourses(this.todayJson).length;
    if (n === 0) {
      return '无课';
    }
    return `${n} 节`;
  }

  /**
   * 标准布局（2*4 / 4*4）：今明两栏，可各自滑动。
   */
  @Builder
  buildStandard() {
    Column() {
      // ---- 顶部：周次 + 今天星期（固定，不随内容滚动） ----
      Row() {
        Text(this.weekText)
          .fontSize(FontSize.title)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.card_title'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.dayText.length > 0) {
          Text(this.dayText)
            .fontSize(FontSize.subtitleEmphasis)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.card_title'))
            .maxLines(1)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // ---- 内容区：两栏各自可上下滑动 ----
      //
      // ⚠️ 这里**不能用 Scroll**：编译器明确拒绝
      //    `'Scroll' can't support form application`
      // 改用 List：它是卡片支持的滚动容器，两栏各一个、可独立滑动。
      Row() {
        // ============ 左：今天 ============
        Column() {
          Text(this.columnTitle('今天', this.todayJson))
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.card_accent'))
            .maxLines(1)
            .width('100%')

          if (parseCourses(this.todayJson).length === 0) {
            EmptyHint()
          } else {
            List() {
              ForEach(parseCourses(this.todayJson), (c: CardCourse, idx: number) => {
                ListItem() {
                  CardCourseRow({
                    name: c.name,
                    time: c.time,
                    room: c.room,
                    color: c.color,
                    teacher: c.teacher,
                    content: c.content,
                    withGap: idx > 0
                  })
                }
              }, (c: CardCourse, idx: number) => `t_${idx}_${c.name}_${c.time}`)
            }
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
            .width('100%')
            .layoutWeight(1)
          }
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(HorizontalAlign.Start)

        // 中间竖分隔线
        //
        // ⚠️ margin 从 10 减到 6：窄卡片里左右各 10 会吃掉 20px，
        // 两栏各剩不到一半，课名直接被压没。
        Divider()
          .vertical(true)
          .color($r('app.color.card_divider'))
          .margin({ left: 6, right: 6 })

        // ============ 右：明天 ============
        Column() {
          Text(this.columnTitle(this.tomorrowLabel, this.tomorrowJson))
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.card_sub'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          if (parseCourses(this.tomorrowJson).length === 0) {
            EmptyHint()
          } else {
            List() {
              ForEach(parseCourses(this.tomorrowJson), (c: CardCourse, idx: number) => {
                ListItem() {
                  CardCourseRow({
                    name: c.name,
                    time: c.time,
                    room: c.room,
                    color: c.color,
                    teacher: c.teacher,
                    content: c.content,
                    withGap: idx > 0
                  })
                }
              }, (c: CardCourse, idx: number) => `m_${idx}_${c.name}_${c.time}`)
            }
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
            .width('100%')
            .layoutWeight(1)
          }
        }
        .layoutWeight(1)
        .height('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(VerticalAlign.Top)
      .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /**
   * 栏目标题：`今天 · 2 节`
   *
   * 带上节数，用户一眼知道这天有几节课、要不要往下滑。
   */
  private columnTitle(base: string, json: string): string {
    const n = parseCourses(json).length;
    if (n === 0) {
      return base;
    }
    return `${base} · ${n} 节`;
  }
}

/** 某一天没有课时显示的空状态（语气参考截图里的「今天没有课啦」） */
@Component
struct EmptyHint {
  build() {
    Column() {
      Text('(・∀・)')
        .fontSize(FontSize.bodyStrong)
        .fontColor($r('app.color.card_sub'))
      Text('今天没有课啦')
        .fontSize(FontSize.smallBody)
        .fontColor($r('app.color.card_sub'))
        .margin({ top: 3 })
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

/**
 * 2*2 紧凑布局的空状态。
 *
 * 空间小得多，去掉颜文字只留一行，避免把标题挤掉。
 */
@Component
struct CompactEmptyHint {
  build() {
    Column() {
      Text('今天没有课啦')
        .fontSize(FontSize.smallBody)
        .fontColor($r('app.color.card_sub'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

/**
 * 2*2 紧凑布局的一行课程。
 *
 * ```
 * ● 系统解剖学         08:00
 *   教学馆 301
 * ```
 *
 * 与标准布局的 CardCourseRow 的区别：
 * - **不显示上课内容**：小尺寸下一行内容会把课名挤掉，得不偿失；
 * - **时间截短**：只显示开始时间（08:00），不显示 `08:00-10:30` 整段；
 * - 地点单独一行，不显示老师（小卡片塞不下三项）。
 *
 * ## 深色模式
 *
 * 所有文字颜色走 `$r('app.color.*')`，由 dark/element/color.json 自动适配，
 * 无任何硬编码前景色。色点保留课程原色（有意设计：色点是课程标识，
 * 深色下依然鲜艳可辨，与课表页保持一致）。
 */
@Component
struct CompactCourseRow {
  @Prop name: string = '';
  @Prop time: string = '';
  @Prop room: string = '';
  @Prop color: string = '';
  @Prop teacher: string = '';
  @Prop content: string = '';
  @Prop withGap: boolean = false;

  build() {
    Row() {
      // 色点：与课表页同一套配色
      Circle({ width: 7, height: 7 })
        .fill(dotColorOf(this.color, $r('app.color.card_accent')))
        .margin({ top: 5, right: 6 })

      Column() {
        // ---- 第 1 行：课名 + 开始时间 ----
        Row() {
          Text(this.name)
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.card_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (startTimeOf(this.time).length > 0) {
            Text(startTimeOf(this.time))
              .fontSize(FontSize.caption)
              .fontColor($r('app.color.card_sub'))
              .maxLines(1)
              .flexShrink(0)
              .margin({ left: 5 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        // ---- 第 2 行：老师 · 地点 ----
        if (teacherRoomTextOf(this.teacher, this.room).length > 0) {
          Text(teacherRoomTextOf(this.teacher, this.room))
            .fontSize(10.5)
            .fontColor($r('app.color.card_sub'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 1 })
        }

        // ---- 第 3 行：上课内容（最多两行，靠滚动查看其它课程） ----
        //
        // 2*2 里每门课给 2 行内容已经是上限：再多会把课程列表挤到
        // 一屏只显示一门课，反而不好扫读。完整内容去 App 里点开看。
        if (this.content.length > 0) {
          Text(this.content)
            .fontSize(10.5)
            .fontColor($r('app.color.card_sub'))
            .opacity(0.85)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 1 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: this.withGap ? 10 : 0 })
  }



}

/**
 * 一行课程。
 *
 * ## 视觉层级（按重要性递减）
 *
 * ```
 * ● 系统解剖学                  08:00-09:25     ← 课名(13 粗) + 时间(10 灰)
 *   王老师 · 教学馆 301                           ← 老师 · 地点 (11 灰)
 *   纵隔与胸膜                                     ← 上课内容 (11 浅灰, 最多两行)
 * ```
 *
 * 三条设计考虑：
 * 1. **课名最大最粗**：一眼扫过去先看到上什么课；
 * 2. **时间靠右小字**：不抢课名的位置，但抬眼看得到；
 * 3. **内容用更浅的颜色 + 允许两行**：它是补充信息，
 *    降一级对比度既区分层级，也不会让卡片显得杂乱。
 *
 * ## 两个必须遵守的写法（踩过坑）
 *
 * ⚠️ 必须是 @Component + @Prop，不能写成带参数的 @Builder：
 * @Builder 按值传参不会随参数变化重新求值，
 * 会导致「数据到了但列表一直是空的」（详见文件头注释）。
 */
@Component
struct CardCourseRow {
  @Prop name: string = '';
  @Prop time: string = '';
  @Prop room: string = '';
  @Prop color: string = '';
  @Prop teacher: string = '';
  @Prop content: string = '';
  @Prop withGap: boolean = false;

  build() {
    Row() {
      // 色点：与课表页同一套配色，方便把卡片和课表对照着看
      Circle({ width: 8, height: 8 })
        .fill(dotColorOf(this.color, $r('app.color.card_accent')))
        .margin({ top: 5, right: 6 })

      Column() {
        // ---- 第 1 行：课名（占满剩余宽度）+ 时间（靠右小字） ----
        //
        // ⚠️ 两个必须遵守的约束（真机上踩过）：
        //
        // 1. 时间 `flexShrink(0)`：Row 默认允许子项按比例压缩。
        //    不加这条时，时间会被截断成「08:45-」，
        //    同时把课名压到宽度 0 完全消失（截图就是这个现象）。
        // 2. 时间**只显示开始时间**：数据里可能是「08:00-10:30」，
        //    在双栏的窄栏里根本放不下，必然省略成「08:00-…」。
        //    卡片是速览场景，用户只需要知道几点开始。
        Row() {
          Text(this.name)
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.card_text'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (startTimeOf(this.time).length > 0) {
            Text(startTimeOf(this.time))
              .fontSize(FontSize.caption)
              .fontColor($r('app.color.card_sub'))
              .maxLines(1)
              .flexShrink(0)
              .margin({ left: 6 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        // ---- 第 2 行：老师 · 地点 ----
        if (teacherRoomTextOf(this.teacher, this.room).length > 0) {
          Text(teacherRoomTextOf(this.teacher, this.room))
            .fontSize(FontSize.small)
            .fontColor($r('app.color.card_sub'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 2 })
        }

        // ---- 第 3 行：上课内容（更浅，最多两行） ----
        //
        // 用 card_sub 再叠 opacity 0.85 而不是用独立色值：
        // 这样浅色/深色两套主题都由资源限定词目录统一控制，
        // 不会出现「深色下这个半透明色恰好看不见」的问题。
        if (this.content.length > 0) {
          Text(this.content)
            .fontSize(FontSize.small)
            .fontColor($r('app.color.card_sub'))
            .opacity(0.85)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 1 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: this.withGap ? 12 : 0 })
  }



}
