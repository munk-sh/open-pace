# Domain: ios-audio-verification

**已下线（2026-11-10，清理写项 B）**：agent 级真机验收已停止——脚本、真机 UI 用例、证据目录均已移除，不再恢复。真机验收改由人手按 `docs/device-manual-acceptance.md` 在交付后执行；本域不承载任何 agent 侧门禁或断言。

## 现状

- 本域的技术结论已无代码承载，仅作历史记录保留；「他路音频在播 → 播报 duck → 恢复」不再有机器证据，只保留手册里的人耳判定两条。
- 音频会话的结构性断言（`categoryOptions`、`setActive`）仍由 `ios-audio-session` 域在单测里覆盖，与本域无关。

## 约束

- 不得据本域恢复脚本/用例，也不得据其新增真机门腿。
- 真机结论一律 `pending: 待人现场`；未做即 pending，禁写「真机已验证」。
