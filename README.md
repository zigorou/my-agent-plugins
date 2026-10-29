# my-agent-plugins

個人用 CC プラグインの marketplace

## 使い方

marketplace として登録し、収録 plugin をインストールする。

```
/plugin marketplace add ~/repos/my-agent-plugins
/plugin install <plugin-name>@my-agent-plugins
```

## plugin の追加

1. `plugins/<name>/` に plugin を置く (`.claude-plugin/plugin.json` と、オリエンテーション skill `skills/<name>/SKILL.md`)
2. `.claude-plugin/marketplace.json` の `plugins` に `{"name": "<name>", "source": "./plugins/<name>", "description": "..."}` を追加する
3. `claude plugin validate .` と `claude plugin validate plugins/<name>` を通す
