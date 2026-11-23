/**
 * 演示数据实现：让 UI 不依赖接口也能跑起来、能截图、能讨论交互。
 * 登录页的「先用演示数据看看」走这里。
 *
 * 移植自 Android 版 data/Jw.kt 的 FakeJw。
 */
import { Course, Grade, TimetableConfig } from '../core/Models';
import { DefaultPeriods } from '../core/Periods';
import { todayStart, addWeeks, mondayOf, addDays } from '../core/DateUtils';
import { JwService } from './RealJw';

export class FakeJw implements JwService {
  async timetableConfig(): Promise<TimetableConfig> {
    // 演示用：把「第一周周一」定成 5 周前，这样「当前周」= 第 6 周，看起来自然
    const monday = mondayOf(todayStart());
    return {
      termName: '2025-2026 学年第二学期（演示）',
      firstMonday: addWeeks(monday, -5),
      totalWeeks: 20,
      periods: DefaultPeriods.ALL
    };
  }

  async timetable(week?: number): Promise<Course[]> {
    return demoCourses();
  }

  async grades(term?: string): Promise<Grade[]> {
    return demoGrades();
  }

  async termCourses(): Promise<Course[]> {
    const all: Course[] = demoCourses();
    for (const e of demoExams()) {
      all.push(e);
    }
    return all;
  }

  async examNumbers(term?: string): Promise<Map<string, string>> {
    const m = new Map<string, string>();
    m.set('药理学', '7667619');
    m.set('临床诊断学', '7667621');
    return m;
  }

  async semesterCode(): Promise<string | undefined> {
    return undefined;
  }

  async probeSession(): Promise<boolean> {
    // 只有真接口才知道登录态
    return false;
  }
}

function range(from: number, to: number): number[] {
  const out: number[] = [];
  for (let i = from; i <= to; i++) {
    out.push(i);
  }
  return out;
}

function oddWeeks(from: number, to: number): number[] {
  const out: number[] = [];
  for (let i = from; i <= to; i++) {
    if (i % 2 === 1) {
      out.push(i);
    }
  }
  return out;
}

function demoCourses(): Course[] {
  const allWeeks = range(1, 16);
  const odd = oddWeeks(1, 16);
  const firstHalf = range(1, 9);

  return [
    {
      id: 'c1', name: '系统解剖学', teacher: '王老师', room: '教学馆 301',
      dayOfWeek: 1, startSection: 1, endSection: 2, weeks: allWeeks, content: '纵隔与胸膜'
    },
    {
      id: 'c2', name: '生理学', teacher: '李老师', room: '教学馆 205',
      dayOfWeek: 1, startSection: 3, endSection: 4, weeks: firstHalf, content: '血液循环'
    },
    {
      id: 'c3', name: '大学英语', teacher: '陈老师', room: '外语楼 402',
      dayOfWeek: 2, startSection: 1, endSection: 2, weeks: allWeeks
    },
    {
      id: 'c4', name: '诊断学', teacher: '周老师', room: '临床楼 114',
      dayOfWeek: 2, startSection: 5, endSection: 6, weeks: odd, content: '体格检查'
    },
    {
      id: 'c5', name: '生物化学', teacher: '赵老师', room: '基础楼 502',
      dayOfWeek: 3, startSection: 3, endSection: 4, weeks: allWeeks, content: '糖代谢'
    },
    {
      id: 'c6', name: '病理学', teacher: '孙老师', room: '基础楼 108',
      dayOfWeek: 4, startSection: 1, endSection: 3, weeks: allWeeks, content: '炎症与修复'
    },
    {
      id: 'c7', name: '医学统计学', teacher: '郑老师', room: '计算机教室 3',
      dayOfWeek: 5, startSection: 5, endSection: 6, weeks: allWeeks
    },
    {
      id: 'c8', name: '体育（游泳）', teacher: '刘老师', room: '体育馆',
      dayOfWeek: 6, startSection: 1, endSection: 2, weeks: odd
    },
    {
      id: 'c9', name: '医学统计学', teacher: '郑老师',
      dayOfWeek: 1, startSection: 5, endSection: 6, weeks: allWeeks,
      content: '自主学习：SPSS 上机练习', isSelfStudy: true
    },
    // 晚课：专门用来验证 11~14 节能不能正常显示（第 11 节 20:15 开始）
    {
      id: 'c10', name: '马克思主义基本原理', teacher: '吴老师', room: '教学馆 101',
      dayOfWeek: 2, startSection: 11, endSection: 12, weeks: allWeeks, content: '专题讨论'
    },
    {
      id: 'c11', name: '医学文献检索', teacher: '何老师', room: '图书馆 401',
      dayOfWeek: 4, startSection: 11, endSection: 12, weeks: allWeeks
    },
    {
      id: 'c12', name: '临床技能训练', teacher: '林老师', room: '临床技能中心',
      dayOfWeek: 6, startSection: 13, endSection: 14, weeks: odd, content: '夜间开放练习'
    }
  ];
}

/** 演示用的考试（日期是相对今天算的，保证一定在「近期」里） */
function demoExams(): Course[] {
  return [
    {
      id: 'e1', name: '药理学', room: '304机房',
      dayOfWeek: 1, startSection: 3, endSection: 4, weeks: [14],
      date: addDays(todayStart(), 6), isExam: true
    },
    {
      id: 'e2', name: '临床诊断学', room: '诊断学实验室(实验楼)(本部)',
      dayOfWeek: 4, startSection: 8, endSection: 9, weeks: [17],
      date: addDays(todayStart(), 21), isExam: true
    }
  ];
}

function demoGrades(): Grade[] {
  return [
    { course: '系统解剖学', term: '2025-2026-2', score: 91.0, gpa: 4.1, credit: 4.0, kind: '必修' },
    { course: '生理学', term: '2025-2026-2', score: 85.0, gpa: 3.5, credit: 3.5, kind: '必修' },
    { course: '大学英语', term: '2025-2026-2', score: 88.0, gpa: 3.8, credit: 3.0, kind: '必修' },
    { course: '医学统计学', term: '2025-2026-2', score: 79.0, gpa: 2.9, credit: 2.0, kind: '必修' },
    { course: '医德修养', term: '2025-2026-2', level: '优秀', gpa: 4.5, credit: 1.0, kind: '选修' },
    { course: '生物化学', term: '2025-2026-1', score: 93.0, gpa: 4.3, credit: 4.0, kind: '必修' }
  ];
}
