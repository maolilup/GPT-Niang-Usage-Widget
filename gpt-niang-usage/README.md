# GPT娘额度挂件

这是 Windows 插件与桌面挂件目录，其中的 Node.js 运行时也由 Mac 原生应用复用。安装、使用、更新和隐私说明请看[项目主页](../README.md)。

- `Install.ps1`：检查依赖并安装；`-CheckOnly` 只检查，不修改系统。
- `widget.ps1` / `widget.xaml`：Windows WPF 挂件与界面。
- `runtime/mcp.mjs`：Windows 插件的只读额度查询工具。
- `runtime/plan.mjs` / `runtime/detect-plan.mjs`：自动识别套餐并检测实际额度窗口；根目录「检测套餐.cmd」可直接运行。
- `runtime/watch.mjs` / `runtime/worker-state.mjs`：双平台共享的额度刷新与单实例 worker。
- `runtime/thread-speed.mjs`：Mac 聊天速度面板的本地计数 helper，不代表实时模型速度。
- `runtime/supervisor.ps1`：识别主窗口并恢复角色；轻度内存超限时自动重新启动 GUI，连续故障或心跳超时则停用。
- `runtime/host-layer.ps1`：独立窗口的遮挡顺序；主窗口或挂件设置处于前台时临时置顶，切到其他应用后降级，避免跨进程 owner 绑定。
- `runtime/expressions.ps1` / `assets/expressions/`：23 种表情与手势的选择、图片缓存和透明区域命中检测。
- `runtime/ui-settings.ps1`：表情手选、定时随机对话开关和语录编辑等设置。
- `assets/quotes.json` / `assets/quote-layouts.json`：254 句日常语录、逐句表情配对及气泡排版。
- `runtime/headpat.ps1` / `assets/headpat-quotes.json`：不按键来回轻抚头顶的手势检测、冷却和 12 句专属回应。
- `runtime/low-quota.ps1` / `assets/low-quota-quotes.json`：9 句低额度专属对话，按偏低、快用完和已用完分级触发。
- `tests/`：额度解析、刷新队列、Windows 安装与生命周期、表情交互、摸头、低额度对话、定时对话、自适应尺寸，以及本地线程计数测试。

在有可见前台窗口的交互桌面上，`tests\run-windows-tests.ps1 -InteractiveDesktop` 会额外执行前后台层级检查；无桌面的 CI 默认跳过该项。

`tests\resource-recovery.integration.test.ps1` 可单独运行，用独立透明测试窗口与故障注入验证自动恢复两次、第三次停用的完整守护循环。

`installation.json` 在本机安装时生成，不包含在仓库中。Windows 默认个人数据位于 `%LOCALAPPDATA%\GPTNiangUsage\state`，停用后保留。Mac 数据位于 `~/Library/Application Support/GPTNiangUsage`；下载与安装说明见 [Mac README](../macos/README.md)。

Windows 点击角色按「额度 → 对话 → 额度」循环，收起后的第一次点击先显示额度。额度气泡显示剩余百分比、进度条和重置时间：展开动画结束后，前 2 秒显示距离重置多久，后 3 秒显示固定日期和重置时刻，然后自动收起；刷新时重新计时。重置时刻、今日／明日及更新时间均按当前 Windows 机器的本地时间显示；悬停气泡可查看完整日期、时区偏移与倒计时。缺少重置时间时会明确提示，过期的额度等待刷新。

鼠标不按键在头顶轻轻来回一次即可摸头，显示独立回应、配套表情和轻微回弹，冷却 4 秒；普通点击循环与按住拖动保持原有行为。

自动表情按当前台词配对，常态会缓慢切换；有效剩余额度不足 20% 时单独显示担忧表情，手动对话仍按台词配表情。右键可固定表情或关闭默认开启的「定时随机对话」：Codex 前台静置时每隔随机 45～90 秒显示一句约 5 秒的本地语录，低额度使用独立台词：低于 20%、不超过 5% 和 0% 各有一组，首次触发后持续偏低最多每 3 分钟提醒一次。隐藏或操作设置时暂停，关闭该开关也关闭自动低额度台词。

大小设置作为上限，挂件连同气泡适应主窗口宽度的 25%、高度的 40%。主窗口小于 720×520 逻辑像素时隐藏，恢复到至少 760×560 后显示。具体触发条件、安装本 fork 和升级语录说明见[项目主页](../README.md#windows-表情与对话)。这些表情、摸头、定时对话及自适应功能仅在 Windows 实现；Mac 从本分支构建时复用共享台词文本。

交互实现范围见[DSH功能对照](DSH功能对照.md)，图片生成来源见[素材说明](assets/生成说明.md)。

台词编写按 [角色与台词](assets/角色与台词.md) 中的人设与句式规范执行。日常、摸头和低额度台词已统一复查。

Windows [台词配置](台词配置.md)：`runtime/dialogue-config.ps1` 负责 `dialogue.json` 的校验、自动重载、配套表情和旧语录迁移。右键可打开配置或使用内置 JSON 编辑器；示例见 `assets/dialogue.example.json`。
