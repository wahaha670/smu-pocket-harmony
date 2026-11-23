/**
 * 主题与配色。
 *
 * 对齐 Android 版的 Material3 语义：
 * - 跟随系统深浅色
 * - 主色用教务蓝（和原版观感一致）
 *
 * 鸿蒙用 `@ohos.app.ability.Configuration` 感知深浅色，
 * 组件里通过 @StorageLink('colorMode') 读取。
 */

/** 语义色板 */
export interface AppColors {
  primary: string;
  onPrimary: string;
  background: string;
  surface: string;
  surfaceVariant: string;
  onSurface: string;
  onSurfaceVariant: string;
  error: string;
  outline: string;

  // ---- 分数分档（文字色）----
  //
  // 成绩页按 90/80/60 分档上色。浅色主题用**深色文字**压在浅底上；
  // 深色主题必须换成**亮色文字**，否则深绿/深红在深底上几乎看不见。
  scoreExcellent: string;
  scoreGood: string;
  scoreFair: string;
  scorePoor: string;

  // ---- 分数分档（徽标底色）----
  //
  // 浅色主题是"浅色底 + 深色字"；深色主题若沿用 #DCEEF9 这类浅底，
  // 会在深色页面里亮得刺眼。所以改成**同色相的深色底**，
  // 配上面的亮色文字 —— 保持同一套色彩语义，只是明度反过来。
  badgeExcellent: string;
  badgeGood: string;
  badgeFair: string;
  badgePoor: string;

  /** 提醒色：离线缓存、需要重新登录等需要注意但不算错误的状态 */
  warning: string;

  /** 「自主学习」小标签（课表格子里的小圆角标签） */
  chipSelfStudyBg: string;
  chipSelfStudyText: string;
}

const LIGHT: AppColors = {
  primary: '#1F86C7',
  onPrimary: '#FFFFFF',
  background: '#F7F8FA',
  surface: '#FFFFFF',
  surfaceVariant: '#E8EBF0',
  onSurface: '#1B1B1B',
  onSurfaceVariant: '#5F6673',
  error: '#C62828',
  outline: '#D5DAE2',
  scoreExcellent: '#0B8A4B',
  scoreGood: '#1F86C7',
  scoreFair: '#C77700',
  scorePoor: '#C62828',
  badgeExcellent: '#DCF3E6',
  badgeGood: '#DCEEF9',
  badgeFair: '#FBEFD9',
  badgePoor: '#F9DEDE',
  warning: '#C77700',
  chipSelfStudyBg: '#D6F3E2',
  chipSelfStudyText: '#0B6B3A'
};

const DARK: AppColors = {
  primary: '#5FB3E0',
  onPrimary: '#0B1A24',
  background: '#101215',
  surface: '#1A1D22',
  surfaceVariant: '#262B32',
  onSurface: '#ECEEF1',
  onSurfaceVariant: '#A6ADB8',
  error: '#EF6B6B',
  outline: '#333A44',
  // 分档文字：整体提亮到在 #1A1D22 上清晰可读
  scoreExcellent: '#4ADE80',
  scoreGood: '#5FB3E0',
  scoreFair: '#F5A623',
  scorePoor: '#EF6B6B',
  // 分档底色：同色相压暗，作为徽标背景
  badgeExcellent: '#16351F',
  badgeGood: '#12303F',
  badgeFair: '#382B12',
  badgePoor: '#3A1D1D',
  warning: '#F5A623',
  chipSelfStudyBg: '#16351F',
  chipSelfStudyText: '#4ADE80'
};

export class Theme {
  /** @param isDark 是否深色模式 */
  static colors(isDark: boolean): AppColors {
    return isDark ? DARK : LIGHT;
  }

  /** 把教务工的 "#1f86c7" 解析成颜色；解析不了返回 undefined */
  static parseHex(hex: string | undefined): string | undefined {
    if (!hex) {
      return undefined;
    }
    const t = hex.trim();
    if (/^#[0-9a-fA-F]{6}$/.test(t)) {
      return t;
    }
    if (/^#[0-9a-fA-F]{8}$/.test(t)) {
      return t.substring(0, 7);
    }
    return undefined;
  }

  /**
   * 判断颜色深浅，决定文字用黑还是白。
   * 用 sRGB 相对亮度近似（和 Compose 的 luminance() 结论一致）。
   */
  static isLightColor(hex: string): boolean {
    const t = hex.trim();
    if (!/^#[0-9a-fA-F]{6}$/.test(t)) {
      return false;
    }
    const r = Number.parseInt(t.substring(1, 3), 16) / 255;
    const g = Number.parseInt(t.substring(3, 5), 16) / 255;
    const b = Number.parseInt(t.substring(5, 7), 16) / 255;
    const lin = (c: number): number => (c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
    const luminance = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
    return luminance > 0.55;
  }

  /** 课程块的前景色：亮色块配深字，深色块配白字 */
  static onCourseColor(hex: string | undefined): string {
    if (hex === undefined) {
      return '#FFFFFF';
    }
    return Theme.isLightColor(hex) ? '#1B1B1B' : '#FFFFFF';
  }
}
