/**
 * 课程配色：课程名 → 颜色。
 *
 * 单独抽成模块，是为了让**课表页**和**桌面卡片**用同一套配色，
 * 避免两处各写一遍导致「同门课在两个地方颜色不同」。
 *
 * ## 为什么不用教务给的 bgcolor
 *
 * 实测真实数据（220 条整学期课程）：
 * - 教务**只给了 4 种颜色**，其中 `#1f86c7` 一个就占了 131 条（60%）；
 * - 更糟的是**同一门课在不同周颜色还会变**：
 *   「呼吸系统」出现过 4 种颜色，「综合高级英语」出现过 3 种。
 *
 * 结果就是整张课表大片同色、同一门课每周换色，完全看不出区分。
 */

/**
 * 课程色块调色板。
 *
 * 选取原则：
 * - **色相分散**：蓝/绿/橙/红/紫/青/棕/绿/玫红/靛/蓝绿/褐/黄绿/洋红，
 *   相邻两色在视觉上能立刻区分；
 * - **明度适中偏深**：`Theme.onCourseColor` 会自动判明暗配黑字或白字，
 *   所以不必拘泥深浅，但整组统一更耐看；
 * - 14 色可容纳 14 门不同课程，超出时循环使用。
 */
export const COURSE_PALETTE: string[] = [
  '#1F86C7', // 蓝
  '#5FB878', // 绿
  '#F59B00', // 橙
  '#E0564A', // 红
  '#7B68C4', // 紫
  '#17A2B8', // 青
  '#D4813F', // 棕橙
  '#4C9A2A', // 深绿
  '#C2557A', // 玫红
  '#5C6BC0', // 靛蓝
  '#00897B', // 蓝绿
  '#8D6E63', // 褐
  '#AFB42B', // 黄绿
  '#8E24AA'  // 洋红
];

/** 拿不到课程名时的兜底色 */
export const FALLBACK_COURSE_COLOR: string = '#1F86C7';

/**
 * 字符串的确定性哈希（FNV-1a 变体）。
 *
 * 要求：**同样输入永远得到同样结果**（跨进程、跨设备一致），
 * 这样同一门课的颜色不会因为重启 App 或换个入口而改变。
 * 不能用 `Math.random()` 之类的非确定因素。
 */
export function stableHash(text: string): number {
  let h = 2166136261;
  for (let i = 0; i < text.length; i++) {
    h = h ^ text.charCodeAt(i);
    h = (h * 16777619) >>> 0;
  }
  return h >>> 0;
}

/**
 * 为一组课程名分配互不相同的颜色。
 *
 * 算法：**哈希定位 + 线性探测**
 * 1. 课程名按字典序排序（保证顺序确定，不受数据到达顺序影响）；
 * 2. 每门课先用哈希算一个首选色位；
 * 3. 若该色位被占用，就往后探测第一个空位。
 *
 * 性质：
 * - **无冲突**：课程数 ≤ 调色板容量时，每门课颜色都不同；
 * - **确定**：同样的课程集合永远得到同样分配；
 * - **较稳**：新增一门课只影响它后面的少数课程，不会整表重排。
 */
export function assignCourseColors(names: string[]): Map<string, string> {
  const size = COURSE_PALETTE.length;
  const sorted: string[] = [];
  for (const n of names) {
    sorted.push(n);
  }
  sorted.sort();

  const taken: boolean[] = [];
  for (let i = 0; i < size; i++) {
    taken.push(false);
  }

  const map = new Map<string, string>();
  for (const n of sorted) {
    let idx = stableHash(n) % size;
    let guard = 0;
    while (taken[idx] && guard < size) {
      idx = (idx + 1) % size;
      guard++;
    }
    taken[idx] = true;
    map.set(n, COURSE_PALETTE[idx]);
  }
  return map;
}

/**
 * 取一门课的颜色。
 *
 * 传入已算好的映射表（由 [assignCourseColors] 生成）；
 * 表里没有时退回哈希取模，保证任何时候都有颜色可用。
 */
export function courseColor(name: string, map: Map<string, string>): string {
  const key = name.trim();
  if (key.length === 0) {
    return FALLBACK_COURSE_COLOR;
  }
  const c = map.get(key);
  if (c !== undefined) {
    return c;
  }
  return COURSE_PALETTE[stableHash(key) % COURSE_PALETTE.length];
}
