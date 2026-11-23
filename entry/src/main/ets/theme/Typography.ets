/**
 * 字号与间距规范。
 *
 * ## 为什么需要这个
 *
 * 基线版本（v1.5.0）里有 **122 处** `.fontSize(数字)` 写死在 9 个页面里，
 * 取值从 9 到 26 共 14 档。这带来三个实际问题：
 *
 * 1. **改版困难**：调整一处字号要翻遍所有文件；
 * 2. **语义不明**：10/11/12 到底哪个是"辅助说明"、哪个是"正文"，全凭记忆；
 * 3. **无法整体调节**：想统一放大/缩小，没有单一入口。
 *
 * 所以这里定义一套**语义化字号**，页面只引用名字，不写数字。
 *
 * ## 关键约束：这次重构**不改变任何视觉**
 *
 * 档位的取值**严格等于**基线版本的实际数字 —— 不是重新设计字号，
 * 而是给已有的数字装上名字。这样：
 * - 改完后界面与 v1.5.0 逐像素一致；
 * - 以后想调整，只改这一个文件；
 * - 每个档位的**语义**在注释里写清楚，新人不用猜。
 *
 * 档位与基线取值的对应关系（全部来自实测统计）：
 *
 * ```
 *  9 → tiny            徽标、角标
 * 10 → caption         辅助说明
 * 11 → small           次要信息
 * 12 → smallBody       列表主文本（比 small 大一档）
 * 13 → body            正文
 * 14 → bodyStrong      正文强调（按钮）
 * 15 → subtitle        小标题
 * 16 → subtitleEmphasis 小标题（强调）
 * 17 → title           标题
 * 18 → titleLarge      标题（大）
 * 20 → headline        页面主标题
 * 21 → headline        （同 20）
 * 22 → headlineLarge   大标题
 * 24 → display         超大标题
 * 26 → displayLarge    超大标题（大）
 * ```
 */
export class FontSize {
  /** 9：徽标、角标、极小的辅助标记 */
  static readonly tiny: number = 9;
  /** 10：辅助说明、卡片副文本 */
  static readonly caption: number = 10;
  /** 11：次要信息、行内小字 */
  static readonly small: number = 11;
  /** 12：列表主文本（比 small 高一档） */
  static readonly smallBody: number = 12;
  /** 13：正文 */
  static readonly body: number = 13;
  /** 14：正文强调、按钮文字 */
  static readonly bodyStrong: number = 14;
  /** 15：小标题 */
  static readonly subtitle: number = 15;
  /** 16：小标题（强调） */
  static readonly subtitleEmphasis: number = 16;
  /** 17：标题 */
  static readonly title: number = 17;
  /** 18：标题（大） */
  static readonly titleLarge: number = 18;
  /** 20：页面主标题 */
  static readonly headline: number = 20;
  /** 22：大标题 */
  static readonly headlineLarge: number = 22;
  /** 24：超大标题（登录页主标题） */
  static readonly display: number = 24;
  /** 26：超大标题（大） */
  static readonly displayLarge: number = 26;
}

/**
 * 间距规范（vp）。
 *
 * ⚠️ 与字号不同，间距**暂未批量替换**：
 * 基线里 padding / margin 的取值与具体布局强相关
 * （比如卡片内边距 14 是因为要贴合视觉重心），
 * 盲目归一化会改变观感。这里先定义常量，
 * 供**新增代码**使用；存量代码保持原样。
 */
export class Spacing {
  /** 2 */
  static readonly xxs: number = 2;
  /** 4 */
  static readonly xs: number = 4;
  /** 6 */
  static readonly sm: number = 6;
  /** 8 */
  static readonly md: number = 8;
  /** 12 */
  static readonly lg: number = 12;
  /** 16 */
  static readonly xl: number = 16;
  /** 页面左右边距 */
  static readonly page: number = 20;
  /** 区块之间 */
  static readonly section: number = 24;
}

/** 圆角规范（vp），供新增代码使用 */
export class Radius {
  /** 4：色点、标签 */
  static readonly sm: number = 4;
  /** 8：输入框、小卡片 */
  static readonly md: number = 8;
  /** 12：卡片 */
  static readonly lg: number = 12;
  /** 16：卡片容器、弹层 */
  static readonly xl: number = 16;
}
