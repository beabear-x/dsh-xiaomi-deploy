# 在 Android 手机的 Minis 部署 DeepSeek Harness（DSH）

> 将 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 部署在 **Minis App** 的 Alpine Linux 沙箱中，并从**手机系统浏览器**（Chrome、夸克等）访问 Web UI。
>
> 本仓库的方案已在 Android ARM64（`arm64-v8a`）、Minis / Alpine Linux 3.21（`aarch64` / musl）、Node.js 22 上实测。DSH 仍处于 Developer Preview，未来版本可能改变依赖或启动方式。

## 结论：推荐方案

手机上不建议优先走 DSH 的完整源码构建；推荐使用本仓库提供的脚本：

1. 安装 DeepSeek 官方发布的 npm 运行包；
2. 在 Minis 内单独编译 ARM64 版 `node-pty`；
3. 将生成的 `pty.node` 部署到运行包需要的 `prebuilds/linux-arm64/`；
4. 用 `node --expose-internals` 启动 DSH；
5. 在同一部手机的 Chrome 等系统浏览器访问 `http://127.0.0.1:3080/`。

实测该路径可返回 Web 页面 **HTTP 200**、Web API 正常，并显示 DSH 首次配置界面。

## 不需要什么

- **不需要 DeepSeek API Key** 才能安装或打开网页。首次引导可选“稍后配置”；只有真正发送模型请求时才需要可用的模型凭据。
- **不需要 Shizuku。** Shizuku 只可用于方便地从命令行唤起 Chrome；编译原生模块和访问 localhost 都不依赖它。
- **不要暴露到局域网。** 当前 DSH 明确拒绝 `--host 0.0.0.0`。网页端拥有本地代理/工具能力，暴露给其他设备不安全。

## 环境要求

在 Minis 的终端中检查：

```sh
cat /etc/os-release
uname -m
node --version
npm --version
```

已验证环境：

- Alpine Linux；
- `aarch64` / ARM64；
- Node.js **22 或更高版本**；
- `npm`、`python3`、`make`、`cc`、`c++`。

若缺少编译工具，执行：

```sh
apk add --no-cache build-base python3
```

## 一键部署

### 1. 克隆本仓库

```sh
git clone https://github.com/beabear-x/dsh-xiaomi-deploy.git
cd dsh-xiaomi-deploy
```

如未安装 `git`：

```sh
apk add --no-cache git
```

### 2. 安装 DSH 并修复 ARM64 原生模块

```sh
sh scripts/install-dsh.sh
```

脚本会：

- 安装官方 `@deepseek-ai/dsh@0.1.0-rc.6`；
- 下载相同版本的 `node-pty` 源码；
- 通过 `npm_config_enable_lto=false` 关闭 LTO 后本地构建；
- 将 ARM64 `pty.node` 写入 DSH 实际查找的位置；
- 运行一个 PTY 加载测试。

默认安装路径为：

```text
/var/minis/shared/deepseek-harness/runtime
```

运行状态、设置和工作区数据位于：

```text
/var/minis/shared/deepseek-harness/state
```

可在执行前指定其他 DSH 版本或数据目录：

```sh
DSH_VERSION=0.1.0-rc.6 sh scripts/install-dsh.sh
DSH_MINIS_DIR=/var/minis/shared/my-dsh sh scripts/install-dsh.sh
```

升级 DSH 后，应再次运行安装脚本，以针对新包中实际的 `node-pty` 版本重新构建。

### 3. 启动本机 Web UI

```sh
sh scripts/start-dsh-web.sh
```

成功时输出：

```text
DSH Web UI is ready: http://127.0.0.1:3080/
```

也可选择端口：

```sh
sh scripts/start-dsh-web.sh 3081
```

### 4. 用系统浏览器访问

在同一部手机的 **Chrome / 夸克 / 系统浏览器** 地址栏打开：

```text
http://127.0.0.1:3080/
```

或点击：<http://127.0.0.1:3080/>

`127.0.0.1` 是手机自身的回环地址，不是 Minis 内置浏览器专用地址。只要浏览器和 Minis 在同一部手机上，就能访问同一个本地服务。

首次出现“添加一个 API Key 开始使用”是正常现象。可以点“**稍后配置**”；网页和设置页在无 Key 状态下仍可使用，发送消息才会需要模型凭据。

## 为什么普通安装会失败？

### 1. 缺少 Alpine ARM64 的 `node-pty` 预编译模块

DSH 的本地终端功能依赖 `node-pty`。桌面 Linux 可能下载到预编译二进制，但 Minis 是 **Alpine ARM64 / musl**，通常没有可直接使用的 `linux-arm64` 产物。

启动时会因此报：

```text
Failed to load native module: pty.node
```

本仓库的安装脚本会本地构建它，并部署到：

```text
node_modules/node-pty/prebuilds/linux-arm64/pty.node
```

### 2. Node 22 的 LTO 会让 node-gyp 在该环境中失败

自动回退编译时，当前 Node 22 会注入类似以下的 LTO 参数：

```text
-flto=4 -fuse-linker-plugin -ffat-lto-objects
```

在 Alpine ARM64 / PRoot 的组合中，可能导致：

```text
lto-wrapper: fatal error
recipe commences before first target
Operation not permitted
```

解决方法是构建 `node-pty` 时关闭 LTO：

```sh
npm_config_enable_lto=false ./node_modules/.bin/node-gyp rebuild
```

### 3. DSH 运行时需要 `--expose-internals`

DSH `0.1.0-rc.6` 会挂载配置监视/HMR 能力。在 Node 22 中普通的：

```sh
dsh web
```

可能先打印 URL，随后因以下错误退出：

```text
--expose-internals is required for HMR service
```

因此启动脚本使用：

```sh
node --expose-internals ./node_modules/@deepseek-ai/dsh/lib/bin.js web --port 3080
```

这是当前 DSH 预览版的兼容性参数，不代表需要开启 Android 开发者权限。

## 手动部署流程

若不使用脚本，可按下列步骤操作。

### 安装官方运行包

```sh
BASE=/var/minis/shared/deepseek-harness
mkdir -p "$BASE/runtime"
cd "$BASE/runtime"
printf '{"name":"dsh-minis-runtime","private":true}\n' > package.json
npm install --omit=dev @deepseek-ai/dsh@0.1.0-rc.6
```

### 关闭 LTO 编译 `node-pty`

```sh
BASE=/var/minis/shared/deepseek-harness
RUNTIME=$BASE/runtime
PTY_DIR=$RUNTIME/node_modules/node-pty
PTY_VERSION=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.argv[1],'utf8')).version)" "$PTY_DIR/package.json")

rm -rf "$BASE/build-node-pty"
mkdir -p "$BASE/build-node-pty"
cd "$BASE/build-node-pty"
npm pack "node-pty@$PTY_VERSION" --silent
tar -xzf "node-pty-$PTY_VERSION.tgz"
cd package
npm install --ignore-scripts --omit=dev
npm install --ignore-scripts --no-save node-gyp@12
npm_config_enable_lto=false ./node_modules/.bin/node-gyp rebuild

mkdir -p "$PTY_DIR/prebuilds/linux-arm64"
cat build/Release/pty.node > "$PTY_DIR/prebuilds/linux-arm64/pty.node"
chmod 755 "$PTY_DIR/prebuilds/linux-arm64/pty.node"
```

验证原生模块：

```sh
cd "$RUNTIME"
node -e "const p=require('node-pty'); const t=p.spawn('sh',['-c','exit 0'],{name:'xterm'}); t.onExit(()=>process.exit(0)); setTimeout(()=>process.exit(1),2000)"
```

返回 `0` 即验证成功。

### 启动与检查

```sh
BASE=/var/minis/shared/deepseek-harness
cd "$BASE/runtime"
mkdir -p "$BASE/state"
DSH_HOME="$BASE/state" \
node --expose-internals ./node_modules/@deepseek-ai/dsh/lib/bin.js web --port 3080 \
  > "$BASE/dsh-web.log" 2>&1 &

wget -S -O /dev/null http://127.0.0.1:3080/
tail -80 "$BASE/dsh-web.log"
```

预期日志包括：

```text
dsh web: http://127.0.0.1:3080
HTTP/1.1 200 OK
```

## 故障排查

| 表现 | 原因与处理 |
|---|---|
| `Failed to load native module: pty.node` | 没有部署 ARM64 `node-pty`。重新执行 `sh scripts/install-dsh.sh`。 |
| `lto-wrapper` / `recipe commences before first target` | `node-pty` 自动构建启用了 LTO。请使用脚本或以 `npm_config_enable_lto=false` 手动重建。 |
| URL 打印后进程退出，日志含 `--expose-internals is required` | 使用 `sh scripts/start-dsh-web.sh`，不要直接使用 `dsh web`。 |
| 系统浏览器显示无法连接 | 服务尚未启动、已被 Android 回收或端口被占用。检查 `/var/minis/shared/deepseek-harness/dsh-web.log` 后重启。 |
| 页面显示“添加 API Key” | 正常，不代表安装失败。选择“稍后配置”。 |
| 发送消息后提示 `MISSING_CREDENTIAL` | 缺少模型凭据，并非 Web 服务故障。可之后在 DSH 设置中配置 DeepSeek API Key 或其他模型/代理。 |
| 想从另一台设备访问 | 不建议且当前不受支持；DSH 默认只绑定 `127.0.0.1`，并拒绝 `--host 0.0.0.0`。 |

## 运行与安全注意事项

- 服务只绑定本机回环地址，适合在**同一部手机**的浏览器中使用。
- Android 若冻结 Minis 或回收进程，Node 服务会停止；再次进入 Minis 后重新运行启动脚本即可。
- 需要备份时，备份 `/var/minis/shared/deepseek-harness/state`。
- 不要把 API Key 写入脚本、Git 仓库、公开 issue 或聊天记录；请通过 DSH 的设置界面保存。
- 本方案不需要 Shizuku。已有 Shizuku 的用户最多用它自动启动 Chrome，不应将其当作部署前置条件。

## 实测版本

| 项目 | 实测值 |
|---|---|
| 手机 CPU ABI | `arm64-v8a` |
| Minis Linux | Alpine Linux 3.21 / `aarch64` / musl |
| Node.js | 22.23.2 |
| DSH npm 包 | `@deepseek-ai/dsh@0.1.0-rc.6` |
| 服务地址 | `http://127.0.0.1:3080/` |
| 原生修复 | `node-pty@1.1.0`，以禁用 LTO 的方式构建 ARM64 `pty.node` |

---

欢迎提交 Issue 或 PR，补充其他手机型号、Minis 版本和 DSH 版本的验证结果。
