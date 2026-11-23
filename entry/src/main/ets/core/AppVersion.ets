/**
 * 应用版本号（运行时从包信息读取）。
 *
 * ## 为什么不用写死的常量
 *
 * 之前 `SettingsScreen` 里写的是 `const APP_VERSION = 'v1.1.1'`，
 * 而 `AppScope/app.json5` 的 `versionName` 是另一处手写值。
 * 两处都要人记着手改 —— 结果功能迭代到 1.7.x 了，
 * 「关于/设置」页显示的还是 **v1.1.1**（实测装配后确认过）。
 *
 * 改成运行时读 `BundleInfo.versionName`，**单一数据源**：
 * 只有 `App.json5` 一处需要维护，界面上永远不会再对不上。
 *
 * ## 为什么用 Sync 版本
 *
 * `getBundleInfoForSelfSync` 是同步的，可以在组件构造/首帧前就拿到值，
 * 不会出现「先显示占位、200ms 后跳成真实版本」的闪烁。
 * 读失败时退回空串，由调用方决定要不要显示。
 */
import bundleManager from '@ohos.bundle.bundleManager';

/** 读取失败时的兜底值 */
const FALLBACK: string = '';

let cached: string | undefined = undefined;

/**
 * 取应用版本名，例如 `"1.7.2"`。
 *
 * 结果做了缓存：包信息在进程生命周期内不会变，没必要反复调。
 */
export function appVersionName(): string {
  if (cached !== undefined) {
    return cached;
  }
  let out: string = FALLBACK;
  try {
    const info = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
    );
    const name: string = info.versionName;
    if (name !== undefined && name.length > 0) {
      out = name;
    }
  } catch (e) {
    // 取不到就留空，界面会退回只显示应用名
    out = FALLBACK;
  }
  cached = out;
  return out;
}

/**
 * 带 `v` 前缀的版本号，例如 `"v1.7.2"`。
 * 读不到时返回空串（调用方应跳过这段，不要显示孤零零的 `v`）。
 */
export function appVersionLabel(): string {
  const name = appVersionName();
  return name.length > 0 ? `v${name}` : '';
}
