/**
 * 实况窗（Live View）课表提醒。
 *
 * ⚠️ 重要前提（必读）
 * ------------------
 * 实况窗的 event 只有 15 个官方场景（TAXI / DELIVERY / FLIGHT / TRAIN / QUEUE /
 * PICK_UP / SCORE / RENT / TIMER / WORKOUT / NAVIGATION / CHECK_IN / EXPRESS /
 * PROGRESS / TRADE），**没有「上课」这一项**，且必须向华为申请场景权限才能调用。
 *
 * 因此本模块的策略是：
 *   1. 用 TIMER 场景（计时/倒计时）作为最贴近语义的合法场景
 *      —— TIMER 是白名单里唯一能表达「距某时刻还有多久」的通用场景；
 *   2. 每次调用前用 isLiveViewEnabled() 做前置检查，拿不到权限时**静默降级**，
 *      绝不让课表主流程崩溃；
 *   3. 把 1003500005（The right of liveView is not enabled）单独识别出来，
 *      在设置页给用户明确的「未开通实况窗权限」提示，而不是报一个看不懂的错。
 *
 * 也就是说：**代码是完整可用的，能否真正显示取决于华为是否给你的应用开通场景权限。**
 */

import { liveViewManager } from '@kit.LiveViewKit';
import { BusinessError } from '@kit.BasicServicesKit';
/**
 * ⚠️ 必须用**旧版** `@ohos.wantAgent`，不能用 `@kit.AbilityKit` 的 wantAgent。
 * LiveViewKit 的 clickAction 类型在 .d.ts 第 8 行明确写的是：
 *   import type { WantAgent } from '@ohos.wantAgent';
 * 两套 API 的 WantAgent 类型不兼容。
 *
 * 注意该模块的导出形态比较特殊（见文件末尾）：
 *   export type WantAgent = object;   // 顶层具名导出，不在 namespace 里
 *   export default wantAgent;          // 默认导出是 namespace
 * 所以类型要从默认导出的命名空间取：wantAgent.WantAgent
 * 而 WantAgentInfo 需从子路径 wantAgent/wantAgentInfo 取。
 */
/**
 * ⚠️ 这里有一条踩过坑的结论，别再试错：
 *
 * 1. clickAction 的类型来自**旧版** `@ohos.wantAgent`
 *    （LiveViewKit 的 .d.ts 第 8 行：import type { WantAgent } from '@ohos.wantAgent'）。
 * 2. 但调用**用新版** `@ohos.app.ability.wantAgent` 的 getWantAgent 更顺手，
 *    因为它把 WantAgentInfo 作为具名类型导出（旧版没有导出来）。
 * 3. 新版返回的 WantAgent 与旧版 WantAgent 在运行期是同一个东西；
 *    编译期只需把它当 object 传给 clickAction，ArkTS 允许。
 *
 * 已试错并通过编译的组合 = 下面这两行。
 */
import abilityWantAgent, { WantAgent as AbilityWantAgentType } from '@ohos.app.ability.wantAgent';
import type Want from '@ohos.app.ability.Want';
import { Course } from '../core/Models';
import { DefaultPeriods } from './Periods';

/** clickAction 需要的类型（与 AbilityWantAgentType 运行期同构） */
type WantAgentType = AbilityWantAgentType;

/** 本应用包名（bundleName） */
const BUNDLE_NAME: string = 'com.smu.pocket';
/** 主入口 Ability */
const ENTRY_ABILITY: string = 'EntryAbility';

/** 实况窗错误码：未开通实况窗权益 */
const ERR_RIGHT_NOT_ENABLED: number = 1003500005;
/** 实况窗错误码：实况窗总开关未打开 */
const ERR_LIVEVIEW_NOT_ENABLED: number = 1003500004;

/** 提醒状态，供设置页展示 */
export enum LiveViewStatus {
  /** 本机/本应用不支持实况窗 */
  UNSUPPORTED = 'unsupported',
  /** 用户没打开实况窗总开关 */
  DISABLED = 'disabled',
  /** 没有华为授予的场景权限（需要商务申请） */
  NO_RIGHT = 'no_right',
  /** 可用 */
  READY = 'ready',
  /** 调用出错 */
  ERROR = 'error',
}

export interface LiveViewProbe {
  status: LiveViewStatus;
  /** 可直接展示给用户的中文说明 */
  message: string;
  /** 原始错误码，便于排查 */
  code?: number;
}

/**
 * 探测实况窗可用性。
 *
 * 注意 isLiveViewEnabled() 只回答「用户是否打开实况窗总开关」，
 * **不回答「你的应用有没有场景权限」** —— 后者只能在真正 startLiveView 时
 * 由错误码 1003500005 暴露出来。所以这里只能探测到 DISABLED 为止。
 */
export async function probeLiveView(): Promise<LiveViewProbe> {
  try {
    const enabled: boolean = await liveViewManager.isLiveViewEnabled();
    if (!enabled) {
      return {
        status: LiveViewStatus.DISABLED,
        message: '系统实况窗开关未打开，请到「设置 → 通知 → 实况窗」中开启',
      };
    }
    return {
      status: LiveViewStatus.READY,
      message: '实况窗可用',
    };
  } catch (e) {
    const err = e as BusinessError;
    return {
      status: LiveViewStatus.UNSUPPORTED,
      message: `本机不支持实况窗（${err.code ?? '未知'}）`,
      code: err.code,
    };
  }
}

/**
 * 深度探测：真正尝试创建一次最小实况窗，借此暴露「场景权益是否开通」。
 *
 * 为什么需要它：isLiveViewEnabled() 只回答「用户有没有打开系统实况窗总开关」，
 * **完全查不出华为有没有给这个应用下发场景权益**。后者只有真正调用
 * startLiveView 时才会以 1003500005 的形式暴露。
 *
 * 做法：用一个固定的探针 id 建一条极短（keepTime=0）的实况窗，立刻结束。
 * 失败会把错误码翻译成明确结论。
 */
const PROBE_ID: number = 2147483000;

export async function probeLiveViewDeep(): Promise<LiveViewProbe> {
  const basic: LiveViewProbe = await probeLiveView();
  if (basic.status !== LiveViewStatus.READY) {
    return basic;
  }
  // 探针也需要 clickAction（必填），用固定 requestCode
  const agent: WantAgentType | undefined = await createWantAgent(PROBE_ID);
  if (agent === undefined) {
    return {
      status: LiveViewStatus.ERROR,
      message: '无法构建跳转意图（WantAgent），请检查 bundleName/abilityName',
    };
  }
  const liveView: liveViewManager.LiveView = {
    id: PROBE_ID,
    event: 'TIMER',
    isMute: true,
    sequence: 1,
    timer: { time: 1000, isCountdown: true },
    liveViewData: {
      primary: {
        title: '权限检测',
        /**
         * ⚠️ primary.content 也是必填（Array<RichText>）。
         * 不传报 401: The type of primary.content must be Array<RichText>
         * [or the parameter is mandatory]
         */
        content: [{ text: '正在检测实况窗能力' }],
        keepTime: 0,
        clickAction: agent,
        /**
         * ⚠️ layoutData 对 TIMER 场景是**必填**的。
         * 不传会直接报 401 Parameter error:
         * "The type of primary.layoutData must be LayoutData
         *  [or the parameter is mandatory]"
         *
         * ⚠️ 而 LAYOUT_TYPE_PROGRESS 下 nodeIcons 也是必填
         * （报 401: The type of layoutData.nodeIcons must be Array<...>），
         * 图片只能取 /resources/rawfile 下的文件名字符串。
         */
        layoutData: makeProgressLayout(0),
      },
      capsule: makeTimerCapsule('检测中', 1000),
    },
  };
  try {
    const result: liveViewManager.LiveViewResult = await liveViewManager.startLiveView(liveView);
    // 建成功了，立刻收掉，不给用户留一条垃圾卡片
    try {
      await liveViewManager.stopLiveView(liveView);
    } catch (e) {
      // 收不掉也不影响结论
    }
    if (result.resultCode === 0) {
      return { status: LiveViewStatus.READY, message: '实况窗可用：场景权益已开通，可以开启提醒' };
    }
    return {
      status: LiveViewStatus.ERROR,
      message: `实况窗创建返回异常码 ${result.resultCode}：${result.message}`,
      code: result.resultCode,
    };
  } catch (e) {
    const err = e as BusinessError;
    if (err.code === ERR_RIGHT_NOT_ENABLED) {
      return {
        status: LiveViewStatus.NO_RIGHT,
        message: '本机未开通实况窗场景权益：需在 AGC 为应用申请（或加白名单设备，24h 生效）',
        code: err.code,
      };
    }
    if (err.code === ERR_LIVEVIEW_NOT_ENABLED) {
      return {
        status: LiveViewStatus.DISABLED,
        message: '系统实况窗开关未打开：设置 → 通知和状态栏 → 实况窗',
        code: err.code,
      };
    }
    if (err.code === 1003500006) {
      // 探针已存在（上次没清掉），说明其实是通过权限校验的
      await stopCourseLiveViewById(PROBE_ID);
      return { status: LiveViewStatus.READY, message: '实况窗可用：场景权益已开通' };
    }
    return {
      status: LiveViewStatus.ERROR,
      message: `检测失败（${err.code ?? '未知'}）：${err.message ?? ''}`,
      code: err.code,
    };
  }
}

/** 按 id 结束（探针清理用） */
async function stopCourseLiveViewById(id: number): Promise<void> {
  try {
    await liveViewManager.stopLiveView({
      id: id,
      event: 'TIMER',
      liveViewData: { primary: { title: '权限检测' } },
    });
  } catch (e) {
    // 忽略
  }
}

/** 生成一个稳定、不重复的实况窗 id（int32 范围内） */
function liveViewIdFor(courseId: string, dayOfWeek: number, startSection: number): number {
  // FNV-1a，再压到 int32 正区间
  let h: number = 2166136261;
  const seed: string = `${courseId}#${dayOfWeek}#${startSection}`;
  for (let i = 0; i < seed.length; i++) {
    h ^= seed.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  // 保证落在 [1, 2147483647]
  return (Math.abs(h) % 2147483646) + 1;
}

/** 把 "08:00" 解析成 {hour, minute} */
function parseHM(s: string): number[] {
  const parts: string[] = s.split(':');
  if (parts.length !== 2) {
    return [-1, -1];
  }
  const h: number = parseInt(parts[0], 10);
  const m: number = parseInt(parts[1], 10);
  if (isNaN(h) || isNaN(m)) {
    return [-1, -1];
  }
  return [h, m];
}

/** 课程的开始时间（优先用教务给的 timeLabel，缺失时回落到作息表） */
function courseStartTime(course: Course): number[] {
  if (course.timeLabel && course.timeLabel.indexOf('-') > 0) {
    const startStr: string = course.timeLabel.split('-')[0].trim();
    const hm: number[] = parseHM(startStr);
    if (hm[0] >= 0) {
      return hm;
    }
  }
  const p = DefaultPeriods.at(course.startSection);
  if (p) {
    return parseHM(p.start);
  }
  return [-1, -1];
}

/** 下一次上课的毫秒时间戳（用于倒计时） */
function nextOccurrenceMs(course: Course, leadMinutes: number): number {
  const hm: number[] = courseStartTime(course);
  if (hm[0] < 0) {
    return 0;
  }
  const now: Date = new Date();
  // 找到下一个与 course.dayOfWeek 匹配的日期（1=周一…7=周日）
  const todayDow: number = now.getDay() === 0 ? 7 : now.getDay();
  let deltaDays: number = course.dayOfWeek - todayDow;
  if (deltaDays < 0) {
    deltaDays += 7;
  }
  const target: Date = new Date(
    now.getFullYear(), now.getMonth(), now.getDate() + deltaDays,
    hm[0], hm[1], 0, 0
  );
  const remindAt: number = target.getTime() - leadMinutes * 60 * 1000;
  // 今天这门课已经过了提醒点，就顺延到下周
  if (remindAt <= now.getTime()) {
    return remindAt + 7 * 24 * 60 * 60 * 1000;
  }
  return remindAt;
}

/**
 * 构建进度型扩展区（layoutData）。
 *
 * ⚠️ 踩坑记录：TIMER + LAYOUT_TYPE_PROGRESS 下，这些字段是必填的，
 * 缺一个就报 401 "The type of layoutData.XXX must be ... [mandatory]"：
 *   layoutType / progress / nodeIcons（[2,5] 个，取 /resources/rawfile 下的文件名）
 *
 * 参照官方示例，把 backgroundColor / indicatorType / indicatorIcon / lineType
 * 也一并填上，避免"补一个又冒一个"。
 */
function makeProgressLayout(progress: number): liveViewManager.ProgressLayout {
  return {
    layoutType: liveViewManager.LayoutType.LAYOUT_TYPE_PROGRESS,
    progress: progress,
    color: '#FF1F86C7',
    backgroundColor: '#19000000',
    indicatorType: liveViewManager.IndicatorType.INDICATOR_TYPE_OVERLAY,
    indicatorIcon: 'node_icon.png',
    lineType: liveViewManager.LineType.LINE_TYPE_DOTTED_LINE,
    nodeIcons: ['node_icon.png', 'node_icon.png'],
  };
}

/**
 * 构建实况窗胶囊（capsule）。
 *
 * ⚠️ 踩坑记录：`capsule.icon` 是**必填**的（即便 type 是 TIMER 也一样），
 * 不传报 401: The type of capsule.icon must be string | image.PixelMap。
 *
 * 所以这里把 CapsuleData 的字段**一次性填满**，避免"补一个又冒一个"：
 * type / status / icon / backgroundColor / isContentDisplayed / isTailIconDisplayed
 */
function makeTimerCapsule(
  contentText: string, ms: number
): liveViewManager.TimerCapsule {
  return {
    type: liveViewManager.CapsuleType.CAPSULE_TYPE_TIMER,
    status: 1,
    icon: 'liveview_icon.png',
    backgroundColor: '#FF1F86C7',
    isContentDisplayed: true,
    tailIcon: 'liveview_icon.png',
    isTailIconDisplayed: false,
    content: contentText,
    time: ms,
    isCountdown: true,
  };
}

/**
 * 构建交接意图（WantAgent）。
 *
 * `primary.clickAction` 在 TIMER 场景下是**必填**，不传报 401：
 * The type of primary.clickAction must be WantAgent。
 *
 * 用新版的 getWantAgent 构建（它把 WantAgentInfo 导出成具名类型，
 * 旧版没有），返回值在运行期与旧版 WantAgent 等价。
 */
async function createWantAgent(requestCode: number): Promise<WantAgentType | undefined> {
  try {
    const infos: Array<Want> = [
      {
        bundleName: BUNDLE_NAME,
        abilityName: ENTRY_ABILITY,
      },
    ];
    const info: abilityWantAgent.WantAgentInfo = {
      wants: infos,
      actionType: abilityWantAgent.OperationType.START_ABILITY,
      requestCode: requestCode,
      actionFlags: [abilityWantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
    };
    const agent: AbilityWantAgentType = await abilityWantAgent.getWantAgent(info);
    // 运行期同构，转成 clickAction 需要的旧版类型
    return agent as WantAgentType;
  } catch (e) {
    return undefined;
  }
}

/** 把毫秒倒计时格式化成「还有 X 分钟」 */
function humanCountdown(ms: number): string {
  const totalMin: number = Math.max(0, Math.round(ms / 60000));
  if (totalMin >= 60) {
    const h: number = Math.floor(totalMin / 60);
    const m: number = totalMin % 60;
    return m > 0 ? `${h} 小时 ${m} 分钟后` : `${h} 小时后`;
  }
  return `${totalMin} 分钟后`;
}

/**
 * 进度条百分比（0–100）。
 *
 * 语义：以「提前量」为整段。刚进入提前窗口时进度低，越接近上课越高。
 * 若已经超过提前量（比如用户提前 30 分钟就打开了开关），按剩余时间
 * 相对 60 分钟折算，避免一上来就是 100%。
 */
function progressValue(msToRemind: number, leadMinutes: number): number {
  const leadMs: number = Math.max(1, leadMinutes * 60 * 1000);
  if (msToRemind <= 0) {
    return 100;
  }
  const windowMs: number = msToRemind > leadMs ? 60 * 60 * 1000 : leadMs;
  const ratio: number = 1 - Math.min(1, msToRemind / windowMs);
  return Math.round(Math.max(0, Math.min(1, ratio)) * 100);
}

/** 实况窗上显示的内容 */
export interface LiveViewContent {
  /** 主标题，如「呼吸系统」 */
  title: string;
  /** 副标题，如「08:00 · 504 智慧教室」 */
  subtitle: string;
  /** 倒计时文案，如「15 分钟后」 */
  countdown: string;
  /** 胶囊短文本 */
  capsuleText: string;
}

/** 由课程 + 提前分钟数构建实况窗内容 */
export function buildContent(course: Course, leadMinutes: number): LiveViewContent {
  const hm: number[] = courseStartTime(course);
  const timeStr: string = hm[0] >= 0
    ? `${hm[0] < 10 ? '0' : ''}${hm[0]}:${hm[1] < 10 ? '0' : ''}${hm[1]}`
    : '--:--';
  const room: string = course.room && course.room.length > 0 ? ` · ${course.room}` : '';
  const ms: number = nextOccurrenceMs(course, leadMinutes);

  return {
    title: course.name,
    subtitle: `${timeStr}${room}`,
    countdown: humanCountdown(ms),
    capsuleText: `${leadMinutes} 分钟后上课`,
  };
}

/**
 * 启动一个课表实况窗。
 *
 * @returns 成功返回 null；失败返回可直接展示给用户的说明。
 *          失败**不抛异常**，调用方无需 try/catch —— 课表主流程不该被提醒功能拖垮。
 */
export async function startCourseLiveView(
  course: Course, leadMinutes: number
): Promise<string | null> {
  const probe: LiveViewProbe = await probeLiveView();
  if (probe.status !== LiveViewStatus.READY) {
    return probe.message;
  }

  const content: LiveViewContent = buildContent(course, leadMinutes);
  const id: number = liveViewIdFor(course.id, course.dayOfWeek, course.startSection);
  const ms: number = nextOccurrenceMs(course, leadMinutes);

  // clickAction 必填：点击实况窗要能跳回 App
  const agent: WantAgentType | undefined = await createWantAgent(id % 100000);
  if (agent === undefined) {
    return '无法构建跳转意图（WantAgent），请检查 bundleName/abilityName 配置';
  }

  const liveView: liveViewManager.LiveView = {
    id: id,
    // TIMER 是白名单里唯一能表达「距某时刻还有多久」的通用场景
    event: 'TIMER',
    isMute: false,
    /**
     * 版本号：更新/结束实况窗时新值必须**大于**旧值，否则更新会被拒
     * （1003500011 The liveView sequence is incorrect）。
     * 用毫秒时间戳保证单调递增。
     */
    sequence: Date.now() % 2147483647,
    timer: {
      time: ms,
      isCountdown: true,
    },
    liveViewData: {
      primary: {
        title: content.title,
        content: [{ text: content.subtitle }],
        // 结束后在通知栏保留 30 秒
        keepTime: 30,
        /**
         * ⚠️ TIMER 场景下 layoutData 是必填的，否则 startLiveView 直接抛
         * 401 Parameter error（The type of primary.layoutData must be LayoutData）。
         *
         * 用进度模板表达"距上课的进度"：progress 取 0–100 之间的值，
         * 这里用「剩余时间占总提前量的比例」反推，越接近上课越满。
         *
         * ⚠️ LAYOUT_TYPE_PROGRESS 下 nodeIcons 同样是必填
         * （401: The type of layoutData.nodeIcons must be Array<string|PixelMap>）。
         * 图片只能取 /resources/rawfile 下的文件名，数组长度要求 [2, 5]。
         */
        layoutData: makeProgressLayout(progressValue(ms, leadMinutes)),
        clickAction: agent,
      },
      capsule: makeTimerCapsule(content.capsuleText, ms),
    },
  };

  try {
    const result: liveViewManager.LiveViewResult = await liveViewManager.startLiveView(liveView);
    if (result.resultCode !== 0) {
      return `实况窗创建失败（${result.resultCode}）：${result.message}`;
    }
    return null;
  } catch (e) {
    const err = e as BusinessError;
    if (err.code === ERR_RIGHT_NOT_ENABLED) {
      return '未开通实况窗权限：需在 AppGallery Connect 为应用申请实况窗场景权限';
    }
    if (err.code === ERR_LIVEVIEW_NOT_ENABLED) {
      return '系统实况窗总开关未打开';
    }
    if (err.code === 1003500006) {
      // 已存在，先结束再重建
      await stopCourseLiveView(course);
      return startCourseLiveView(course, leadMinutes);
    }
    return `实况窗启动失败（${err.code ?? '未知'}）：${err.message ?? ''}`;
  }
}

/** 结束某门课的实况窗 */
export async function stopCourseLiveView(course: Course): Promise<void> {
  const id: number = liveViewIdFor(course.id, course.dayOfWeek, course.startSection);
  try {
    const liveView: liveViewManager.LiveView = {
      id: id,
      event: 'TIMER',
      liveViewData: {
        primary: {
          title: course.name,
        },
      },
    };
    await liveViewManager.stopLiveView(liveView);
  } catch (e) {
    // 结束失败不打扰用户（本来就没开或已过期）
  }
}

/** 结束全部实况窗（用于关闭提醒开关时） */
export async function stopAllCourseLiveViews(courses: Course[]): Promise<void> {
  for (let i = 0; i < courses.length; i++) {
    await stopCourseLiveView(courses[i]);
  }
}
