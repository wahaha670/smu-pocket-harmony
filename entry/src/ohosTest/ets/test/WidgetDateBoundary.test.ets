/**
 * 卡片日期转换的边界与回归测试（补充 WidgetDate.test.ets 未覆盖的部分）。
 *
 * 重点覆盖在真实数据上容易出错的场景：
 * - 跨周时「明天」的周次计算
 * - 学期最后一周边界
 * - 空数据 / 缺字段的兜底
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  recomputeForToday, weekOfDate, dayOfWeekOf, startOfDay, DayFallback, TermDayCourses
} from '../../../main/ets/core/WidgetDate';

const MS: number = 24 * 60 * 60 * 1000;
/** 2026-08-31 00:00 周一 */
const FM: number = new Date(2026, 7, 31, 0, 0, 0, 0).getTime();

interface C {
  name: string; time: string; room: string; color: string; teacher: string; content: string;
}

function mk(name: string): C {
  return { name: name, time: '08:00', room: 'R', color: '#000', teacher: '', content: '' };
}

function buildTerm(totalWeeks: number): TermDayCourses[] {
  const out: TermDayCourses[] = [];
  for (let w = 1; w <= totalWeeks; w++) {
    for (let d = 1; d <= 7; d++) {
      out.push({ week: w, dayOfWeek: d, courses: [mk(`W${w}D${d}`)] });
    }
  }
  return out;
}

const TOTAL: number = 20;
const TERM: TermDayCourses[] = buildTerm(TOTAL);

export default function widgetDateBoundaryTest() {
  describe('日期转换 - 跨周明天', () => {
    it('周日看明天指向下一周', 0, () => {
      // 第 5 周周日
      const sunday = FM + 4 * 7 * MS + 6 * MS + 22 * 3600000;
      const r = recomputeForToday(sunday, FM, TOTAL, TERM, []);
      expect(r.dayText).assertEqual('周日');
      expect(r.tomorrow.length).assertEqual(1);
      expect(r.tomorrow[0].name).assertEqual('W6D1');
    });

    it('周六看明天仍在同一周', 0, () => {
      const sat = FM + 4 * 7 * MS + 5 * MS + 22 * 3600000;
      const r = recomputeForToday(sat, FM, TOTAL, TERM, []);
      expect(r.dayText).assertEqual('周六');
      expect(r.tomorrow[0].name).assertEqual('W5D7');
    });

    it('周一看明天仍在同一周', 0, () => {
      const mon = FM + 4 * 7 * MS + 10 * 3600000;
      const r = recomputeForToday(mon, FM, TOTAL, TERM, []);
      expect(r.tomorrow[0].name).assertEqual('W5D2');
    });

    it('最后一周周日 tomorrow 为空', 0, () => {
      const lastSun = FM + (TOTAL - 1) * 7 * MS + 6 * MS + 22 * 3600000;
      const r = recomputeForToday(lastSun, FM, TOTAL, TERM, []);
      expect(r.today.length).assertEqual(1);
      expect(r.today[0].name).assertEqual(`W${TOTAL}D7`);
      expect(r.tomorrow.length).assertEqual(0);
    });

    it('倒数第二周周日 tomorrow 正常', 0, () => {
      const sun = FM + (TOTAL - 2) * 7 * MS + 6 * MS + 22 * 3600000;
      const r = recomputeForToday(sun, FM, TOTAL, TERM, []);
      expect(r.tomorrow[0].name).assertEqual(`W${TOTAL}D1`);
    });
  });

  describe('日期转换 - 学期边界', () => {
    it('开学前 1 天', 0, () => {
      const r = recomputeForToday(FM - MS, FM, TOTAL, TERM, []);
      expect(r.weekText).assertEqual('未开学');
      expect(r.outOfRange).assertEqual(true);
    });

    it('开学前 7 天', 0, () => {
      const r = recomputeForToday(FM - 7 * MS, FM, TOTAL, TERM, []);
      expect(r.weekText).assertEqual('未开学');
    });

    it('开学前 30 天', 0, () => {
      const r = recomputeForToday(FM - 30 * MS, FM, TOTAL, TERM, []);
      expect(r.weekText).assertEqual('未开学');
    });

    it('学期结束当天', 0, () => {
      // 第 20 周周日之后一天
      const r = recomputeForToday(FM + TOTAL * 7 * MS, FM, TOTAL, TERM, []);
      expect(r.weekText).assertEqual('学期已结束');
    });

    it('学期结束后 100 天', 0, () => {
      const r = recomputeForToday(FM + TOTAL * 7 * MS + 100 * MS, FM, TOTAL, TERM, []);
      expect(r.weekText).assertEqual('学期已结束');
    });

    it('学期结束后 tomorrowLabel 仍含日期', 0, () => {
      const r = recomputeForToday(FM + TOTAL * 7 * MS + 10 * MS, FM, TOTAL, TERM, []);
      expect(r.tomorrowLabel.indexOf('/')).assertLarger(-1);
    });
  });

  describe('日期转换 - 数据兜底', () => {
    it('termDays 与 weekDays 都空 → 用 fb', 0, () => {
      const fb: DayFallback = {
        weekText: 'FB周', dayText: 'FB日',
        today: [mk('FB课')], tomorrow: [], tomorrowLabel: 'FB明天'
      };
      const r = recomputeForToday(Date.now(), FM, TOTAL, [], [], fb);
      expect(r.weekText).assertEqual('FB周');
      expect(r.today[0].name).assertEqual('FB课');
      expect(r.outOfRange).assertEqual(true);
    });

    it('无 fb 且无数据 → 返回空', 0, () => {
      const r = recomputeForToday(Date.now(), FM, TOTAL, [], []);
      expect(r.today.length).assertEqual(0);
      expect(r.weekText).assertEqual('');
    });

    it('totalWeeks=0 时不判越界', 0, () => {
      // 配置缺失场景：不应把日期判成「未开学/已结束」
      const t = FM + 50 * MS;
      const r = recomputeForToday(t, FM, 0, TERM, []);
      expect(r.outOfRange).assertEqual(false);
      expect(r.weekText.indexOf('第')).assertLarger(-1);
    });

    it('termDays 里缺失某天 → 该天为空而不是报错', 0, () => {
      // 只有第 3 周周三的数据
      const partial: TermDayCourses[] = [{ week: 3, dayOfWeek: 3, courses: [mk('ONLY')] }];
      const wed = FM + 2 * 7 * MS + 2 * MS + 10 * 3600000;
      const r = recomputeForToday(wed, FM, TOTAL, partial, []);
      expect(r.today[0].name).assertEqual('ONLY');

      // 同周周四没有数据 → 空
      const thu = wed + MS;
      const r2 = recomputeForToday(thu, FM, TOTAL, partial, []);
      expect(r2.today.length).assertEqual(0);
    });
  });

  describe('日期转换 - 时刻稳定性', () => {
    it('同一时刻不同分钟结果相同', 0, () => {
      const base = FM + 11 * 7 * MS + 2 * MS;
      const r1 = recomputeForToday(base, FM, TOTAL, TERM, []);
      const r2 = recomputeForToday(base + 12 * 3600000 + 34 * 60000, FM, TOTAL, TERM, []);
      expect(r1.dayText).assertEqual(r2.dayText);
      expect(r1.weekText).assertEqual(r2.weekText);
    });

    it('午夜 00:00 与 23:59 分属不同天', 0, () => {
      const day = FM + 11 * 7 * MS + 2 * MS;
      const r1 = recomputeForToday(day, FM, TOTAL, TERM, []);            // 周三 00:00
      const r2 = recomputeForToday(day + MS - 1, FM, TOTAL, TERM, []);   // 周三 23:59:59
      const r3 = recomputeForToday(day + MS, FM, TOTAL, TERM, []);       // 周四 00:00
      expect(r1.dayText).assertEqual('周三');
      expect(r2.dayText).assertEqual('周三');
      expect(r3.dayText).assertEqual('周四');
    });

    it('weekOfDate 在整个学期单调递增', 0, () => {
      let prev = 0;
      for (let i = 0; i < TOTAL * 7; i++) {
        const w = weekOfDate(FM + i * MS, FM);
        expect(w >= prev).assertEqual(true);
        prev = w;
      }
    });
  });
}
