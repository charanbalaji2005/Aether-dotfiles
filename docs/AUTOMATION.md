# Automation

Settings → Automation, or `aether automation list|validate|import|export`.

A rule is **When** *trigger* — **If** *conditions* (optional, up to 4, all must hold) — **Then**
*1–5 actions in order* (later actions are skipped if one fails).

| Triggers | Conditions | Actions |
|---|---|---|
| startup · charger connected/disconnected · battery below N % · Bluetooth device (dis)connects · app opened/closed · workspace active · monitor (dis)connected · time HH:MM · network changed · focus session start/end · profile applied | on battery · on AC · between times (wraps midnight) · battery above/below | quality · motion profile · theme mode · palette · desktop profile · window layout · power profile · wallpaper / next · launch app (by desktop id) · switch workspace · volume · Do Not Disturb · dock · notification |

```json
{ "id": "dock-at-desk", "name": "Desk mode", "enabled": true,
  "trigger": { "type": "monitor-connected" },
  "conditions": [ { "type": "on-ac" } ],
  "actions": [ { "type": "apply-layout", "value": "developer" }, { "type": "set-quality", "value": "ultra" } ] }
```

Safety: there is **no "run command" action**; launching takes a desktop id, never a command
line. A rule can't fire twice within 3 s; actions run with re-entry suppressed (a rule can't
trigger itself); more than 20 actions in a minute switches automation off and tells you why.
Imported rules arrive **disabled**. Rules don't run in safe mode. The 0.3 single-`action` form is
still accepted.
