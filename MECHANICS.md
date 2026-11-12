# 行为证据与独立实现

已调用 native_functions_list、native_strings_find 和四次 native_function_pseudocode。Ghidra 初始化失败，工具返回后备寄存器级伪代码；未将伪代码复制进实现。额外读取 llvm-objdump 原始 arm64 汇编核实常量。

## 已恢复规则
- 初始化函数 0x10009519c，证据 ev_56a2eb6c001d388bcc0936469e6522509953b302bc5aa7a2ad3e9d04a1214bba：显示延迟0.2秒，IEEE754 0x3fc999999999999a（指令0x1000952ac–0x1000952b8）；自动隐藏0（从不）；再次激活前台App则隐藏=true；菜单栏图标=true；大小0.7（0x100095374），透明度0.75（0x1000953ac）；边框1；Option激活修饰位0x80000（0x10009540c）；双击暂停默认false；Finder优先true；当前屏幕true。
- 延迟读取函数0x100004520使用time-delay-before-activation设置，证据ev_fdaeca7771c530461e241eb14b401eac4d5cf44f321bff2a60fa14e22dde8d02。
- 快捷键提供器0x10001eba0，证据ev_38b6193c3c4bd3d5e9f068ae3e72b247d7ff3014045290f4829462bf969ff036：左手字符集合12345QWERTASDFGZXCVB、字母ABCDEFGHIJKLMNOPQRSTUVWXYZ、数字1234567890；有字符模式和键盘模式。
- 设置窗口函数0x1000384c0读取screen-bar-position、switcher-filtered-apps、显示延迟、自动隐藏和激活键，证据ev_463ba76bdd0e154d432c8c28a548d617403333db42bfe04390cf2bcd51e806d3。
- 资源本地化及字符串引用说明Dock模式跟随Dock，切换器模式跟随运行App，自定义模式管理App和快捷键；静默名单可抑制显示且可禁用快捷键。字符串证据ev_d9dd8b2109fbb5a3576fd1c4f057c61f7b2b6e7257142a4ae8e13dcbde2b6e65。

## 估计与边界
- estimated：设置窗口1000×740，侧栏布局，玻璃圆角26，按键分配顺序，右手字符集合67890YUIOPHJKLNM，双击间隔0.3秒，水平默认位置0.5、垂直0.5。后备分析不足以完整恢复布局和排序算法。UI按macOS原生设置风格独立重建。
- 使用AppKit工作区激活应用、Dock偏好读取、CGEvent tap全局拦截；辅助功能授权由系统管理。缺少授权时只可验证本窗口快捷键，不能声称全局已实测。
- 本地配置可导入导出；iCloud需独立签名及容器，尚未接入。原购买、授权、更新服务和品牌素材不复制。
- 原程序运行截图被自动审批策略拒绝，没有以缺少截图证明视觉一致。
- 截图参数不激活窗口，120次60Hz定时刷新后保存原生视图PNG并退出。

## 2026-11-11 本轮重新反编译与修正

本轮重新通过 `core_target_open` 打开上述原始主程序。Deep 模式已开启，但 Ghidra 启动失败；以下逐个调用 `native_function_pseudocode`，等待每个完整返回并阅读后才继续。实际返回为内置反编译器的寄存器级伪 C，不能冒充 Ghidra 高级反编译。完整结果（包含限制、地址、证据 ID）保存在 `decompilation-evidence.json`，不是仅沿用旧文档。

### 字符串 → 引用 → 函数

`native_strings_find` 搜索设置、名称和消息，证据 `ev_dfb05c264b45c20c6043a0dec9fcf5bfd024574b3261547504d76c3c0a061362`。搜索共214项，本轮读取前200项，不宣称完整字符串覆盖。实际沿返回引用读取以下函数：

- `time-delay-before-activation`（0x1001c7520）→ 0x10009519c、0x100004520；`fadeInHudWithDelay`（0x1001f3680）→ 0x10003930c。
- `12345QWERTASDFGZXCVB`（0x1001c8270）→ 0x10001eba0，再沿其直接调用读取 0x10001eeb4。
- `overlay-size-scale`（0x1001c7670）→ 0x100008210、0x1000089a8；`updateItemSize: width: %f, count: %ld`（0x1001f3240）→ 0x10000ba70。
- `It seems you double tapped, so stop showing Switcher!`（0x1001f3640）及启停提示 → 0x10003b0b8。
- `hide-app-for-second-time`（0x1001c9630）、`Target app is active, now hide it`（0x1001c9710）→ 0x10004f668。
- `fadeOutHudWithDelay`（0x1001f3590）→ 0x10003a500。

### 已核实并用于当前构建

- 0x10009519c 默认延迟0.2秒、自动隐藏0、大小0.7、透明度0.75；继续保持现有已匹配默认值，移入 `Sources/Mechanics.swift`。汇编证据 `ev_fc587d36dfa057c59f6e181a6a128fa4c466a9f8042fb351dbbdd6ea39a8f2b5`，伪代码证据 `ev_56a2eb6c001d388bcc0936469e6522509953b302bc5aa7a2ad3e9d04a1214bba`。
- 0x10003930c 在0x100039350–0x100039358将显示延迟与 **2.5严格比较相等**；相等直接返回、不安排显示计时器。其余值传给单次计时器，并加入 Common run-loop modes。当前构建新增此“从不显示”值，显示延迟滑块扩展到2.5；手动预览仍可显示。伪代码 `ev_e55b85034838535c7feb9d20950304e687a70884c8dffc0b1b7f66d1c0b8027f`，汇编 `ev_ff98bac71cfa157d2005e98894451ec4dfee5757a598230bef4a8459b6682f74`。
- 0x10003b0b8：首次按下创建 **0.3秒单次窗口**（0x10003b374–0x10003b390，IEEE754 0x3fd3333333333333）；窗口尚在时再次按下则取消并清空窗口，再翻转启停状态。因此三连按只触发一次翻转，第三次开始下一对。原实现用上次按下时间连续比较，会使三连按翻转两次；现改为成对消费，采用系统单调时钟。第二次触发后立即取消显示，不重新安排延迟显示。伪代码 `ev_855b0e7de5bddd65571d2fe43c2581c74248313b25acca928068affacd812e02`，汇编 `ev_1c854b4b10eb54563abb551a43dce8990b4bd3816d3d9dcb333e271ddfd3a270`。0.3不再是估计值。计时器恰好到期的事件顺序仍取决于原程序运行循环。
- 0x10001eba0 构造左手字符集合、字母集合、数字集合；0x10001eeb4遍历预置键码数组，按字符模式与键盘模式过滤、保留数组顺序。证据 `ev_38b6193c3c4bd3d5e9f068ae3e72b247d7ff3014045290f4829462bf969ff036`、`ev_795637f76d1e6b8d30dd70480a0b5009a2259d1a88fbc7deffcb67e6dfe4e0dd`。现有字符集合相符；预置数组顺序尚未恢复，现有按键顺序仍为估计，不能仅用集合字符串证明顺序。
- 0x10004f668读取再次隐藏设置；目标正在运行且已激活时走隐藏分支，否则继续打开/激活。当前构建保留此规则。原程序还存在 Firefox Developer Edition、Emacs 等兼容分支，当前未复刻。证据 `ev_3b3dd26ac4e3f77db8ccd605ec81c55bd29b53382fa162a725460e4d24fca5e8`。

### 已恢复但不能直接套入当前布局的公式

0x10000ba70（0x10000bb7c–0x10000bbf0）：令 N 为条目数，M 为0x10023a988对应模式字节，W为返回屏幕矩形宽度。额外槽 E 在 N=0 或 M=2 时为1，否则0。单元尺寸 `D = min(136, (W - 40) / (N + E))`；无屏幕则 D=0。0x10000be08–0x10000be1c把 `D > 0 ? D : 128` 同时作为宽、高传递。伪代码 `ev_539c505bd35fd475731ed24a6572e5187550485a0aaec8c2ca17258aacdc198a`，汇编 `ev_3056b51f24120d6199ac43c06c5d14eb462b81577a97d0696c7e4b1aaaa1eb82`。**M枚举意义、后续缩放与最终窗口尺寸未恢复，因此未将此局部公式冒充完整布局公式写入UI。** 当前64+size×28及固定154高仍为独立布局估计。

0x10003a500取消旧隐藏计时器，再创建0.1秒单次计时器（0x10003a65c–0x10003a67c，IEEE754 0x3fb999999999999a），加入 Common modes。证据 `ev_663fed2956e2fc138e2bab29d9474fe348404c78fbcc0f06e0f9e4a4953e54e2`、`ev_3ea9a2961c7a3a55d303e256aacff6f3b3e7f33abf19ae807cd6ed4057cfe9ec`。调用场景与淡出完成路径未全部恢复，当前立即关闭逻辑未贸然统一添加0.1秒。

0x10009519c 的 **overlay-center-x真实默认值为1.6**（0x100095328–0x10009533c，0x3ff999999999999a），y为0.5；此前文档仅将x=0.5标为估计。原坐标换算尚未恢复，不能把1.6直接当作当前0…1比例。当前居中位置仍为估计。

### 覆盖边界与验证

本轮读取11个函数（默认、快捷键构造/过滤、尺寸、双击、显示延迟、设置读取、缩放观察/更新、应用激活、延迟隐藏），所有调用均已返回。没有恢复整个应用：Dock/运行应用排序、完整静默状态机、配置/iCloud、完整外观布局仍不能声称逐函数对齐。旧文档中的四函数描述仅代表上一轮，不是本轮覆盖。

验证：`checks/mechanics-check.swift`直接编译生产 `Mechanics.swift`，覆盖双击、三连按、超时及恢复常量；随后运行 `build.sh` 重新生成并签名 release 应用。完整构建输出见 `build.log`。全局辅助功能、原窗口像素对照仍未实测。
