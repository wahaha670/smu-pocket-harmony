/**
 * Push Token 获取与展示。
 *
 * 为什么需要它
 * ------------
 * 实况窗「白名单调试」**是按 Push Token 添加设备的**（不是 UDID），
 * 所以必须先从应用里拿到 Push Token，再去 AGC 后台填。
 *
 * 前提条件（缺一不可，见 docs/实况窗白名单调试.md）：
 *   1. AGC 里为应用**开通推送服务**；
 *   2. `entry/src/main/module.json5` 的 metadata 里配置 `client_id`；
 *   3. 签名用的 Profile 与 AGC 上的应用证书指纹一致。
 *
 * 否则 getToken() 会抛 1000900010 (Illegal application identity)。
 */

import { pushService } from '@kit.PushKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface PushTokenResult {
  ok: boolean;
  token: string;
  /** 失败时给用户看的中文说明 */
  message: string;
  code?: number;
}

/**
 * 取 Push Token。
 *
 * 不抛异常 —— 拿不到 Token 不应该让设置页崩掉。
 */
export async function getPushToken(): Promise<PushTokenResult> {
  try {
    const token: string = await pushService.getToken();
    if (token && token.length > 0) {
      return { ok: true, token: token, message: '获取成功' };
    }
    return { ok: false, token: '', message: '返回了空 Token，检查 client_id 是否已配置' };
  } catch (e) {
    const err = e as BusinessError;
    let hint: string = `获取失败（${err.code ?? '未知'}）`;
    if (err.code === 1000900010) {
      hint = '身份校验失败：检查 AGC 是否已开通推送服务、client_id 是否正确、签名指纹是否上传（生效需 30–60 分钟）';
    } else if (err.code === 1000900001) {
      hint = '网络不可用，或设备未登录华为帐号';
    }
    return { ok: false, token: '', message: hint, code: err.code };
  }
}

/**
 * 删除本地 Push Token（换设备/排查时用）。
 */
export async function deletePushToken(): Promise<void> {
  try {
    await pushService.deleteToken();
  } catch (e) {
    // 删不掉不影响主流程
  }
}
