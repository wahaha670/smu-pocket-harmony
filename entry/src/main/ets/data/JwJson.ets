/**
 * 教务接口的原始 JSON 模型 + 解析。
 *
 * ## 为什么要手写解析而不是用 JSON.parse 直接映射
 *
 * 教务的字段类型**不稳定**，同一个字段在不同请求里类型不一样：
 * - `zc`：整学期总表返回 `"12,13"`（字符串），按周返回 `8`（数字）
 * - `zcjfs`：实测是 `88.2`（数字），别处可能给 `"88.20"`
 *
 * 直接声明成 string 或 number，都会在另一条路径上抛类型错误。
 * 所以统一用「柔性」取值函数：什么进来都转成目标类型，转不动给默认值。
 *
 * ## ArkTS 约束（编译期强制）
 *
 * ArkTS 禁止 `any` / `unknown` / `ESObject` 出现在接口边界（arkts-no-any-unknown），
 * 也不允许「索引访问字段」（arkts-no-props-by-index）。
 * 所以这里：
 * - JSON 解析结果统一用 `Object` 承接；
 * - 读取字段走 `toMap()` 把对象转成 `Record<string, Object>` 再按键取；
 * - 数组用 `Array.isArray()` 收窄后按 `Object[]` 处理。
 *
 * 移植自 Android 版 data/model/*.kt。
 */

// ---------------------------------------------------------------------------
// 安全取值
// ---------------------------------------------------------------------------

/** 任何值 → Record<string, Object>；不是对象就给空表 */
function toMap(v: Object | null | undefined): Record<string, Object> {
  if (v === null || v === undefined) {
    return {};
  }
  if (typeof v !== 'object' || Array.isArray(v)) {
    return {};
  }
  return v as Record<string, Object>;
}

/** 任何值 → Object[]；不是数组就给空数组 */
function toArray(v: Object | null | undefined): Object[] {
  if (v === null || v === undefined) {
    return [];
  }
  if (!Array.isArray(v)) {
    return [];
  }
  return v as Object[];
}

/** 从 Record 里取字段；没有就返回 undefined */
function pick(m: Record<string, Object>, key: string): Object | undefined {
  const v: Object | undefined = m[key];
  return v;
}

/** 不管进来是字符串、数字还是 null，都转成 string；转不动给 '' */
export function flexString(v: Object | null | undefined): string {
  if (v === null || v === undefined) {
    return '';
  }
  if (typeof v === 'string') {
    return v as string;
  }
  if (typeof v === 'number') {
    return `${v as number}`;
  }
  if (typeof v === 'boolean') {
    return (v as boolean) ? 'true' : 'false';
  }
  try {
    return JSON.stringify(v);
  } catch (e) {
    return '';
  }
}

/** 不管进来是什么，都转成 number；转不动给 0 */
export function flexInt(v: Object | null | undefined): number {
  if (v === null || v === undefined) {
    return 0;
  }
  if (typeof v === 'number') {
    const n = v as number;
    return Number.isNaN(n) ? 0 : Math.trunc(n);
  }
  const text = flexString(v).trim();
  if (text.length === 0) {
    return 0;
  }
  const asInt = Number.parseInt(text, 10);
  if (!Number.isNaN(asInt)) {
    return asInt;
  }
  const asFloat = Number.parseFloat(text);
  if (!Number.isNaN(asFloat)) {
    return Math.trunc(asFloat);
  }
  return 0;
}

/** 转成 number | undefined（成绩/绩点这类「可能没有」的字段） */
export function flexDoubleOrUndefined(v: Object | null | undefined): number | undefined {
  if (v === null || v === undefined) {
    return undefined;
  }
  if (typeof v === 'number') {
    const n = v as number;
    return Number.isNaN(n) ? undefined : n;
  }
  const text = flexString(v).trim();
  if (text.length === 0) {
    return undefined;
  }
  const n = Number.parseFloat(text);
  return Number.isNaN(n) ? undefined : n;
}

// ---------------------------------------------------------------------------
// 一条课次（对应 CourseData）
// ---------------------------------------------------------------------------

/**
 * 一条课次。字段含义来自真实抓包的字段字典。
 *
 * 两条不同查询路径返回的字段**不一样**，模型必须能同时装下：
 *
 * | 字段 | 整学期总表 | 按周查询 |
 * |---|---|---|
 * | `zc` 周次 | `"12,13"` 字符串，含多周 | `8` 数字 |
 * | `qsrq` 真实日期 | 没有 | 有 |
 * | `sknrjj` 上课内容 | 没有 | 有 |
 * | `jcdm` 节次串 | 没有 | 有 |
 * | `pe` 结束节 | 有 | 没有（只有 `ps`） |
 */
export interface CourseData {
  kcmc: string;
  kcdm: string;
  kcbh: string;
  teaxms: string;
  jxcdmc: string;
  jxbmc: string;
  jxhjmc: string;
  khfsmc: string;
  xq: number;
  zc: string;
  ps: string;
  pe: string;
  jcdm: string;
  qsrq: string;
  sknrjj: string;
  lx: string;
  qssj: string;
  jssj: string;
  xnxqdm: string;
  bgcolor: string;
  xs: number;
  pkrs: number;
}

/** 从任意 JSON 对象安全构造一条 CourseData（所有字段都容错） */
export function parseCourseData(obj: Object): CourseData {
  const o = toMap(obj);
  return {
    kcmc: flexString(pick(o, 'kcmc')),
    kcdm: flexString(pick(o, 'kcdm')),
    kcbh: flexString(pick(o, 'kcbh')),
    teaxms: flexString(pick(o, 'teaxms')),
    jxcdmc: flexString(pick(o, 'jxcdmc')),
    jxbmc: flexString(pick(o, 'jxbmc')),
    jxhjmc: flexString(pick(o, 'jxhjmc')),
    khfsmc: flexString(pick(o, 'khfsmc')),
    xq: flexInt(pick(o, 'xq')),
    zc: flexString(pick(o, 'zc')),
    ps: flexString(pick(o, 'ps')),
    pe: flexString(pick(o, 'pe')),
    jcdm: flexString(pick(o, 'jcdm')),
    qsrq: flexString(pick(o, 'qsrq')),
    sknrjj: flexString(pick(o, 'sknrjj')),
    lx: flexString(pick(o, 'lx')),
    qssj: flexString(pick(o, 'qssj')),
    jssj: flexString(pick(o, 'jssj')),
    xnxqdm: flexString(pick(o, 'xnxqdm')),
    bgcolor: flexString(pick(o, 'bgcolor')),
    xs: flexInt(pick(o, 'xs')),
    pkrs: flexInt(pick(o, 'pkrs'))
  };
}

// ---------------------------------------------------------------------------
// 一条成绩（对应 ScoreData）
// ---------------------------------------------------------------------------

/**
 * 一条成绩。字段类型照真实抓包定，有几处和直觉相反：
 * - `zcjfs` / `cjjd` / `xf` 实测是**数字**，但别处可能是字符串
 * - `zcj`（总成绩）**本来就是字符串** `"88.20"`
 * - 学期字段是 `xnxqmc`（"2025-2026-2"），**不是** `xnxqdmc`
 */
export interface ScoreData {
  kcmc: string;
  kcdm: string;
  xnxqdm: string;
  xnxqmc: string;
  zcj: string;
  zcjfs: string;
  cjjd: string;
  xf: string;
  zxs: string;
  kcdlmc: string;
  kcflmc: string;
  xdfsmc: string;
  ksxzmc: string;
  cjfsmc: string;
  kkbmmc: string;
  bz: string;
  ismax: string;
  isactive: string;
}

export function parseScoreData(obj: Object): ScoreData {
  const o = toMap(obj);
  return {
    kcmc: flexString(pick(o, 'kcmc')),
    kcdm: flexString(pick(o, 'kcdm')),
    xnxqdm: flexString(pick(o, 'xnxqdm')),
    xnxqmc: flexString(pick(o, 'xnxqmc')),
    zcj: flexString(pick(o, 'zcj')),
    zcjfs: flexString(pick(o, 'zcjfs')),
    cjjd: flexString(pick(o, 'cjjd')),
    xf: flexString(pick(o, 'xf')),
    zxs: flexString(pick(o, 'zxs')),
    kcdlmc: flexString(pick(o, 'kcdlmc')),
    kcflmc: flexString(pick(o, 'kcflmc')),
    xdfsmc: flexString(pick(o, 'xdfsmc')),
    ksxzmc: flexString(pick(o, 'ksxzmc')),
    cjfsmc: flexString(pick(o, 'cjfsmc')),
    kkbmmc: flexString(pick(o, 'kkbmmc')),
    bz: flexString(pick(o, 'bz')),
    ismax: flexString(pick(o, 'ismax')),
    isactive: flexString(pick(o, 'isactive'))
  };
}

/** 数值型成绩。优先 zcjfs（精度更规范），退回 zcj */
export function scoreOf(s: ScoreData): number | undefined {
  const a = flexDoubleOrUndefined(s.zcjfs);
  if (a !== undefined) {
    return a;
  }
  return flexDoubleOrUndefined(s.zcj);
}

/** 绩点 */
export function gradePointOf(s: ScoreData): number | undefined {
  return flexDoubleOrUndefined(s.cjjd);
}

/** 学分 */
export function creditOf(s: ScoreData): number {
  const v = flexDoubleOrUndefined(s.xf);
  return v === undefined ? 0 : v;
}

// ---------------------------------------------------------------------------
// 一条课程任务 / 考试（对应 ExamTaskData）
// ---------------------------------------------------------------------------

/**
 * 一条课程任务（考试）。
 *
 * 字段名会骗人：抓包时看到的字段是 `xkh`，但真实响应里网考号在 **`xid`**。
 * 所以两个都解析，`xkh` 优先、退回 `xid`。
 */
export interface ExamTaskData {
  xkh: string;
  xid: string;
  kcmc: string;
  khfsmc: string;
}

export function parseExamTaskData(obj: Object): ExamTaskData {
  const o = toMap(obj);
  return {
    xkh: flexString(pick(o, 'xkh')),
    xid: flexString(pick(o, 'xid')),
    kcmc: flexString(pick(o, 'kcmc')),
    khfsmc: flexString(pick(o, 'khfsmc'))
  };
}

/** 网考号：`xkh` 优先，没有就用 `xid` */
export function onlineExamNumber(e: ExamTaskData): string {
  const a = e.xkh.trim();
  if (a.length > 0) {
    return a;
  }
  return e.xid.trim();
}

// ---------------------------------------------------------------------------
// 响应包装
// ---------------------------------------------------------------------------

export interface TimetableResponse {
  code: number;
  message: string;
  data: CourseData[];
}

export interface ScoreResponse {
  code: number;
  message: string;
  rows: ScoreData[];
  total: number;
}

export interface ExamTaskResponse {
  code: number;
  message: string;
  rows: ExamTaskData[];
  total: number;
}

export function scoreHasMore(r: ScoreResponse): boolean {
  return r.rows.length > 0 && r.rows.length < r.total;
}

export function examTaskHasMore(r: ExamTaskResponse): boolean {
  return r.rows.length > 0 && r.rows.length < r.total;
}

// ---------------------------------------------------------------------------
// 解码入口（所有容错集中在这里）
// ---------------------------------------------------------------------------

export class JwJson {
  /**
   * 课表解码。三种形态都要能吃：
   * 1. 成功：`{"code":0,"data":[...],"message":"成功"}` → data 是数组
   * 2. 成功（裸数组）：`[...]`
   * 3. **失败**：`{"code":-401,"data":"","message":"尚未登录，请先登录"}` → data 是**空字符串**
   *
   * 第 3 种如果直接按数组解，会抛一个看不懂的解析错误，
   * 把一个清清楚楚的「未登录」变成难查的 bug。
   */
  static timetable(body: string): TimetableResponse {
    const text = body.trimStart();

    if (text.startsWith('[')) {
      const arr = JwJson.parseArray(text);
      const rows: CourseData[] = [];
      for (const item of arr) {
        rows.push(parseCourseData(item));
      }
      return { code: 0, message: '', data: rows };
    }

    const root = JwJson.parseObject(text);
    const code = flexInt(pick(root, 'code'));
    const message = flexString(pick(root, 'message'));
    // 失败时 data 是 ""，只有成功时才是数组
    const rowsRaw = pick(root, 'data');
    const rows: CourseData[] = [];
    if (Array.isArray(rowsRaw)) {
      for (const item of toArray(rowsRaw)) {
        rows.push(parseCourseData(item));
      }
    }
    return { code: code, message: message, data: rows };
  }

  /**
   * 成绩解码。
   *
   * 实测形态：`{ "data": "", "rows": [...], "total": 50 }`
   * `rows` 与 `data` **平级**。另外顺手兼容 `{ "data": { "rows": [...] } }`
   * 这种嵌套形态，免得换个接口就崩。
   */
  static scores(body: string): ScoreResponse {
    const root = JwJson.parseObject(body);
    const rowsJson = JwJson.extractRows(root);

    let total = 0;
    const totalRaw = pick(root, 'total');
    if (totalRaw !== undefined) {
      total = flexInt(totalRaw);
    } else {
      total = rowsJson.length;
    }

    const rows: ScoreData[] = [];
    for (const item of rowsJson) {
      rows.push(parseScoreData(item));
    }

    return {
      code: flexInt(pick(root, 'code')),
      message: flexString(pick(root, 'message')),
      rows: rows,
      total: total
    };
  }

  /**
   * 课程任务（考试）解码。形态与成绩接口一致，顺手兼容裸数组。
   */
  static examTasks(body: string): ExamTaskResponse {
    const text = body.trimStart();

    if (text.startsWith('[')) {
      const arr = JwJson.parseArray(text);
      const rows: ExamTaskData[] = [];
      for (const item of arr) {
        rows.push(parseExamTaskData(item));
      }
      return { code: 0, message: '', rows: rows, total: rows.length };
    }

    const root = JwJson.parseObject(body);
    const rowsJson = JwJson.extractRows(root);

    let total = 0;
    const totalRaw = pick(root, 'total');
    if (totalRaw !== undefined) {
      total = flexInt(totalRaw);
    } else {
      total = rowsJson.length;
    }

    const rows: ExamTaskData[] = [];
    for (const item of rowsJson) {
      rows.push(parseExamTaskData(item));
    }

    return {
      code: flexInt(pick(root, 'code')),
      message: flexString(pick(root, 'message')),
      rows: rows,
      total: total
    };
  }

  /**
   * 从根对象里抽出 rows 数组。
   * 同时认两种形态：`{rows:[...]}`（平级）和 `{data:{rows:[...]}}`（嵌套）。
   */
  private static extractRows(root: Record<string, Object>): Object[] {
    const directRows = pick(root, 'rows');
    if (Array.isArray(directRows)) {
      return toArray(directRows);
    }
    const nestedData = pick(root, 'data');
    if (nestedData !== undefined && typeof nestedData === 'object' && !Array.isArray(nestedData)) {
      const nested = pick(toMap(nestedData), 'rows');
      if (Array.isArray(nested)) {
        return toArray(nested);
      }
    }
    return [];
  }

  /** 安全解析 JSON 对象；失败返回空表 */
  private static parseObject(text: string): Record<string, Object> {
    try {
      const v: Object = JSON.parse(text) as Object;
      return toMap(v);
    } catch (e) {
      return {};
    }
  }

  /** 安全解析 JSON 数组；失败返回空数组 */
  private static parseArray(text: string): Object[] {
    try {
      const v: Object = JSON.parse(text) as Object;
      if (Array.isArray(v)) {
        return toArray(v);
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
