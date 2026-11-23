/**
 * 公共组件。
 *
 * 对齐 Android 版 ui/components/Common.kt。
 *
 * 全部用 ArkUI **状态管理 V1**（@Prop / @State / @BuilderParam）。
 *
 * ## 关于卡片容器 CardBox 的用法
 *
 * ArkUI 的 `@BuilderParam` **只接受尾随闭包**写法：
 *
 * ```
 * CardBox({ isDark: this.isDark }) {
 *   Text('内容')
 * }
 * ```
 *
 * 不能把普通函数当 prop 传进来再在 build 里调用
 * —— 那会报 `'this.body()' does not meet UI component syntax`。
 */
import { Theme } from '../../theme/Theme';
import { FontSize } from '../../theme/Typography';

/** 圆角卡片容器：用尾随闭包传入内容 */
@Component
export struct CardBox {
  @Prop isDark: boolean = false;
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
    // ⚠️ 不要写 .width('100%') + 左右 margin：
    // 那会让实际宽度 = 100% + 左右边距，卡片右侧溢出屏幕
    // （表现：右侧箭头/徽标被切掉一半）。
    // 用 width('auto') 让 margin 从父容器宽度里"扣"，才是安全的。
    .width('auto')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .margin({ left: 14, right: 14, bottom: 10 })
    .backgroundColor(Theme.colors(this.isDark).surface)
    .borderRadius(14)
  }
}

/** 页面标题 */
@Component
export struct ScreenHeader {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop isDark: boolean = false;

  build() {
    Column() {
      Text(this.title)
        .fontSize(FontSize.headlineLarge)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.colors(this.isDark).onSurface)
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(FontSize.smallBody)
          .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
          .margin({ top: 3 })
          .maxLines(2)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 20, right: 20, top: 16, bottom: 10 })
  }
}

/** 空状态 */
@Component
export struct EmptyHint {
  @Prop text: string = '';
  @Prop isDark: boolean = false;

  build() {
    Column() {
      Text(this.text)
        .fontSize(FontSize.body)
        .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
    }
    .width('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Center)
  }
}

/** 「标签 / 值」一行 */
@Component
export struct LabelValue {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop isDark: boolean = false;
  /**
   * 值的强调色（可选）。
   * 空串表示用普通文字色；传入颜色时值会被高亮，
   * 用于「离线缓存」「未接入」这类需要一眼看到的状态。
   */
  @Prop valueColor: string = '';

  build() {
    Row() {
      Text(this.label)
        .fontSize(FontSize.body)
        .fontColor(Theme.colors(this.isDark).onSurfaceVariant)
        .layoutWeight(1)
      Text(this.value)
        .fontSize(FontSize.body)
        .fontColor(this.valueColor.length > 0
          ? this.valueColor
          : Theme.colors(this.isDark).onSurface)
        .fontWeight(this.valueColor.length > 0 ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(2)
        .textAlign(TextAlign.End)
        .layoutWeight(2)
    }
    .width('100%')
    .padding({ top: 5, bottom: 5 })
    .alignItems(VerticalAlign.Center)
  }
}

/** 「自主」小标签：格子窄时只显示「自主」 */
@Component
export struct SelfStudyChip {
  @Prop compact: boolean = false;
  @Prop isDark: boolean = false;

  build() {
    Text(this.compact ? '自主' : '自主学习')
      .fontSize(this.compact ? 8 : 10)
      // 深色主题下「浅绿底 + 深绿字」会刺眼，改用主题里的深浅两套
      .fontColor(Theme.colors(this.isDark).chipSelfStudyText)
      .padding({ left: 4, right: 4, top: 1, bottom: 1 })
      .backgroundColor(Theme.colors(this.isDark).chipSelfStudyBg)
      .borderRadius(3)
  }
}
