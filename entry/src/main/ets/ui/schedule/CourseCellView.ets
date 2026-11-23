/**
 * 课表格子（独立组件）。
 *
 * ## 为什么是独立组件而不是 @Builder
 *
 * `@Builder` 是「当前组件内的一段 UI 片段」，被 ForEach 复用时
 * 参数变化未必重新求值；而 `@Prop` 组件有明确的「入参变 → 重新渲染」语义，
 * 能保证切换周次后格子内容真的更新（这是踩过的坑）。
 *
 * ## 为什么入参全是扁平原始类型
 *
 * 刻意传字符串/布尔/数字，而不是整个 `Course` 对象 ——
 * 避免 `@Prop` 对复杂对象做浅比较时漏更新。
 *
 * ## 两个关键的布局/交互约束（都踩过）
 *
 * 1. **点击必须注册在 `clip` 之前**
 *    `.clip(true)` 会改变 hit test 区域，注册在其后的 `onClick` 收不到事件。
 *    实测表现：点格子毫无反应、也不报错。
 *
 * 2. **必须 `clip(true)` 硬裁切**
 *    格子高度随「跨几节 × 屏幕高度」变化，`maxLines(6)` 只是上限；
 *    高度不够时文字会撑出容器、跑到相邻格子上（截图实测过）。
 */
import { FontSize } from '../../theme/Typography';
import { SelfStudyChip } from '../components/Common';

@Component
export struct CourseCellView {
  @Prop name: string = '';
  @Prop room: string = '';
  @Prop teacher: string = '';
  @Prop content: string = '';
  @Prop isSelfStudy: boolean = false;
  @Prop color: string = '#1F86C7';
  @Prop onColor: string = '#FFFFFF';
  @Prop cellHeight: number = 62;
  @Prop isDark: boolean = false;
  /** 点击回调：由父组件注入，用于弹出课程详情 */
  onTap: () => void = () => {};

  build() {
    Column() {
      // 课程名：最高优先级，加粗
      Text(this.name)
        .fontSize(FontSize.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.onColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.isSelfStudy) {
        SelfStudyChip({ compact: true, isDark: this.isDark })
          .margin({ top: 2 })
      }

      // 地点 / 教师（地点优先，没有地点才显示老师）
      if (this.room.length > 0) {
        Text(this.room)
          .fontSize(FontSize.tiny)
          .fontColor(this.onColor)
          .opacity(0.85)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      } else if (this.teacher.length > 0) {
        Text(this.teacher)
          .fontSize(FontSize.tiny)
          .fontColor(this.onColor)
          .opacity(0.85)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      // 上课内容（sknrjj）
      //
      // 用 layoutWeight(1) 占满剩余高度，而不是写死 maxLines：
      // 格子高度随「跨几节」「屏幕多高」变化，弹性布局能自动适配 ——
      // 单节小格子少显示几行，跨 4 节的大格子多显示几行。
      //
      // opacity 0.9：内容是要读的信息，太淡在彩色底上看不清（0.7 实测偏虚）。
      if (this.content.length > 0) {
        Text(this.content)
          .fontSize(FontSize.tiny)
          .fontColor(this.onColor)
          .opacity(0.9)
          .maxLines(6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .layoutWeight(1)
          .margin({ top: 1 })
      }
    }
    .width('100%')
    .height(this.cellHeight)
    .padding({ left: 3, right: 3, top: 2, bottom: 2 })
    .backgroundColor(this.color)
    .opacity(0.9)
    .borderRadius(6)
    .alignItems(HorizontalAlign.Start)
    // ⚠️ 点击必须在 clip 之前注册（见文件头说明）
    .onClick(() => {
      this.onTap();
    })
    // ⚠️ 硬裁切：任何超出色块的内容都不得渲染到外面
    .clip(true)
  }
}
