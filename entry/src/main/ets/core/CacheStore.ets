/**
 * 本地缓存：把最后一次成功拿到的**课表 + 成绩 + 考试**存成 JSON 文件。
 *
 * 注意这里有**两份课表**：
 * - `courses`：课表页当时选中的那一周
 * - `currentCourses`：当时**真实当前周**的课（今日页用）
 *
 * 分两份是因为「今日」必须和「课表选中周」解耦 —— 用户在课表翻到第 8 周，
 * 今日页不能跟着变成第 8 周的课。
 *
 * 移植自 Android 版 core/CacheStore.kt。
 */
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import { Course, Grade, Period, TimetableConfig, TOTAL_SECTIONS } from './Models';
import { DefaultPeriods } from './Periods';
import { formatDate, parseDate } from './DateUtils';

// ---------------------------------------------------------------------------
// 缓存模型（与磁盘 JSON 一一对应）
// ---------------------------------------------------------------------------

export interface CachedPeriod {
  index: number;
  start: string;
  end: string;
}

export interface CachedConfig {
  termName: string;
  firstMonday: string;
  totalWeeks: number;
  periods: CachedPeriod[];
}

export interface CachedCourse {
  /**
   * 课程稳定标识（可选，老缓存没有）。
   *
   * ⚠️ 这个字段很关键：早期实现用「数组下标」生成 id，
   * 导致同一门课在不同周、不同缓存快照里 id 不同，
   * 合并/去重时会被当成两门不同的课 —— 这正是「课程顺序混乱」的根源。
   * 现在把真实 id 一并落盘，恢复时原样带回。
   */
  id?: string;
  name: string;
  teacher?: string;
  room?: string;
  dayOfWeek: number;
  startSection: number;
  endSection: number;
  weeks: number[];
  content?: string;
  date?: string;
  timeLabel?: string;
  colorHex?: string;
  isSelfStudy?: boolean;
  /** 考试环节（整学期缓存里要保留，供「考试安排」筛选） */
  isExam?: boolean;
}

export interface CachedGrade {
  course: string;
  term: string;
  score?: number;
  level?: string;
  gpa?: number;
  credit: number;
  kind?: string;
}

export interface CachedSnapshot {
  version: number;
  /** 保存时刻（毫秒） */
  savedAt: number;
  /** 课表页缓存的是第几周 */
  week: number;
  courses: CachedCourse[];
  /** 今日页缓存的是哪一周（真实当前周） */
  currentWeek: number;
  currentCourses: CachedCourse[];
  config?: CachedConfig;
  grades: CachedGrade[];
  /** 近期考试（离线时也能看到） */
  exams: CachedCourse[];
  /**
   * **整学期课表**（离线翻周的数据来源）。
   *
   * 只要登录过一次、拉到过整学期总表，就把它整个存下来。
   * 之后即使登录失效，切换任意周都能从这份数据本地过滤，
   * 不会出现「某几周有内容、某几周空白」的错乱。
   *
   * 老版本缓存没有这个字段，读出来是 undefined，做兼容处理。
   */
  termCourses?: CachedCourse[];
}

// ---------------------------------------------------------------------------
// 磁盘读写
// ---------------------------------------------------------------------------

export class CacheStore {
  private static readonly FILE_NAME: string = 'cache_snapshot.json';
  private filePath: string = '';

  constructor(context:common.UIAbilityContext) {
    this.filePath = `${context.filesDir}/${CacheStore.FILE_NAME}`;
  }

  load(): CachedSnapshot | undefined {
    try {
      if (!fs.accessSync(this.filePath)) {
        return undefined;
      }
      const stat = fs.statSync(this.filePath);
      if (stat.size === 0) {
        return undefined;
      }
      const text = fs.readTextSync(this.filePath);
      const raw = JSON.parse(text) as CachedSnapshot;
      // 补齐缺省字段，兼容旧版本缓存
      return normalizeSnapshot(raw);
    } catch (e) {
      return undefined;
    }
  }

  save(snapshot: CachedSnapshot): void {
    try {
      const text = JSON.stringify(snapshot);
      const file = fs.openSync(this.filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, text);
      } finally {
        fs.closeSync(file);
      }
    } catch (e) {
      // 写失败不影响主流程
    }
  }

  clear(): void {
    try {
      if (fs.accessSync(this.filePath)) {
        fs.unlinkSync(this.filePath);
      }
    } catch (e) {
      // ignore
    }
  }
}

function normalizeSnapshot(raw: CachedSnapshot): CachedSnapshot {
  return {
    version: raw.version ?? 1,
    savedAt: raw.savedAt ?? 0,
    week: raw.week ?? 1,
    courses: raw.courses ?? [],
    currentWeek: raw.currentWeek ?? 1,
    currentCourses: raw.currentCourses ?? [],
    config: raw.config,
    grades: raw.grades ?? [],
    exams: raw.exams ?? [],
    // 老缓存没有整学期数据 → 空数组；上层会用 exams + courses 兜底
    termCourses: raw.termCourses ?? []
  };
}

// ---------------------------------------------------------------------------
// 缓存模型 → 领域模型
// ---------------------------------------------------------------------------

function cachedToDomain(c: CachedCourse, index: number): Course {
  return {
    // 优先用落盘的真实 id；老缓存没有 id 时，用「星期_节次_课名」做确定性兜底，
    // 这样同一门课每次恢复拿到的 id 都一样，不会因下标变化而漂移。
    id: c.id !== undefined && c.id.length > 0
      ? c.id
      : `cache_${c.dayOfWeek}_${c.startSection}_${c.name}_${index}`,
    name: c.name,
    teacher: c.teacher,
    room: c.room,
    dayOfWeek: c.dayOfWeek,
    startSection: c.startSection,
    endSection: c.endSection,
    weeks: c.weeks,
    content: c.content,
    date: parseDate(c.date),
    timeLabel: c.timeLabel,
    colorHex: c.colorHex,
    isSelfStudy: c.isSelfStudy,
    isExam: c.isExam
  };
}

function domainToCached(c: Course): CachedCourse {
  return {
    id: c.id,
    name: c.name,
    teacher: c.teacher,
    room: c.room,
    dayOfWeek: c.dayOfWeek,
    startSection: c.startSection,
    endSection: c.endSection,
    weeks: c.weeks.slice().sort((a, b) => a - b),
    content: c.content,
    date: c.date === undefined ? undefined : formatDate(c.date),
    timeLabel: c.timeLabel,
    colorHex: c.colorHex,
    isSelfStudy: c.isSelfStudy,
    isExam: c.isExam
  };
}

export function snapshotToConfig(s: CachedSnapshot): TimetableConfig | undefined {
  const c = s.config;
  if (c === undefined) {
    return undefined;
  }
  const monday = parseDate(c.firstMonday);
  if (monday === undefined) {
    return undefined;
  }
  const cached: Period[] = [];
  for (const p of c.periods) {
    cached.push({ index: p.index, start: p.start, end: p.end });
  }
  // 旧版本缓存里作息只有 10 节：缺 11~14 节就用默认表补齐，
  // 否则升级后不清缓存，「今日」页的晚课仍然查不到时刻
  const periods = cached.length >= TOTAL_SECTIONS ? cached : DefaultPeriods.ALL;
  return {
    termName: c.termName,
    firstMonday: monday,
    totalWeeks: c.totalWeeks,
    periods: periods
  };
}

/** 课表页那份（选中周） */
export function snapshotToCourses(s: CachedSnapshot): Course[] {
  return s.courses.map((c, i) => cachedToDomain(c, i));
}

/** 今日页那份（真实当前周） */
export function snapshotToCurrentCourses(s: CachedSnapshot): Course[] {
  const source = s.currentCourses.length > 0 ? s.currentCourses : s.courses;
  return source.map((c, i) => cachedToDomain(c, i));
}

export function snapshotToExams(s: CachedSnapshot): Course[] {
  return s.exams.map((c, i) => {
    const course = cachedToDomain(c, i);
    course.isExam = true;
    return course;
  });
}

export function snapshotToGrades(s: CachedSnapshot): Grade[] {
  return s.grades.map((g) => {
    const grade: Grade = {
      course: g.course,
      term: g.term,
      score: g.score,
      level: g.level,
      gpa: g.gpa,
      credit: g.credit,
      kind: g.kind
    };
    return grade;
  });
}

/**
 * 整学期课表（离线翻周的数据来源）。
 *
 * 优先用新字段 `termCourses`；老缓存没有它时，
 * 退回到 `exams`（那里面其实也存了带 weeks 的课程），保证升级后不丢数据。
 */
export function snapshotToTermCourses(s: CachedSnapshot): Course[] {
  const source = s.termCourses !== undefined && s.termCourses.length > 0
    ? s.termCourses
    : s.exams;
  return source.map((c, i) => cachedToDomain(c, i));
}

export function makeSnapshot(
  config: TimetableConfig,
  scheduleCourses: Course[],
  currentWeekCourses: Course[],
  grades: Grade[],
  exams: Course[],
  week: number,
  currentWeek: number,
  savedAt: number,
  termCourses: Course[] = []
): CachedSnapshot {
  const periods: CachedPeriod[] = [];
  for (const p of config.periods) {
    periods.push({ index: p.index, start: p.start, end: p.end });
  }
  return {
    version: 2,
    savedAt: savedAt,
    week: week,
    courses: scheduleCourses.map(domainToCached),
    currentWeek: currentWeek,
    currentCourses: currentWeekCourses.map(domainToCached),
    config: {
      termName: config.termName,
      firstMonday: formatDate(config.firstMonday),
      totalWeeks: config.totalWeeks,
      periods: periods
    },
    exams: exams.map(domainToCached),
    // 整学期课表全量落盘 —— 登录一次就能记住整个学期
    termCourses: termCourses.map(domainToCached),
    grades: grades.map((g) => {
      const c: CachedGrade = {
        course: g.course,
        term: g.term,
        score: g.score,
        level: g.level,
        gpa: g.gpa,
        credit: g.credit,
        kind: g.kind
      };
      return c;
    })
  };
}
