# dist / 构建产物

## 这里的文件

| 文件 | 说明 |
|---|---|
| `smu-pocket-harmony-v1.1.1-unsigned.hap` | **未签名**的安装包，需要你自己签名后才能装到设备上 |

## ⚠️ 为什么没有可直接安装的包

**鸿蒙的机制限制**：每一个安装包都必须用**绑定了目标设备 UDID** 的证书签名。
调试证书只能在签名时登记过的那台设备上安装，所以：

- 开发者自己签的包，**给别人装不上**
- 想让别人也能装，必须走 **AppGallery Connect 申请发布证书**，
  且应用要在 AGC 注册并走审核

因此本仓库定位是**源码项目**，不提供"下载即装"的包。

## 我要装到自己手机，怎么做

```powershell
# ⚠️ 若本机开了代理，先清掉（否则登录报 ERR_TLS_CERT_ALTNAME_INVALID）
Remove-Item Env:HTTP_PROXY,Env:HTTPS_PROXY,Env:http_proxy,Env:https_proxy -ErrorAction SilentlyContinue
$env:NODE_USE_ENV_PROXY='0'

devecocli auth login                        # 登录华为开发者账号
devecocli signature generate --product default   # 读设备 UDID，生成证书并写入 build-profile.json5
devecocli run --device <你的设备序列号>          # 编译 + 签名 + 安装 + 启动
```

详细步骤与常见问题见 [../docs/安装到手机.md](../docs/安装到手机.md)。

## 只想编译、不装设备

不需要任何签名配置，直接构建即可产出上面的未签名包：

```bash
hvigorw --mode module -p product=default assembleHap --no-daemon
```

> `build-profile.json5` **故意不含签名配置** —— 里面会有个人绝对路径与签名口令，
> 不适合提交到公开仓库。跑 `signature generate` 会自动写回去。
