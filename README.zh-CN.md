# MyGo 音乐 (mygo_mobile)

[English](README.md) | 简体中文

![phone](screenshots/phone.jpg)

一款移动端（Flutter）音乐播放器，可**原样运行 MyGo Music 插件**——与桌面应用 [egoist/mygo-music](https://github.com/egoist/mygo-music)
加载的 `plugin.json` + `index.js` 插件包完全相同。应用本身不提供任何音乐服务：所有曲库、登录、音频流和歌词
都来自已安装的插件（例如 [kugou-lite](https://github.com/bitbyte404/mygo-music-kugou-lite)）。

优先支持 Android（包名 `io.github.bitbyte404.mygo_mobile`）；代码为纯 Flutter + dart:ffi，因此
后续可跟进 iOS。

## 功能

- **外观与动效与 MyGo Music 一致**，并针对触屏做了适配：MyGo 的配色（浅色与深色，跟随
  系统）、字号层级、图标、封面、歌曲行、胶囊标签、播放栏、Now Playing 以弹簧动画从播放栏
  展开并以封面配色作背景，以及会平滑滚动到当前演唱行的同步歌词。不使用 Material 默认外观。参见 [docs/DESIGN.md](docs/DESIGN.md)。
- **按宽度分级的自适应布局**：手机使用底部标签栏（首页 / 搜索 / 我的）和迷你播放器，可
  展开为 Now Playing（点击或上拉；下拉 Now Playing 关闭）；平板、折叠屏
  和横屏（≥ 840 dp）使用桌面布局：插件导航位于侧边栏，卡片
  网格、播放栏，以及封面与歌词并排的 Now Playing；600–840 dp 使用图标导航栏（icon rail）。
- **Edge to edge（全面屏沉浸）**：内容和封面绘制在透明的状态栏和导航栏之下（无
  对比度遮罩，短边适配刘海/挖孔）；系统栏图标颜色跟随主题和 Now Playing 的
  封面；标签栏和迷你播放器位于手势条或三键导航栏之上。
- **插件运行时**——每个插件在各自的 QuickJS-ng 引擎（`libmygojs.so`）中运行，各占一个
  后台 isolate，桌面端的宿主 API 用 Dart 重新实现：存储、设置、
  多语言（`host.t`）、md5 / AES / RSA、仅限插件声明的网络权限范围内的 `fetch`、
  定时器，以及登录提示（二维码 / 链接）。
- **安装插件**：可从 GitHub 仓库安装（通过 codeload 下载默认分支 zip；`plugin.json` 位于
  根目录或下一级目录），也可从本地 zip 安装，安装前会进行权限审查。
  更新检查从 raw.githubusercontent.com 读取仓库的 `plugin.json`（不受 GitHub API 速率限制）。
  深层链接 `mygo-music://install-plugin?repo=owner/repo`（与桌面应用响应的一致）会打开安装界面。
- **浏览**——插件的首页（问候语下方）、页面、专辑、歌手、歌单、“查看全部”页面、电台。
  页面在会话期间会被保留：返回某个标签页或页面时立即显示，并在内容过期时于后台
  静默刷新，同时保持滚动位置（参见 docs/DESIGN.md 的 Loading 一节）。
- **搜索**——歌曲 / 专辑 / 歌手 / 歌单，支持分页和搜索建议。
- **我的**——账号与扫码登录、喜欢的歌曲（“播放全部”会先加载
  剩余分页，再播放所有喜欢的歌曲）、最近播放（音源的列表与本设备的记录合并为一项）、
  歌单、收藏的专辑、插件自带的页面、插件、设置。
- **Now playing（正在播放）**——播放队列、音质选择（标准 … 无损/Hi-Res，视插件支持而定，
  带“无损”标识）、同步歌词（逐行与逐字时间轴，点击某行即可跳转）、插件导出评论时
  可查看评论。
- **播放**——just_audio + audio_service：后台播放、通知栏和锁屏
  控制、媒体按键。每首歌开始播放时才向插件请求音频流 URL
  （它们会过期），并附带插件返回的请求头。
- 界面支持简体中文和英文（两者都使用 Flutter 自带的本地化）。

## 架构

分层为 `core` → `data` → `features`，设计系统位于 `ui`，组合根位于
`app`；插件运行在 `PluginRuntime` 平台接口之后（目前是基于 FFI 的 QuickJS-ng，也可接入
Web 运行时）。详细说明、运行时/isolate 模型、架构图，以及插件如何映射到
各项功能：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

```
lib/
  main.dart · app/ (bootstrap, services, app)
  core/      models, errors, plugin manifest, runtime interface + quickjs/ (JsEngine, PluginHost, PluginWorker)
  data/      plugins (manager, installer), library (MusicRepository, LikedStore), player, settings, navigation
  ui/        design system: theme (tokens, icons), components, layout
  features/  shell, home, browse, search, album, artist, playlist, liked, recent, stations, library,
             now_playing, lyrics, account, plugins, settings, common
  l10n/      the app's strings (zh-CN, en)
assets/js/prelude.js    JS side of the host API given to every plugin
native/                 QuickJS-ng amalgamation + mygojs.c bridge; build.sh
android/app/src/main/jniLibs/<abi>/libmygojs.so   prebuilt by native/build.sh android
```

插件的返回数据沿用桌面应用的 JSON 结构（`internal/music/music.go`）；时间单位为毫秒。

## 网页版

同一个应用也可以在浏览器中运行，由一个小型 Go relay（负责插件流量、音频流、
封面图、GitHub 安装）提供服务，并以访问令牌保护：只需一个容器。

```bash
echo "RELAY_TOKEN=$(openssl rand -hex 24)" > .env && mkdir -p data && sudo chown 65532:65532 data
docker compose up -d --build        # http://127.0.0.1:18090，前面加一层 TLS
```

插件在浏览器的 Web Worker 中运行；其数据保存在 IndexedDB 中。架构、安全
模型、环境变量和部署：[docs/WEB.md](docs/WEB.md)。截图：`screenshots/web.jpg`。

## 构建

普通机器（安装了 Flutter + Android SDK + NDK r28 的 x86_64 Linux/macOS）：

```bash
native/build.sh android          # 仅当 native/*.c 有改动时需要；预编译的 .so 文件已提交到仓库
flutter pub get
flutter build apk --release --split-per-abi
```

### 发布签名

`android/app/build.gradle.kts` 会读取 `android/key.properties`：

```
storePassword=...
keyPassword=...
keyAlias=mygo
storeFile=../keystore/release.jks
```

可用如下命令生成密钥：
`keytool -genkeypair -keystore android/keystore/release.jks -alias mygo -keyalg RSA -keysize 4096 -validity 10000`。
`android/key.properties` 和 `android/keystore/` 均已加入 gitignore。没有 `key.properties` 时，
release 构建会回退到 debug 密钥。**请备份 keystore**——对已安装
APK 的更新必须使用同一个密钥签名。

### arm64 Linux 构建机（最初几个 APK 的构建方式）

这些 APK 是在一台 aarch64 Linux 沙盒上构建的，而 Flutter/Android 并不官方支持
以它作为构建主机。各项变通方案都位于 `/workspace/work/tools` 下（先执行 `source tools/env.sh`）：

- **通过本地代理下载**：`tools/localproxy.py`（127.0.0.1:3128）负责添加上游认证；
  `env.sh` 通过 `JAVA_TOOL_OPTIONS` 让 Java/Gradle 使用它。`./build_apk.sh` 会在需要时启动它。
- **Flutter 镜像**：`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`。
- **gen_snapshot**：Flutter 没有为 Android 目标提供 linux-arm64 的 gen_snapshot，因此
  `artifacts/engine/android-*/linux-arm64/gen_snapshot` 是 shell 包装脚本，通过 qemu-user
  运行 x86_64 二进制（`tools/x86`，从 Debian 软件包中提取）。
- **aapt2**：一个 arm64 构建（2.19），通过 `tools/aapt2-wrap/aapt2` 调用，由
  `android/gradle.properties` 中的 `android.aapt2FromMavenOverride` 指定。该包装脚本会把 `--opt=value`
  改写为 `--opt value`：AGP 9.1 会调用 `aapt2 optimize --resource-path-shortening-map=…`，而这个
  aapt2 会拒绝该参数（exit 1），随后 AGP 会*悄无声息地*打包出一个缺少 `AndroidManifest.xml` 和
  `resources.arsc` 的 APK。现在如果任何 APK 缺少 manifest 或 `libmygojs.so`，`build_apk.sh` 会让构建失败。
  （在其他机器上，删除 `gradle.properties` 中的那一行即可。）
- **内存**：8 GB，无 swap。在 `android/gradle.properties` 中，Gradle 堆上限为 2 GB，Kotlin daemon 为 768 MB；
  使用原先 3 GB 堆时，daemon 会在 qemu
  gen_snapshot 运行期间被 OOM kill。在这里，一次干净的 release 构建约需 25 分钟（主要耗时在 qemu 下的 gen_snapshot）。
- **NDK 替身 28.2.13676358**：使用 r28c 的 sysroot/头文件，工具链二进制以符号链接指向系统的
  LLVM 19，使 AGP 认为已安装 NDK。Gradle 构建中不会进行 NDK 编译；
  `libmygojs.so` 由 `native/build.sh` 使用系统 clang 针对 NDK sysroot 构建。
- **系统 LLVM 19**（来自 Debian 的 `clang-19`、`lld-19`、`llvm-19`），供 `native/build.sh` 使用；NDK 替身的
  工具链链接指向 `/usr/lib/llvm-19/bin`。它们位于 workspace 之外，因此全新的沙盒需要
  重新安装（通过代理执行 `apt-get install clang-19 lld-19 llvm-19`）。
- **path_provider_android 固定为 2.2.23**（`dependency_overrides`）：2.3.x 会引入 `package:jni`，
  它会在构建时用 NDK 工具链编译 C 代码。

在普通的 x86_64 主机上，除了版本固定（无害）和签名之外，以上都不需要。

## 测试

```bash
flutter test test/unit                      # 无需网络：controllers、navigation、lyrics、design tokens
native/build.sh host
MYGOJS_LIB=native/build/host/libmygojs.so flutter test test/kugou_live_test.dart
MYGOJS_LIB=native/build/host/libmygojs.so flutter test test/stack_stress_test.dart   # 4 个插件 isolate，480 次调用
```

在代理环境下，用 `MYGO_HTTP_PROXY=host:port` 为插件流量指定一个无需认证的代理
（这里是本地转发器 `127.0.0.1:3128`），并用 `NO_PROXY=127.0.0.1,localhost` 让测试运行器自身的
localhost WebSocket 不走代理。

live 测试需要网络、一份 kugou-lite 的检出（`--dart-define=KUGOU_DIR=...`，默认
`/workspace/work/mygo-music-kugou-lite`），以及位于
`test/fixtures/kugou-data/kugou-lite/storage.json` 的已登录 fixture（已加入 gitignore——其中包含登录信息）。它会检查
导出项、账号、首页、最近播放、搜索（所有类型）、喜欢、首字节为
`fLaC` 的无损音频流、标准音质音频流、歌词、评论，以及未导出的方法会以 `unsupported` 失败。
结果写入 `build/kugou_live_results.json`。

### 截图（无需设备）

`test/screenshots_test.dart` 会渲染真实的应用（`MyGoApp`，zh-CN），使用在应用自身运行时中运行的
已登录 kugou-lite 插件提供的实时数据，并像用户一样逐步操作：

- 手机，1080x2340 px（360x780 dp @3），深色和浅色：首页、搜索 周杰伦 晴天、一张专辑（从
  搜索结果的歌曲菜单进入）、我喜欢、迷你播放器、Now Playing、歌词（播放位置固定在歌曲中间，使
  某一行处于高亮状态）、插件（在一次真实的更新检查之后）；
- 平板横屏，2560x1600 px（1280x800 dp @2）：带侧边栏的首页、一张专辑、带歌词的 Now Playing。

状态栏（24 dp）和手势条（16 / 20 dp）是模拟的：视图会像 edge-to-edge 窗口那样把它们作为
padding 获得，测试再按应用最近一次请求的图标亮度（`SystemChrome.latestStyle`）在画面上
绘制一个假的状态栏和手势条；它们下方显示的是应用自己的内容。PNG 输出到 `screenshots/`（拼图
`screenshots/phone.jpg`、`screenshots/tablet.jpg`），包含每张截图叠加样式的报告输出到
`build/screenshot_report.json`。

```bash
MYGOJS_LIB=native/build/host/libmygojs.so MYGO_HTTP_PROXY=127.0.0.1:3128 NO_PROXY=localhost,127.0.0.1 \
  flutter test test/screenshots_test.dart
```

字体来自 `--dart-define=CJK_FONT_DIR=...`（默认 `/workspace/work/tools/fonts`）：Noto Sans SC
Regular/Medium/Bold，优先使用 `emoji-merged/` 中的副本，这些副本由
`tools/fonts/add_emoji.py` 加入了单色 Noto Emoji 字形（测试引擎没有逐字形的字体回退，否则 emoji 会显示成豆腐块）。
封面图会用 curl 一次性下载到 `build/img-cache/`。不会实际播放：“正在播放”状态
是直接设置在播放器的 notifier 上的，其时钟通过 `Player.debugSetClock` 固定。

## 已知不足 / 尚未验证

仅在无界面环境下验证过（插件运行时 + kugou-lite 实时调用、手机/平板尺寸的界面、
release 构建与签名）。尚未在真机上验证：

- 实际音频播放（包括 ExoPlayer 对 FLAC / Hi-Res 的解码），
- 后台播放、通知栏和锁屏控制，
- 界面中的扫码登录流程，
- 通过文件选择器从 zip 安装插件，
- `mygo-music://install-plugin` 深层链接，
- 触控手感：迷你播放器拖动、下拉关闭、歌词滚动以及真实硬件上的帧率，
- 真机上的 edge-to-edge 效果（状态栏/导航栏颜色、三键导航、刘海/挖孔）以及
  Android 返回手势，
- iOS：完全没有构建（需要 Mac；`libmygojs` 需静态链接 / 以 xcframework 形式链接）。

其他不足：没有下载 / 离线缓存；不支持仅限桌面端的插件导出（例如 `remoteState`
返回 `unsupported`）。
