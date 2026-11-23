/**
 * WidgetDate 时间变化测试（ohosTest 单元测试）。
 *
 * 覆盖：跨天、跨周、跨月、跨年、学期边界、精确时刻。
 * 这些是「卡片显示昨天课」这个 bug 的回归防线。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  startOfDay, dayOfWeekOf, weekOfDate, cnWeekdayOf, recomputeForToday, DayFallback
} from '../../../main/ets/core/WidgetDate';

const MS: number = 24 * 60 * 60 * 1000;

/** 2026-08-31 00:00（周一），学期第 1 周起点 */
const FM: number = new Date(2026, 7, 31, 0, 0, 0, 0).getTime();

/** 构造一个「每天一门课」的整学期课表 */
function buildTermDays(totalWeeks: number): TermDayLike[] {
  const out: TermDayLike[] = [];
  for (let w = 1; w <= totalWeeks; w++) {
    for (let d = 1; d <= 7; d++) {
      out.push({
        week: w,
        dayOfWeek: d,
        courses: [{ name: `W${w}D${d}`, time: '08:00', room: 'R', color: '#000', teacher: '', content: '' }]
      });
    }
  }
  return out;
}

interface TermDayLike {
  week: number;
  dayOfWeek: number;
  courses: WidgetCourseLike[];
}

interface WidgetCourseLike {
  name: string;
  time: string;
  room: string;
  color: string;
  teacher: string;
  content: string;
}

const TOTAL: number = 20;
const TERM: TermDayLike[] = buildTermDays(TOTAL);

export default function widgetDateTest() {
  describe('WidgetDate 时间基元', () => {
    it('startOfDay 归一到零点', 0, () => {
      const t = new Date(2026, 7, 31, 15, 30, 45).getTime();
      const s = startOfDay(t);
      const d = new Date(s);
      expect(d.getHours()).assertEqual(0);
      expect(d.getMinutes()).assertEqual(0);
      expect(d.getSeconds()).assertEqual(0);
    });

    it('dayOfWeekOf 周日返回 7 而不是 0', 0, () => {
      // 2026-09-06 是周日
      const sunday = FM + 6 * MS + 10 * 3600000;
      expect(dayOfWeekOf(sunday)).assertEqual(7);
    });

    it('dayOfWeekOf 周一到周六', 0, () => {
      for (let i = 0; i < 6; i++) {
        expect(dayOfWeekOf(FM + i * MS + 3600000)).assertEqual(i + 1);
      }
    });

    it('weekOfDate 第 1 周周一 = 1', 0, () => {
      expect(weekOfDate(FM, FM)).assertEqual(1);
    });

    it('weekOfDate 逐周递增', 0, () => {
      for (let w = 1; w <= TOTAL; w++) {
        const t = FM + (w - 1) * 7 * MS + 3 * MS + 3600000;
        expect(weekOfDate(t, FM)).assertEqual(w);
      }
    });

    it('cnWeekdayOf 1-7', 0, () => {
      const expectArr: string[] = ['一', '二', '三', '四', '五', '六', '日'];
      for (let i = 1; i <= 7; i++) {
        expect(cnWeekdayOf(i)).assertEqual(expectArr[i - 1]);
      }
    });

    it('cnWeekdayOf 越界返回空串', 0, () => {
      expect(cnWeekdayOf(0)).assertEqual('');
      expect(cnWeekdayOf(8)).assertEqual('');
    });
  });

  describe('WidgetDate 跨天', () => {
    it('同一天 24 个时刻算同一天', 0, () => {
      const base = FM + 11 * 7 * MS + 2 * MS; // 第 12 周周三
      for (let h = 0; h < 24; h++) {
        const r = recomputeForToday(base + h * 3600000, FM, TOTAL, TERM, []);
        expect(r.weekText).assertEqual('第 12 周');
        expect(r.dayText).assertEqual('周三');
      }
    });

    it('23:59:59 → 00:00:00 跨越到次日', 0, () => {
      const base = FM + 11 * 7 * MS + 2 * MS;
      const last = base + MS - 1;
      const first = base + MS;
      expect(recomputeForToday(last, FM, TOTAL, TERM, []).dayText).assertEqual('周三');
      expect(recomputeForToday(first, FM, TOTAL, TERM, []).dayText).assertEqual('周四');
    });

    it('跨天后课程内容跟着切换', 0, () => {
      const wed = FM + 11 * 7 * MS + 2 * MS + 10 * 3600000;
      const thu = wed + MS;
      const rWed = recomputeForToday(wed, FM, TOTAL, TERM, []);
      const rThu = recomputeForToday(thu, FM, TOTAL, TERM, []);
      expect(rWed.today[0].name).assertEqual('W12D3');
      expect(rThu.today[0].name).assertEqual('W12D4');
    });

    it('连续 7 天每天都正确', 0, () => {
      const monday = FM + 4 * 7 * MS; // 第 5 周周一
      for (let i = 0; i < 7; i++) {
        const r = recomputeForToday(monday + i * MS + 10 * 3600000, FM, TOTAL, TERM, []);
        expect(r.today[0].name).assertEqual(`W5D${i + 1}`);
      }
    });
  });

  describe('WidgetDate 跨周', () => {
    it('周日看明天 = 下一周周一', 0, () => {
      const sunday = FM + 4 * 7 * MS + 6 * MS + 22 * 3600000; // 第 5 周周日
      const r = recomputeForToday(sunday, FM, TOTAL, TERM, []);
      expect(r.dayText).assertEqual('周日');
      expect(r.tomorrow[0].name).assertEqual('W6D1');
    });

    it('周一零点属于新的一周', 0, () => {
      for (let w = 2; w <= TOTAL; w++) {
        const monday = FM + (w - 1) * 7 * MS + 30 * 60000; // 00:30
        const r = recomputeForToday(monday, FM, TOTAL, TERM, []);
        expect(r.weekText).assertEqual(`第 ${w} 周`);
        expect(r.dayText).assertEqual('周一');
      }
    });

    it('整学期 140 天逐日周次正确', 0, () => {
      for (let i = 0; i < TOTAL * 7; i++) {
        const t = FM + i * MS + 10 * 3600000;
        const r = recomputeForToday(t, FM, TOTAL, TERM, []);
        expect(r.weekText).assertEqual(`第 ${Math.floor(i / 7) + 1} 周`);
      }
    });

    it('最后一周周日 tomorrow 为空（超出学期）', 0, () => {
      const lastSunday = FM + (TOTAL - 1) * 7 * MS + 6 * MS + 22 * 3600000;
      const r = recomputeForToday(lastSunday, FM, TOTAL, TERM, []);
      expect(r.tomorrow.length).assertEqual(0);
    });
  });

  describe('WidgetDate 学期边界', () => {
    it('开学前显示未开学', 0, () => {
      const r = recomputeForToday(FM - MS, FM, TOTAL, TERM, []);
      expect(r.weekText).assertEqual('未开学');
      expect(r.today.length).assertEqual(0);
      expect(r.outOfRange).assertEqual(true);
    });

    it('学期结束后显示学期已结束', 0, () => {
      const r = recomputeForToday(FM + TOTAL * 7 * MS, FM, TOTAL, TERM, []);
      expect(r.weekText).assertEqual('学期已结束');
      expect(r.today.length).assertEqual(0);
    });

    it('开学日 00:00 是第 1 周周一', 0, () => {
      const r = recomputeForToday(FM, FM, TOTAL, TERM, []);
      expect(r.weekText).assertEqual('第 1 周');
      expect(r.dayText).assertEqual('周一');
    });

    it('最后一周仍在范围内', 0, () => {
      const r = recomputeForToday(FM + (TOTAL - 1) * 7 * MS, FM, TOTAL, TERM, []);
      expect(r.weekText).assertEqual(`第 ${TOTAL} 周`);
      expect(r.outOfRange).assertEqual(false);
    });
  });

  describe('WidgetDate 数据兜底', () => {
    it('无 termDays 也无 weekDays → 退回快照', 0, () => {
      const fb: DayFallback = {
        weekText: '旧周',
        dayText: '旧日',
        today: [{ name: '旧课', time: '', room: '', color: '#000', teacher: '', content: '' }],
        tomorrow: [],
        tomorrowLabel: '旧明天'
      };
      const r = recomputeForToday(Date.now(), FM, TOTAL, [], [], fb);
      expect(r.weekText).assertEqual('旧周');
      expect(r.dayText).assertEqual('旧日');
      expect(r.today[0].name).assertEqual('旧课');
    });

    it('只有 weekDays（老版本数据）也能工作', 0, () => {
      const weekDays: DayLike[] = [];
      for (let d = 1; d <= 7; d++) {
        weekDays.push({
          dayOfWeek: d,
          courses: [{ name: `OLD_D${d}`, time: '', room: '', color: '#000', teacher: '', content: '' }]
        });
      }
      const wed = FM + 2 * MS + 10 * 3600000;
      const r = recomputeForToday(wed, FM, TOTAL, [], weekDays);
      expect(r.dayText).assertEqual('周三');
      expect(r.today[0].name).assertEqual('OLD_D3');
    });

    it('firstMonday 为 0 → 退回快照', 0, () => {
      const fb: DayFallback = {
        weekText: 'F', dayText: 'D', today: [], tomorrow: [], tomorrowLabel: 'T'
      };
      const r = recomputeForToday(Date.now(), 0, TOTAL, TERM, [], fb);
      expect(r.outOfRange).assertEqual(true);
      expect(r.weekText).assertEqual('F');
    });
  });

  describe('WidgetDate 明天标签', () => {
    it('明天标签含日期与星期', 0, () => {
      const t = new Date(2026, 10, 18, 10, 0, 0).getTime(); // 2026-11-18
      const r = recomputeForToday(t, FM, TOTAL, TERM, []);
      // 明天 = 11/19 周四
      expect(r.tomorrowLabel.indexOf('11/19')).assertLarger(-1);
      expect(r.tomorrowLabel.indexOf('周四')).assertLarger(-1);
    });
  });
}

interface DayLike {
  dayOfWeek: number;
  courses: WidgetCourseLike[];
}
