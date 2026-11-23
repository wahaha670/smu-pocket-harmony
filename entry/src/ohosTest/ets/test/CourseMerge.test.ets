/**
 * 课程合并逻辑单测。
 *
 * 覆盖「用按周查询的富数据补全整学期缓存」这条关键路径。
 * 对应的问题：整学期总表缺 sknrjj（上课内容），实测 220 条里仅 43 条有值，
 * 只有翻过、且在线的那几周才有内容。
 *
 * 运行：DevEco Studio 里右键本文件 Run，或
 *   hvigorw test --project-path D:\HarmonyOS\smu-pocket
 */
import { describe, it, expect } from '@ohos/hypium';
import { Course } from '../../../../main/ets/core/Models';
import {
  isSameCourse,
  pickText,
  enrichCourse,
  mergeWeekIntoTerm,
  weekMissingContent
} from '../../../../main/ets/core/CourseMerge';

/** 造一条课程，只写关心的字段 */
function course(
  name: string,
  day: number,
  start: number,
  end: number,
  weeks: number[],
  content?: string,
  id?: string
): Course {
  return {
    id: id !== undefined ? id : `id_${name}_${day}_${start}`,
    name: name,
    teacher: '',
    room: '',
    dayOfWeek: day,
    startSection: start,
    endSection: end,
    weeks: weeks,
    content: content
  };
}

export default function courseMergeTest() {
  describe('isSameCourse', () => {
    it('matchesSameNameDayStart', 0, () => {
      const a = course('呼吸系统', 2, 3, 4, [1]);
      const b = course('呼吸系统', 2, 3, 5, [2]); // 跨度不同
      // 刻意不比较 endSection：两种查询对跨节判定偶有差异
      expect(isSameCourse(a, b)).assertTrue();
    });

    it('rejectsDifferentName', 0, () => {
      const a = course('呼吸系统', 2, 3, 4, [1]);
      const b = course('消化系统', 2, 3, 4, [1]);
      expect(isSameCourse(a, b)).assertFalse();
    });

    it('rejectsDifferentDay', 0, () => {
      const a = course('呼吸系统', 2, 3, 4, [1]);
      const b = course('呼吸系统', 3, 3, 4, [1]);
      expect(isSameCourse(a, b)).assertFalse();
    });

    it('rejectsDifferentStartSection', 0, () => {
      const a = course('呼吸系统', 2, 3, 4, [1]);
      const b = course('呼吸系统', 2, 5, 6, [1]);
      expect(isSameCourse(a, b)).assertFalse();
    });
  });

  describe('pickText', () => {
    it('prefersFirstNonEmpty', 0, () => {
      expect(pickText('a', 'b')).assertEqual('a');
    });

    it('fallsBackToSecondWhenFirstEmpty', 0, () => {
      expect(pickText('', 'b')).assertEqual('b');
    });

    it('returnsUndefinedWhenBothEmpty', 0, () => {
      expect(pickText('', '')).assertUndefined();
    });

    it('handlesUndefinedInputs', 0, () => {
      expect(pickText(undefined, 'b')).assertEqual('b');
      expect(pickText(undefined, undefined)).assertUndefined();
    });
  });

  describe('enrichCourse', () => {
    it('fillsContentFromWeekly', 0, () => {
      const base = course('呼吸系统', 2, 3, 4, [1, 2, 3]);  // 整学期：无内容
      const fresh = course('呼吸系统', 2, 3, 4, [2], '慢性阻塞性肺疾病'); // 按周：有内容
      const merged = enrichCourse(base, fresh);
      expect(merged.content).assertEqual('慢性阻塞性肺疾病');
    });

    it('prefersWeeklyRoomOverTermRoom', 0, () => {
      // ⚠️ 核心修复：整学期给的是多教室拼接，按周才是当周精确教室
      const base = course('综合高级英语', 1, 1, 2, [1, 2, 4, 7, 9, 12, 14]);
      base.room = '207教室,403教室,408教室,604教室';
      const fresh = course('综合高级英语', 1, 1, 2, [12], '课程内容');
      fresh.room = '604教室';
      const merged = enrichCourse(base, fresh);
      expect(merged.room).assertEqual('604教室');
      expect(merged.content).assertEqual('课程内容');
    });

    it('keepsBaseRoomWhenWeeklyHasNone', 0, () => {
      const base = course('X', 1, 1, 2, [1]);
      base.room = '504智慧教室';
      const fresh = course('X', 1, 1, 2, [1], '内容');
      expect(enrichCourse(base, fresh).room).assertEqual('504智慧教室');
    });

    it('keepsBaseWeeksNotFreshWeeks', 0, () => {
      // ⚠️ 关键：必须保留 base 的多周，否则该课在其它周会消失
      const base = course('呼吸系统', 2, 3, 4, [1, 2, 3]);
      const fresh = course('呼吸系统', 2, 3, 4, [2], '内容');
      const merged = enrichCourse(base, fresh);
      expect(merged.weeks.length).assertEqual(3);
      expect(merged.weeks[0]).assertEqual(1);
      expect(merged.weeks[2]).assertEqual(3);
    });

    it('keepsBaseIdNotFreshId', 0, () => {
      const base = course('呼吸系统', 2, 3, 4, [1], '', 'term_id');
      const fresh = course('呼吸系统', 2, 3, 4, [1], '内容', 'weekly_id');
      expect(enrichCourse(base, fresh).id).assertEqual('term_id');
    });

    it('doesNotOverwriteExistingContent', 0, () => {
      const base = course('呼吸系统', 2, 3, 4, [1], '原有内容');
      const fresh = course('呼吸系统', 2, 3, 4, [1], '新内容');
      expect(enrichCourse(base, fresh).content).assertEqual('原有内容');
    });

    it('fillsTeacherAndRoomWhenBaseEmpty', 0, () => {
      const base = course('呼吸系统', 2, 3, 4, [1]);
      const fresh = course('呼吸系统', 2, 3, 4, [1], '内容');
      fresh.teacher = '张老师';
      fresh.room = '504智慧教室';
      const merged = enrichCourse(base, fresh);
      expect(merged.teacher).assertEqual('张老师');
      expect(merged.room).assertEqual('504智慧教室');
    });
  });

  describe('mergeWeekIntoTerm', () => {
    it('fillsContentForMatchedCourse', 0, () => {
      const term: Course[] = [course('呼吸系统', 2, 3, 4, [1, 2, 3])];
      const fresh: Course[] = [course('呼吸系统', 2, 3, 4, [2], '肺炎')];
      const result = mergeWeekIntoTerm(term, fresh, 2);
      expect(result.length).assertEqual(1);
      expect(result[0].content).assertEqual('肺炎');
      expect(result[0].weeks.length).assertEqual(3); // 多周保持不变
    });

    it('appendsCourseNotInTerm', 0, () => {
      const term: Course[] = [course('呼吸系统', 2, 3, 4, [1, 2])];
      const fresh: Course[] = [course('新增课', 5, 6, 7, [2], '内容')];
      const result = mergeWeekIntoTerm(term, fresh, 2);
      expect(result.length).assertEqual(2);
    });

    it('doesNotMergeWhenTermRowNotCoveringWeek', 0, () => {
      // 整学期这条只在第 1 周，但我们要合并第 5 周 → 不应命中，应追加
      const term: Course[] = [course('呼吸系统', 2, 3, 4, [1])];
      const fresh: Course[] = [course('呼吸系统', 2, 3, 4, [5], '内容')];
      const result = mergeWeekIntoTerm(term, fresh, 5);
      expect(result.length).assertEqual(2);
    });

    it('doesNotMutateInput', 0, () => {
      const term: Course[] = [course('呼吸系统', 2, 3, 4, [1, 2])];
      const before = term[0].content;
      mergeWeekIntoTerm(term, [course('呼吸系统', 2, 3, 4, [2], '新')], 2);
      // 入参对象不应被改动
      expect(term[0].content).assertEqual(before);
    });

    it('returnsSameWhenFreshEmpty', 0, () => {
      const term: Course[] = [course('呼吸系统', 2, 3, 4, [1])];
      const result = mergeWeekIntoTerm(term, [], 1);
      expect(result.length).assertEqual(1);
    });

    it('mergesAllWeeksSequentially', 0, () => {
      // 模拟「补全全部周」：20 周逐周合并，每周补一门课的内容
      let term: Course[] = [];
      for (let w = 1; w <= 20; w++) {
        term.push(course(`课程${w}`, 1, 1, 2, [w]));
      }
      expect(term.length).assertEqual(20);

      for (let w = 1; w <= 20; w++) {
        const fresh: Course[] = [course(`课程${w}`, 1, 1, 2, [w], `第${w}周内容`)];
        term = mergeWeekIntoTerm(term, fresh, w);
      }
      // 仍然是 20 条，且全部有内容
      expect(term.length).assertEqual(20);
      let withContent = 0;
      for (const c of term) {
        if (c.content !== undefined && c.content.length > 0) {
          withContent++;
        }
      }
      expect(withContent).assertEqual(20);
    });
  });

  describe('weekMissingContent', () => {
    it('trueWhenAnyMissing', 0, () => {
      const cs: Course[] = [
        course('A', 1, 1, 2, [1], '有内容'),
        course('B', 2, 1, 2, [1])          // 无内容
      ];
      expect(weekMissingContent(cs)).assertTrue();
    });

    it('falseWhenAllHaveContent', 0, () => {
      const cs: Course[] = [
        course('A', 1, 1, 2, [1], '有内容'),
        course('B', 2, 1, 2, [1], '也有')
      ];
      expect(weekMissingContent(cs)).assertFalse();
    });

    it('falseWhenEmptyList', 0, () => {
      // 空周不该被判定为「缺内容」，否则会误提示
      expect(weekMissingContent([])).assertFalse();
    });
  });
}
