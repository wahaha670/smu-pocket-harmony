/**
 * 周次与学期换算的单测。
 *
 * 这些用例直接对应原 Android 版 tests/SemesterTest.kt / TermCodeTest.kt，
 * 用来验证移植后的日期/周次逻辑与原版完全等价。
 *
 * 运行：DevEco Studio 里右键本文件 Run，或
 *   hvigorw test --project-path D:\HarmonyOS\smu-pocket
 */
import { describe, it, expect } from '@ohos/hypium';
import { Semester } from '../../../../main/ets/core/Semester';
import { TermCode } from '../../../../main/ets/core/TermCode';
import { makeDate, addDays, dayOfWeek, parseDate, formatDate } from '../../../../main/ets/core/DateUtils';

export default function semesterTest() {
  describe('Semester', () => {
    // 2025-09-01 是周一，当作第 1 周周一
    const firstMonday = makeDate(2025, 9, 1);

    it('firstMondayIsWeek1', 0, () => {
      expect(Semester.weekOf(firstMonday, firstMonday)).assertEqual(1);
    });

    it('sundayBelongsToSameWeek', 0, () => {
      expect(Semester.weekOf(makeDate(2025, 9, 7), firstMonday)).assertEqual(1);
    });

    it('nextMondayIsWeek2', 0, () => {
      expect(Semester.weekOf(makeDate(2025, 9, 8), firstMonday)).assertEqual(2);
    });

    it('lastSundayOfWeek8', 0, () => {
      expect(Semester.weekOf(makeDate(2025, 10, 26), firstMonday)).assertEqual(8);
    });

    it('beforeTermIsNotWeek1', 0, () => {
      const w = Semester.weekOf(makeDate(2025, 8, 25), firstMonday);
      expect(w <= 0).assertTrue();
    });

    it('clampKeepsInsideRange', 0, () => {
      expect(Semester.clampWeek(25, 20)).assertEqual(20);
      expect(Semester.clampWeek(0, 20)).assertEqual(1);
      expect(Semester.clampWeek(3, 0)).assertEqual(1);
    });

    it('datesOfWeekStartsOnMonday', 0, () => {
      const dates = Semester.datesOfWeek(3, firstMonday);
      expect(dates.length).assertEqual(7);
      expect(formatDate(dates[0])).assertEqual('2025-09-15');
      expect(formatDate(dates[6])).assertEqual('2025-09-21');
    });

    it('parseSimpleRange', 0, () => {
      const w = Semester.parseWeeks('1-16');
      expect(w.length).assertEqual(16);
      expect(w[0]).assertEqual(1);
      expect(w[15]).assertEqual(16);
    });

    it('parseCommaList', 0, () => {
      const w = Semester.parseWeeks('1,3,5,7');
      expect(w.join(',')).assertEqual('1,3,5,7');
    });

    it('parseOddWeeks', 0, () => {
      const w = Semester.parseWeeks('1-16(单)');
      expect(w.join(',')).assertEqual('1,3,5,7,9,11,13,15');
    });

    it('parseEvenWeeks', 0, () => {
      const w = Semester.parseWeeks('2-16双');
      expect(w.join(',')).assertEqual('2,4,6,8,10,12,14,16');
    });

    it('parseSingleWeekWithChinesePrefix', 0, () => {
      const w = Semester.parseWeeks('第3周');
      expect(w.join(',')).assertEqual('3');
    });

    it('parseMixesFullWidthComma', 0, () => {
      const w = Semester.parseWeeks('2，4');
      expect(w.join(',')).assertEqual('2,4');
    });

    it('parseRespectsTotalWeeks', 0, () => {
      const w = Semester.parseWeeks('1-20', 16);
      expect(w.length).assertEqual(16);
    });

    it('parseBlankIsEmpty', 0, () => {
      expect(Semester.parseWeeks('').length).assertEqual(0);
      expect(Semester.parseWeeks('   ').length).assertEqual(0);
    });
  });

  describe('TermCode', () => {
    it('convertsDashDisplayName', 0, () => {
      expect(TermCode.fromDisplayName('2026-2027-1')).assertEqual('202601');
      expect(TermCode.fromDisplayName('2025-2026-2')).assertEqual('202502');
    });

    it('convertsChineseDisplayName', 0, () => {
      expect(TermCode.fromDisplayName('2026-2027 学年 第 1 学期')).assertEqual('202601');
      expect(TermCode.fromDisplayName('2025-2026 学年 第 2 学期')).assertEqual('202502');
    });

    it('rejectsGarbage', 0, () => {
      expect(TermCode.fromDisplayName('')).assertUndefined();
      expect(TermCode.fromDisplayName('2026-2027')).assertUndefined();
      expect(TermCode.fromDisplayName('第 1 学期')).assertUndefined();
    });

    it('expandsShortCode', 0, () => {
      expect(TermCode.displayName('202601')).assertEqual('2026-2027 学年 第 1 学期');
      expect(TermCode.displayName('202502')).assertEqual('2025-2026 学年 第 2 学期');
    });

    it('autumnIsFirstTerm', 0, () => {
      expect(TermCode.fromDate(makeDate(2026, 9, 1))).assertEqual('202601');
      expect(TermCode.fromDate(makeDate(2026, 12, 31))).assertEqual('202601');
    });

    it('januaryStillBelongsToFirstTerm', 0, () => {
      expect(TermCode.fromDate(makeDate(2027, 1, 15))).assertEqual('202601');
    });

    it('springIsSecondTerm', 0, () => {
      expect(TermCode.fromDate(makeDate(2027, 3, 1))).assertEqual('202602');
      expect(TermCode.fromDate(makeDate(2027, 8, 31))).assertEqual('202602');
    });

    // 回归：教务页面下拉里真的有 203402，绝不能当当前学期
    it('rejectsFarFutureAndMalformed', 0, () => {
      const today = makeDate(2026, 11, 2);
      expect(TermCode.isPlausible('203402', today)).assertFalse();
      expect(TermCode.isPlausible('201801', today)).assertFalse();
      expect(TermCode.isPlausible('202603', today)).assertFalse();
      expect(TermCode.isPlausible('202600', today)).assertFalse();
      expect(TermCode.isPlausible('2026', today)).assertFalse();
    });

    it('acceptsNormalTerms', 0, () => {
      const today = makeDate(2026, 11, 2);
      expect(TermCode.isPlausible('202601', today)).assertTrue();
      expect(TermCode.isPlausible('202502', today)).assertTrue();
      expect(TermCode.isPlausible('202702', today)).assertTrue();
    });
  });

  describe('DateUtils', () => {
    it('parseDateHandlesBothFormats', 0, () => {
      expect(formatDate(parseDate('2026-10-23') as number)).assertEqual('2026-10-23');
      expect(formatDate(parseDate('2026-10-23 00:00:00') as number)).assertEqual('2026-10-23');
    });

    it('parseDateRejectsGarbage', 0, () => {
      expect(parseDate('')).assertUndefined();
      expect(parseDate('abc')).assertUndefined();
    });

    it('dayOfWeekMondayIs1', 0, () => {
      // 2026-08-31 是周一
      expect(dayOfWeek(makeDate(2026, 8, 31))).assertEqual(1);
    });

    it('addDaysCrossesMonth', 0, () => {
      expect(formatDate(addDays(makeDate(2026, 10, 31), 1))).assertEqual('2026-11-01');
    });
  });
}
