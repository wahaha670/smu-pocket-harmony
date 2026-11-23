/**
 * 登录态（cookie）存储与 HTTP 传输层。
 *
 * Android 版用 OkHttp + CookieJar；HarmonyOS 用 `@ohos.net.http`，
 * 但**没有内置 CookieJar**，需要自己维护。这里做了三件事：
 *
 * 1. 按 host 分别存 cookie —— CAS / 统一身份认证场景下
 *    `cas.xxx.edu.cn` 和 `zhjw.xxx.edu.cn` 各有一份，只存一个必然出错；
 * 2. 自动带 Cookie 头、自动回收 Set-Cookie；
 * 3. 补齐 Referer / X-Requested-With —— 缺了教务会把你当爬虫，
 *    返回登录页 HTML 而不是数据。
 *
 * 会话失效检测尤其重要：cookie 过期后，教务**不会**返回 401，
 * 而是 302 到登录页然后回一个 **200 + 一整页登录 HTML**。
 * 只看 HTTP 状态码会拿一页 HTML 去解析，报出「JSON 解析失败」这种误导性错误。
 *
 * 鸿蒙 API 事实（已核对 @ohos.net.http.d.ts）：
 * - 请求体字段是 **`extraData`**，不是 `data`；
 * - 响应头是 `Object`，需要按 Record 访问；
 * - 响应里另有 `cookies` 字段（本实现仍从 header 的 Set-Cookie 解析，
 *   因为需要按 host 归档）。
 *
 * 移植自 Android 版 core/Net.kt / Session.kt / JwClient.kt。
 */
import http from '@ohos.net.http';
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';

/** 登录态失效。上层抓到它就清 cookie、把用户送回扫码页 */
export class SessionExpiredError extends Error {
  constructor(message: string = '登录态失效，请重新扫码登录') {
    super(message);
    this.name = 'SessionExpiredError';
  }
}

export interface Req {
  url: string;
  method?: string;
  headers?: Record<string, string>;
  /** application/x-www-form-urlencoded */
  form?: Record<string, string>;
  /** application/json 原始体 */
  json?: string;
  referer?: string;
}

export interface Resp {
  code: number;
  body: string;
  contentType: string;
}

/** 从 URL 里取 host；取不到返回 undefined */
export function hostOf(url: string): string | undefined {
  const m = url.match(/^https?:\/\/([^/?#:]+)/i);
  if (!m) {
    return undefined;
  }
  return m[1].toLowerCase();
}

/**
 * 登录态存储的抽象。
 *
 * 放在 Net.ets 里而不是 AppViewModel.ets，是为了避免循环依赖：
 * AppViewModel 需要这个类型，而 Net 里的 SessionStore 要实现它。
 * 定义在最底层（Net）最干净。
 */
export interface SessionStoreLike {
  isLoggedIn(): boolean;
  saveRawCookieHeader(url: string, raw: string): void;
  cookieHeader(url: string): string;
  clear(): Promise<void>;
}

/**
 * Cookie 存储。
 *
 * 结构：host → { name → value }。
 * 落盘到 Preferences（等价于 Android 的 SharedPreferences），
 * 每个 host 存成一个 `"a=1; b=2"` 字符串，和 Android 版格式一致。
 */
export class SessionStore implements SessionStoreLike {
  static readonly PREF_NAME: string = 'smu_session';
  static readonly KEY_PREFIX: string = 'h_';

  private prefs: preferences.Preferences | undefined;
  private cache: Map<string, Map<string, string>> = new Map<string, Map<string, string>>();
  private ready: boolean = false;

  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  /** 首次使用时初始化（Preferences 是异步 API，必须先 await） */
  async init(): Promise<void> {
    if (this.ready) {
      return;
    }
    this.prefs = await preferences.getPreferences(this.context, SessionStore.PREF_NAME);
    this.ready = true;
  }

  /** 拼成请求用的 Cookie 头 */
  cookieHeader(url: string): string {
    const host = hostOf(url);
    if (host === undefined) {
      return '';
    }
    const table = this.table(host);
    const parts: string[] = [];
    table.forEach((value: string, name: string) => {
      parts.push(`${name}=${value}`);
    });
    return parts.join('; ');
  }

  /** 回收响应里的 Set-Cookie（可能有多条） */
  saveSetCookie(url: string, setCookieHeaders: string[]): void {
    const host = hostOf(url);
    if (host === undefined) {
      return;
    }
    for (const headerText of setCookieHeaders) {
      if (!headerText || headerText.trim().length === 0) {
        continue;
      }
      // 每个 Set-Cookie 形如 "JSESSIONID=abc; Path=/; HttpOnly"
      // 只取第一段 name=value
      const firstPair = headerText.split(';')[0];
      const eq = firstPair.indexOf('=');
      if (eq > 0) {
        const name = firstPair.substring(0, eq).trim();
        const value = firstPair.substring(eq + 1).trim();
        if (name.length > 0) {
          this.table(host).set(name, value);
        }
      }
    }
    this.persist(host);
  }

  /** Web 登录成功后拿到的一整串 cookie，直接灌进来 */
  saveRawCookieHeader(url: string, rawHeader: string): void {
    const host = hostOf(url);
    if (host === undefined || rawHeader.trim().length === 0) {
      return;
    }
    const table = this.table(host);
    for (const pair of rawHeader.split(';')) {
      const eq = pair.indexOf('=');
      if (eq > 0) {
        const name = pair.substring(0, eq).trim();
        const value = pair.substring(eq + 1).trim();
        if (name.length > 0) {
          table.set(name, value);
        }
      }
    }
    this.persist(host);
  }

  /**
   * 是否已经有登录态。
   *
   * 不能只查 `this.cache`：那是惰性从磁盘加载的内存表，
   * 冷启动时它是空的，会导致「明明有 cookie 却判定未登录」
   * → 用户每次开 App 都被踢回登录页。
   * 所以这里必须直接查 Preferences 里有没有任何 `h_*` 键。
   */
  isLoggedIn(): boolean {
    // 先看内存里已经加载的表
    let found = false;
    this.cache.forEach((table: Map<string, string>) => {
      if (table.size > 0) {
        found = true;
      }
    });
    if (found) {
      return true;
    }
    // 再查磁盘：有任意一个非空的 h_* 键就算已登录
    if (this.prefs === undefined) {
      return false;
    }
    const all = this.prefs.getAllSync() as Record<string, Object>;
    const keys = Object.keys(all);
    for (const k of keys) {
      if (k.startsWith(SessionStore.KEY_PREFIX)) {
        const v = all[k];
        if (typeof v === 'string' && v.length > 0) {
          return true;
        }
      }
    }
    return false;
  }

  async clear(): Promise<void> {
    this.cache.clear();
    if (this.prefs !== undefined) {
      await this.prefs.clear();
      await this.prefs.flush();
    }
  }

  /** 把某 host 的表落盘（内部方法） */
  private persist(host: string): void {
    const table = this.cache.get(host);
    if (table === undefined || this.prefs === undefined) {
      return;
    }
    const parts: string[] = [];
    table.forEach((value: string, name: string) => {
      parts.push(`${name}=${value}`);
    });
    this.prefs.putSync(SessionStore.KEY_PREFIX + host, parts.join('; '));
    this.prefs.flush();
  }

  /** 取某 host 的 cookie 表（惰性从磁盘加载） */
  private table(host: string): Map<string, string> {
    let table = this.cache.get(host);
    if (table !== undefined) {
      return table;
    }
    table = new Map<string, string>();
    if (this.prefs !== undefined) {
      const raw = this.prefs.getSync(SessionStore.KEY_PREFIX + host, '') as string;
      for (const pair of raw.split(';')) {
        const eq = pair.indexOf('=');
        if (eq > 0) {
          const name = pair.substring(0, eq).trim();
          const value = pair.substring(eq + 1).trim();
          if (name.length > 0) {
            table.set(name, value);
          }
        }
      }
    }
    this.cache.set(host, table);
    return table;
  }
}

/** 判断响应体像不像「被踢回登录页」 */
const LOGIN_URL_HINTS: string[] = ['login', '/cas/', 'sso', 'authserver', 'passport'];

export function looksLikeLoginPage(code: number, body: string, finalUrl: string): boolean {
  if (code === 401 || code === 403) {
    return true;
  }
  const lowerUrl = finalUrl.toLowerCase();
  for (const hint of LOGIN_URL_HINTS) {
    if (lowerUrl.indexOf(hint) >= 0) {
      return true;
    }
  }
  // 返回 HTML 且带密码框，基本就是登录页
  const head = body.substring(0, 4096).toLowerCase();
  const isHtml = head.indexOf('<html') >= 0 || head.indexOf('<!doctype') >= 0;
  if (isHtml) {
    if (head.indexOf('type="password"') >= 0 || head.indexOf("type='password'") >= 0) {
      return true;
    }
  }
  return false;
}

/**
 * 教务专用传输实现。
 *
 * 要点：
 * - 自动带 Cookie / 回收 Set-Cookie
 * - 自动补 Referer / X-Requested-With / Accept
 * - 把「200 + 登录页 HTML」翻译成可捕获的 SessionExpiredError
 */
export class JwTransport {
  /** 统一 UA：教务会看这个头 */
  static readonly UA: string = 'SMUPocket/1.1 (HarmonyOS)';

  private busy: boolean = false;
  private session: SessionStore;
  private baseUrl: string;

  constructor(session: SessionStore, baseUrl: string) {
    this.session = session;
    this.baseUrl = baseUrl;
  }

  /**
   * 发一次表单 POST（教务全是这种）。
   *
   * @throws SessionExpiredError 当响应看起来是登录页时
   * @throws Error 当 HTTP 状态非 2xx 时
   */
  async postForm(path: string, form: Record<string, string>): Promise<string> {
    const url = this.baseUrl + path;
    const resp = await this.exec({
      url: url,
      method: 'POST',
      form: form,
      referer: this.baseUrl
    });
    return resp.body;
  }

  async exec(req: Req): Promise<Resp> {
    // 单请求串行：避免同一时刻多个 HttpRequest 互相干扰
    while (this.busy) {
      await sleep(20);
    }
    this.busy = true;
    try {
      return await this.execInner(req);
    } finally {
      this.busy = false;
    }
  }

  private async execInner(req: Req): Promise<Resp> {
    const method = (req.method !== undefined ? req.method : 'GET').toUpperCase();

    const request = http.createHttp();
    try {
      // header 在鸿蒙里是 Object，用普通对象即可
      const header: Record<string, string> = {};
      header['User-Agent'] = JwTransport.UA;
      header['Referer'] = req.referer !== undefined ? req.referer : this.baseUrl;
      header['X-Requested-With'] = 'XMLHttpRequest';
      header['Accept'] = 'application/json, text/javascript, */*; q=0.01';

      const cookie = this.session.cookieHeader(req.url);
      if (cookie.length > 0) {
        header['Cookie'] = cookie;
      }
      if (req.headers !== undefined) {
        const keys = Object.keys(req.headers);
        for (const k of keys) {
          header[k] = req.headers[k];
        }
      }

      // ⚠️ 鸿蒙的请求体字段是 extraData，不是 data
      let extraData: string | undefined = undefined;
      if (req.form !== undefined) {
        const pairs: string[] = [];
        const keys = Object.keys(req.form);
        for (const k of keys) {
          pairs.push(`${encodeURIComponent(k)}=${encodeURIComponent(req.form[k])}`);
        }
        extraData = pairs.join('&');
        header['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';
      } else if (req.json !== undefined) {
        extraData = req.json;
        header['Content-Type'] = 'application/json; charset=utf-8';
      }

      const options: http.HttpRequestOptions = {
        method: method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: header,
        connectTimeout: 15000,
        readTimeout: 20000,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        extraData: extraData
      };

      const result = await request.request(req.url, options);

      const respHeaders = result.header as Record<string, Object>;
      // 回收 Set-Cookie（大小写不敏感地找）
      const setCookie = collectSetCookie(respHeaders);
      if (setCookie.length > 0) {
        this.session.saveSetCookie(req.url, setCookie);
      }

      const code = result.responseCode as number;
      const bodyText = typeof result.result === 'string' ? result.result : JSON.stringify(result.result);

      if (code === 401 || code === 403) {
        throw new SessionExpiredError();
      }
      if (looksLikeLoginPage(code, bodyText, req.url)) {
        throw new SessionExpiredError();
      }
      if (code < 200 || code > 299) {
        throw new Error(`HTTP ${code}`);
      }

      const contentType = headerValue(respHeaders, 'content-type');
      return { code: code, body: bodyText, contentType: contentType };
    } finally {
      request.destroy();
    }
  }
}

/** 从响应头里收集所有 Set-Cookie（大小写不敏感） */
function collectSetCookie(headers: Record<string, Object>): string[] {
  const out: string[] = [];
  const keys = Object.keys(headers);
  for (const k of keys) {
    if (k.toLowerCase() === 'set-cookie') {
      const v = headers[k];
      if (typeof v === 'string') {
        // 多个 cookie 可能用换行分隔；逗号在 Expires 里是合法的，不能按逗号切
        for (const line of v.split('\n')) {
          if (line.trim().length > 0) {
            out.push(line.trim());
          }
        }
      } else if (Array.isArray(v)) {
        for (const item of v as Object[]) {
          if (typeof item === 'string' && item.trim().length > 0) {
            out.push((item as string).trim());
          }
        }
      }
    }
  }
  return out;
}

function headerValue(headers: Record<string, Object>, name: string): string {
  const lower = name.toLowerCase();
  const keys = Object.keys(headers);
  for (const k of keys) {
    if (k.toLowerCase() === lower) {
      const v = headers[k];
      return typeof v === 'string' ? v : '';
    }
  }
  return '';
}

export function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}
