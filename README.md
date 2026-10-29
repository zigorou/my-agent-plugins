# my-agent-plugins

個人用 CC プラグインの marketplace

## 使い方

marketplace として登録し、収録 plugin をインストールする。

```
/plugin marketplace add zigorou/my-agent-plugins
/plugin install <plugin-name>@my-agent-plugins
```

GitHub 経由で登録した marketplace は auto-update が既定で off である。
push した更新を取り込むには `/plugin marketplace update my-agent-plugins` を実行するか、`/plugin` の Marketplaces から auto-update を有効にする。
反映にはセッションの再起動 (または `/reload-plugins`) も要る。

### 開発モード

この repo を開発するマシンでは、ローカルパスで登録すると作業ツリーがそのまま読まれ、変更が bump なしで次のセッションから反映される。

```
/plugin marketplace add ~/repos/my-agent-plugins
```

- 同名の marketplace は 1 つしか登録できない。GitHub 経由とローカルパスはどちらか一方にする
- main checkout で checkout しているブランチや未 commit の変更が、そのまま全プロジェクトに配信される。main checkout は default branch に保ち、作業は worktree で行う

## plugin の追加

1. `plugins/<name>/` に plugin を置く。`.claude-plugin/plugin.json` には `name` / `version` (例: `0.1.0`) / `description` / `author` を書き、オリエンテーション skill を `skills/<name>/SKILL.md` に置く
2. `.claude-plugin/marketplace.json` の `plugins` に `{"name": "<name>", "source": "./plugins/<name>", "description": "..."}` を追加する (`version` は書かない)
3. commit すると `.githooks/check-plugins.sh` が version と `claude plugin validate` を検査する
