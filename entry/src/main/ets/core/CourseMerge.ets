/**
 * 课程合并的纯函数实现（可单测）。
 *
 * ## 为什么单独抽出来
 *
 * 「用按周查询的富数据补全整学期缓存」是数据正确性的关键路径，
 * 却埋在 AppViewModel 的私有方法里，无法单测。
 * 这里把它们抽成无副作用的纯函数：
 * - 输入同样数据必然得到同样结果；
 * - 不碰 UI 状态、不读写文件，测试里可以直接调用。
 *
 * AppViewModel 里的同名逻辑改为调用这里，保证「测过的就是跑的」。
 */
import { Course } from './Models';

/**
 * 判断两条课程记录是否指「同一节课」。
 *
 * ## 为什么不用 id
 *
 * 实测教务两种查询返回的 id 形态完全不同：
 * - 整学期总表：`100037_TMP849_3_10_4`
 * - 按周查询：  `103868440_W117202601001_6_4_11`
 * 按 id 匹配永远对不上，会把同一节课存成两份。
 *
 * ## 为什么业务键要用「课名 + 星期 + 起始节」
 *
 * 这三个字段足够唯一定位课表上的一个色块。
 *
 * ⚠️ **刻意不比较 `endSection`**：
 * 两种查询对「跨几节」的判定偶有差异（实测出现过 1-3 节 vs 1-2 节），
 * 若把 endSection 纳入匹配条件，这些课就永远合并不上、内容补不全。
 * 起始节相同 + 课名相同 + 同一天，已能确定是同一节课。
 */
export function isSameCourse(a: Course, b: Course): boolean {
  return a.name === b.name &&
    a.dayOfWeek === b.dayOfWeek &&
    a.startSection === b.startSection;
}

/** 取第一个非空文本 */
export function pickText(a: string | undefined, b: string | undefined): string | undefined {
  if (a !== undefined && a.length > 0) {
    return a;
  }
  if (b !== undefined && b.length > 0) {
    return b;
  }
  return undefined;
}

/**
 * 用按周数据补全整学期条目。
 *
 * ## 字段合并策略（重要，踩过坑）
 *
 * | 字段 | 取值 | 理由 |
 * |------|------|------|
 * | `content` | base 优先，空则取 fresh | 整学期总表常缺 sknrjj |
 * | `room` | **fresh 优先**（见下） | 按周查询才是精确教室 |
 * | `teacher` | base 优先，空则取 fresh | 两者通常一致 |
 * | `id` / `weeks` | **始终用 base** | 离线按周过滤依赖它们 |
 *
 * ## 为什么 room 要用 fresh（按周数据）
 *
 * 实测同一节课在两个接口里给的教室不同：
 *
 * ```
 * 整学期总表：room = "207教室,403教室,408教室,604教室"   ← 多条排课拼接
 * 按周查询：  room = "604教室"                          ← 当周精确教室
 * ```
 *
 * 整学期总表把「这门课这一学期用过的所有教室」拼在一起，
 * 而按周查询给的是**这一周实际在哪上课**。
 *
 * 结果就是今日页（走整学期）和课表页（走按周）显示的教室不一致，
 * 用户看到「同一个课时，两个页面的教室不一样」。
 *
 * 现在统一以**按周查询的精确值**为准 —— 这也是课表页原本显示的值，
 * 符合「课表是权威」的直觉。
 */
export function enrichCourse(base: Course, fresh: Course): Course {
  return {
    id: base.id,
    name: base.name,
    teacher: pickText(base.teacher, fresh.teacher),
    // ⚠️ room 反过来：优先用按周查询的精确值
    room: pickText(fresh.room, base.room),
    dayOfWeek: base.dayOfWeek,
    startSection: base.startSection,
    endSection: base.endSection,
    weeks: base.weeks,
    content: pickText(base.content, fresh.content),
    date: base.date !== undefined ? base.date : fresh.date,
    timeLabel: pickText(base.timeLabel, fresh.timeLabel),
    colorHex: pickText(base.colorHex, fresh.colorHex),
    isSelfStudy: base.isSelfStudy === true || fresh.isSelfStudy === true,
    isExam: base.isExam === true || fresh.isExam === true
  };
}

/**
 * 把某一周的富数据合并进整学期列表，返回**新数组**（不修改入参）。
 *
 * 行为：
 * - 命中同一节课 → 只补富字段（`enrichCourse`）；
 * - 没命中 → 追加（这周有一门整学期总表里没有的课）。
 *
 * @param term 现有整学期课程
 * @param fresh 按周查询得到的该周课程
 * @param week 这是第几周
 */
export function mergeWeekIntoTerm(term: Course[], fresh: Course[], week: number): Course[] {
  if (fresh.length === 0) {
    return term;
  }
  const next: Course[] = [];
  for (const c of term) {
    next.push(c);
  }

  for (const f of fresh) {
    let hit = -1;
    for (let i = 0; i < next.length; i++) {
      const c = next[i];
      // 同一节课，且这条整学期记录确实覆盖本周
      if (isSameCourse(c, f) && c.weeks.indexOf(week) >= 0) {
        hit = i;
        break;
      }
    }
    if (hit >= 0) {
      next[hit] = enrichCourse(next[hit], f);
    } else {
      next.push(f);
    }
  }
  return next;
}

/** 某一周的课程里，是否还有缺上课内容的 */
export function weekMissingContent(courses: Course[]): boolean {
  for (const c of courses) {
    if (c.content === undefined || c.content.length === 0) {
      return true;
    }
  }
  return false;
}

/**
 * 判断某个 room 值是否是「整学期总表的多教室拼接」。
 *
 * 教务在整学期总表里会把一门课这一学期用过的所有教室拼起来，
 * 形如 `207教室,403教室,408教室,604教室`；
 * 而按周查询只给当周那一个：`604教室`。
 *
 * 判据：出现逗号分隔且至少两段。
 * 注意中文逗号 `，` 也要处理 —— 教务两种符号都出现过。
 */
export function isMultiRoom(room: string | undefined): boolean {
  if (room === undefined || room.length === 0) {
    return false;
  }
  const parts: string[] = room.split(/[,，]/);
  let nonEmpty: number = 0;
  for (const p of parts) {
    if (p.trim().length > 0) {
      nonEmpty++;
    }
  }
  return nonEmpty >= 2;
}

/**
 * 某一周是否有课需要「用按周数据修正」。
 *
 * 两种需要修正的情形：
 * 1. 缺上课内容（`sknrjj`）
 * 2. room 是多教室拼接值（应该改成当周精确教室）
 *
 * 补全功能用它决定要拉哪几周，避免漏掉「只有 room 不对」的周。
 */
export function weekNeedsWeeklySync(courses: Course[]): boolean {
  for (const c of courses) {
    if (c.content === undefined || c.content.length === 0) {
      return true;
    }
    if (isMultiRoom(c.room)) {
      return true;
    }
  }
  return false;
}

/**
 * 用「新拉到的整学期总表」刷新缓存，同时**保留旧数据里的富字段**。
 *
 * ## 为什么不能直接替换
 *
 * 教务的整学期总表（`zc` 为空）**不含 `sknrjj`（上课内容）**，
 * 实测 220 条里仅 43 条有值；而用户点「补全全部周」后，
 * 内存里的 `termCourses` 已经带有完整内容。
 *
 * 如果每次同步都 `state.termCourses = fresh`，补全成果会被冲掉 ——
 * 现象就是：刚补全看得到，一同步或重启就没了。
 *
 * ## 做法
 *
 * 以 `fresh`（新总表）为骨架，保证能拿到教务最新的排课调整；
 * 但对每一条，若旧数据里有同一节课且带内容/精确教室，则继承过来。
 *
 * 判定「同一节课」用 `isSameCourse`（课名 + 星期 + 起始节），
 * 且要求旧记录覆盖新记录里的某几周（避免把别的周的课错配过来）。
 *
 * @param old 现有缓存（可能带补全内容）
 * @param fresh 刚从教务拉到的整学期总表（可能缺内容）
 * @returns 合并后的新数组
 */
export function preserveRichFields(old: Course[], fresh: Course[]): Course[] {
  if (old.length === 0) {
    return fresh;
  }
  const out: Course[] = [];
  for (const f of fresh) {
    // 在旧数据里找同一节课
    let hit: Course | undefined = undefined;
    for (const o of old) {
      if (!isSameCourse(o, f)) {
        continue;
      }
      // 还要求周次有交集，否则可能是同一门课的另一段排课
      let overlap = false;
      for (const w of o.weeks) {
        if (f.weeks.indexOf(w) >= 0) {
          overlap = true;
          break;
        }
      }
      if (overlap) {
        hit = o;
        break;
      }
    }
    if (hit === undefined) {
      out.push(f);
      continue;
    }
    // 骨架用 f（保留教务最新的 id / weeks / 排课），富字段优先取旧值
    out.push({
      id: f.id,
      name: f.name,
      teacher: pickText(hit.teacher, f.teacher),
      // room：旧值若不是多教室拼接就优先（那才是按周查询修正过的精确值）
      room: isMultiRoom(hit.room) ? pickText(f.room, hit.room) : pickText(hit.room, f.room),
      dayOfWeek: f.dayOfWeek,
      startSection: f.startSection,
      endSection: f.endSection,
      weeks: f.weeks,
      content: pickText(hit.content, f.content),
      date: f.date !== undefined ? f.date : hit.date,
      timeLabel: pickText(hit.timeLabel, f.timeLabel),
      colorHex: pickText(hit.colorHex, f.colorHex),
      isSelfStudy: f.isSelfStudy === true || hit.isSelfStudy === true,
      isExam: f.isExam === true || hit.isExam === true
    });
  }
  return out;
}
