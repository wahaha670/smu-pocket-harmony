/**
 * 接口模型 → 领域模型。
 *
 * UI 只认 Course / Grade，不认教务的 40 个字段。好处：
 * - 教务改字段名，只改这一个文件；
 * - 隐私字段（`xsbh` 学号、`xsxm` 姓名）根本进不了领域模型。
 *
 * 移植自 Android 版 data/model/Mappers.kt。
 */
import { Course, Grade } from '../core/Models';
import { dateOf, parseDate } from '../core/DateUtils';
import { Semester } from '../core/Semester';
import { CourseData, creditOf, gradePointOf, ScoreData, scoreOf } from './JwJson';

/**
 * 解析节次串 `"0809"` / `"060708"` → [8, 9] / [6, 8]。
 *
 * 每两位一节。奇数长度直接放弃（宁可返回 undefined 让上层兜底，也不猜出个错范围）。
 */
export function parseJcdm(jcdm: string): number[] | undefined {
  const raw = jcdm.trim();
  if (raw.length === 0 || raw.length % 2 !== 0) {
    return undefined;
  }
  for (const ch of raw) {
    if (ch < '0' || ch > '9') {
      return undefined;
    }
  }
  const nums: number[] = [];
  for (let i = 0; i < raw.length; i += 2) {
    const n = Number.parseInt(raw.substring(i, i + 2), 10);
    if (Number.isNaN(n)) {
      return undefined;
    }
    nums.push(n);
  }
  if (nums.length === 0) {
    return undefined;
  }
  let min = nums[0];
  let max = nums[0];
  for (const n of nums) {
    if (n < min) {
      min = n;
    }
    if (n > max) {
      max = n;
    }
  }
  // 返回 [起始节, 结束节]
  return [min, max];
}

/**
 * 统一取节次：优先 `jcdm`（按周数据），退回 `ps`/`pe`（整学期总表）。
 * 两条查询路径的字段不一样，这层封装让 UI 不用关心走的是哪条。
 */
export function sectionsOf(record: CourseData): number[] | undefined {
  const byJcdm = parseJcdm(record.jcdm);
  if (byJcdm !== undefined) {
    return byJcdm;
  }

  const startText = record.ps.trim();
  if (startText.length === 0) {
    return undefined;
  }
  const start = Number.parseInt(startText, 10);
  if (Number.isNaN(start)) {
    return undefined;
  }

  const endText = record.pe.trim();
  let end = start;
  if (endText.length > 0) {
    const parsed = Number.parseInt(endText, 10);
    if (!Number.isNaN(parsed)) {
      end = parsed;
    }
  }
  return end >= start ? [start, end] : [start, start];
}

/** "09:50-11:15"，比节次更直观，用于课程卡片副标题 */
export function clockRange(record: CourseData): string | undefined {
  const start = record.qssj.substring(0, 5);
  const end = record.jssj.substring(0, 5);
  if (start.length !== 5 || end.length !== 5) {
    return undefined;
  }
  return `${start}-${end}`;
}

/**
 * 教学环节名称判断。
 *
 * 实测 118 行真实数据里 `jxhjmc` 只有 7 种取值：
 * 理论 / 自主学习 / 实验 / 考试（理论）/ 考试（实操）/ 技能 / 见习。
 * 其中「自主学习」19 行全部没有教室，与其它类别完全可分。
 */
function isExamKind(v: string | undefined): boolean {
  if (!v) {
    return false;
  }
  return v.indexOf('考试') >= 0;
}

function isSelfStudyKind(jxhjmc: string): boolean {
  const v = jxhjmc.trim();
  if (v.length === 0) {
    return false;
  }
  const markers = ['自主', '线上', '网络', '慕课', '在线', '自习'];
  for (const m of markers) {
    if (v.indexOf(m) >= 0) {
      return true;
    }
  }
  return false;
}

/**
 * @param fallbackWeek 调用方知道的周次。按日期/周次查询的响应里没有 `zc`，
 *   必须靠它兜底，否则 weeks 为空 → 整门课被静默丢掉。
 * @param firstMonday 整学期总表没有 `qsrq`，但若这行只落在某一周，可以用它反推日期
 */
export function toCourse(
  record: CourseData,
  fallbackWeek?: number,
  firstMonday?: number
): Course | undefined {
  const day = record.xq;
  if (day < 1 || day > 7) {
    return undefined;
  }

  const sections = sectionsOf(record);
  if (sections === undefined) {
    return undefined;
  }

  const weeksFromData = Semester.parseWeeks(record.zc);
  let weeks: number[];
  if (weeksFromData.length > 0) {
    weeks = weeksFromData;
  } else if (fallbackWeek !== undefined) {
    weeks = [fallbackWeek];
  } else {
    return undefined;
  }

  const name = record.kcmc.trim();
  if (name.length === 0) {
    return undefined;
  }

  // id 用课程码 + 星期 + 节次，保证同一门课不同时段是不同 id
  const idParts: string[] = [];
  if (record.kcdm.trim().length > 0) {
    idParts.push(record.kcdm.trim());
  }
  if (record.kcbh.trim().length > 0) {
    idParts.push(record.kcbh.trim());
  }
  idParts.push(`${day}`);
  idParts.push(`${sections[0]}`);
  idParts.push(record.zc.trim().length > 0 ? record.zc.trim() : `w${fallbackWeek}`);

  let date = parseDate(record.qsrq);
  if (date === undefined && firstMonday !== undefined && weeks.length === 1) {
    date = dateOf(firstMonday, weeks[0], day);
  }

  const teacher = record.teaxms.trim();
  const room = record.jxcdmc.trim();
  const content = record.sknrjj.trim();
  const color = record.bgcolor.trim();

  const course: Course = {
    id: idParts.join('_'),
    name: name,
    teacher: teacher.length > 0 ? teacher : undefined,
    room: room.length > 0 ? room : undefined,
    dayOfWeek: day,
    startSection: sections[0],
    endSection: sections[1],
    weeks: weeks,
    content: content.length > 0 ? content : undefined,
    date: date,
    timeLabel: clockRange(record),
    colorHex: color.length > 0 ? color : undefined,
    isSelfStudy: isSelfStudyKind(record.jxhjmc),
    isExam: isExamKind(record.jxhjmc) || isExamKind(record.khfsmc)
  };
  return course;
}

export function toCourses(
  records: CourseData[],
  fallbackWeek?: number,
  firstMonday?: number
): Course[] {
  const out: Course[] = [];
  for (const r of records) {
    const c = toCourse(r, fallbackWeek, firstMonday);
    if (c !== undefined) {
      out.push(c);
    }
  }
  return out;
}

export function toGrade(s: ScoreData): Grade | undefined {
  const name = s.kcmc.trim();
  if (name.length === 0) {
    return undefined;
  }

  const numericScore = scoreOf(s);
  // 等级制课程（优/良/中）没有分数，等级就藏在 zcj 里
  let level: string | undefined;
  if (numericScore === undefined) {
    const z = s.zcj.trim();
    if (z.length > 0) {
      level = z;
    }
  }

  const kind = s.xdfsmc.trim();
  const grade: Grade = {
    course: name,
    term: s.xnxqmc,
    score: numericScore,
    level: level,
    gpa: gradePointOf(s),
    credit: creditOf(s),
    kind: kind.length > 0 ? kind : undefined
  };
  return grade;
}

export function toGrades(rows: ScoreData[]): Grade[] {
  const out: Grade[] = [];
  for (const r of rows) {
    const g = toGrade(r);
    if (g !== undefined) {
      out.push(g);
    }
  }
  return out;
}
