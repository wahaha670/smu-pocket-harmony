/**
 * 作息时间表（第 1~14 节的起止时刻）。
 *
 * 教务**没有**「每节课几点上」的接口 —— `qssj`/`jssj` 是**每门课**的起止时刻，
 * 不是每节课的。所以这张表只能本地维护。
 *
 * 1~12 节不是拍脑袋写的，而是用真实抓包的 `ps`/`pe` + `qssj`/`jssj` 反推出来的。
 * 每节课 40 分钟，相邻两节之间休息 5 分钟，大节（上午/下午/晚上）之间休息 20 分钟：
 *
 * ```
 * ps=01 pe=02 → 08:00-09:25      ps=06 pe=08 → 14:30-16:55
 * ps=03 pe=04 → 09:50-11:15      ps=06 pe=09 → 14:30-17:40
 * ps=03 pe=05 → 09:50-12:00      ps=08 pe=09 → 16:15-17:40
 * ps=10 pe=12 → 19:30-21:40
 * ```
 *
 * 第 13、14 节真实抓包里还没出现过，按同样的节奏往后顺延（21:45 / 22:30）。
 * 学校若改了作息，改这一处即可。
 *
 * 移植自 Android 版 core/Periods.kt。
 */
import { Period } from './Models';

export class DefaultPeriods {
  static readonly ALL: Period[] = [
    // 上午
    { index: 1, start: '08:00', end: '08:40' },
    { index: 2, start: '08:45', end: '09:25' },
    { index: 3, start: '09:50', end: '10:30' },
    { index: 4, start: '10:35', end: '11:15' },
    { index: 5, start: '11:20', end: '12:00' },
    // 下午
    { index: 6, start: '14:30', end: '15:10' },
    { index: 7, start: '15:15', end: '15:55' },
    { index: 8, start: '16:15', end: '16:55' },
    { index: 9, start: '17:00', end: '17:40' },
    // 晚上（晚课会一直排到 11~14 节）
    { index: 10, start: '19:30', end: '20:10' },
    { index: 11, start: '20:15', end: '20:55' },
    { index: 12, start: '21:00', end: '21:40' },
    { index: 13, start: '21:45', end: '22:25' },
    { index: 14, start: '22:30', end: '23:10' }
  ];

  /** 取一节的作息；没有就返回 undefined */
  static at(section: number): Period | undefined {
    for (const p of DefaultPeriods.ALL) {
      if (p.index === section) {
        return p;
      }
    }
    return undefined;
  }
}
