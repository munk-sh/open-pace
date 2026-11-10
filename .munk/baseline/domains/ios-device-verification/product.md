# Domain: ios-device-verification

**已下线（2026-11-10，清理写项 B）**：agent 级真机验收已停止——脚本、真机 UI 用例、证据目录均已移除，不再恢复。真机验收改由人手按 `docs/device-manual-acceptance.md` 在交付后执行；本域不承载任何 agent 侧门禁或断言。

## 现状

- 本域的技术结论已无代码承载，仅作历史记录保留，删去的用例与脚本不参与任何门。
- 真机能力（定位权限、锁屏后台、音频实听）不在 CI、不在 `scripts/**`、不在 `.munk/code-gates.json`。

## 约束

- 不得据本域恢复脚本/用例，也不得据其新增真机门腿。
- 真机结论一律 `pending: 待人现场`；未做即 pending，禁写「真机已验证」。
