# Widget expressions implementation plan

> **For agentic workers:** Use subagent-driven-development for the code task, with spec and quality review. Keep all changes local.

**Goal:** Add ten generated expression/gesture sprites and automatic/manual selection to the installed Windows widget.

**Architecture:** A focused runtime/expressions.ps1 owns bitmap/alpha caches, expression selection and transition deadlines. widget.ps1 emits interaction/refresh events and updates selection during ticks; ui-settings.ps1 offers a persisted selector. Generated PNGs keep the existing normalized framing.

**Tech stack:** Windows PowerShell5.1 STA, WPF, PNG alpha, existing Node runtime unchanged.

## Task1: Generate and inspect assets (controller)
- [x] Generate six face edits with built-in imagegen using original sprite as target; inspect inline results.
- [ ] Generate wave/cheer/pout/comfort variants allowing only face and arm edits; retain transparent square framing.
- [ ] Copy every PNG to gpt-niang-usage/assets/expressions and outputs/widget-expressions; preserve original PNG.
- [ ] Save the exact prompt set and inspect dimensions/alpha with read-only Pillow; no scripted image editing.

## Task2: Runtime and integration (implementer)
- [ ] Write tests/expression.test.ps1 first. Assert manual selection survives auto events; pressed beats refresh/idle; transient expires; a fresh 10% window shows worried,0% shows pout; null/failed/stale/expired windows do not; refresh expires after8000ms; missing asset falls back; cache changes current bitmap/alpha and palette masks together.
- [ ] Run powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tests/expression.test.ps1 and confirm the missing feature fails.
- [ ] Create runtime/expressions.ps1 with the registry, lazy cache and deterministic time-based state; integrate widget.ps1 click/press/quote/refresh/tick hooks and persisted expressionMode.
- [ ] Add 表情与动作 submenu in runtime/ui-settings.ps1 with auto and eleven named sprites; synchronize checks and Save-Settings.
- [ ] Include runtime/expressions.ps1 in Install.ps1 validation and entrypoint.test.ps1 fixture. Wire expression.test.ps1 into run-windows-tests.ps1. Keep optional PNG loss recoverable with neutral fallback.
- [ ] Run expression test, full Windows suite and npm test. For sandbox EPERM temp rename, run isolated tests escalated as previously verified; prepare fake codex.exe from node.exe in work/widget-test-bin, then prefix PATH only for the child tests.
- [ ] Self-review actual-source hooks, alpha coordinates, color masks, deadline transitions and source compatibility. Commit only the code/tests touched; assets/docs are controller-owned and must not be included by broad git add.

## Task3: Review and local installation (controller)
- [ ] Read-only spec review of code vs approved design, then separate code-quality review. Implementer repairs actionable findings and re-runs relevant tests.
- [ ] Independently run full Windows tests including all generated PNGs; shared Node tests only once after final code, then packaging if installer dependencies changed.
- [ ] Back up widget.ps1, ui-settings.ps1, Install.ps1 and any replaced local modules under outputs/widget-expressions/backup. Copy changed module and expression assets to existing installation only after verified stopped.
- [ ] Use existing per-user supervisor-task helper to stop/start exact installation. If stop times out, verify exact supervisor command path and process creation time before stopping that own process.
- [ ] Validate live HWND remains stable and presence reports expression changes, manual persistence, alpha response and restored auto mode; write installation/verification record and local gallery.

