# my-agent-plugins

## 目的

個人用 CC プラグインの marketplace

このリポジトリは Claude Code プラグイン集である。`.claude-plugin/marketplace.json` と `plugins/` フラット配置をとり、各プラグインは自己完結しオリエンテーション skill を持つ。

## レイアウト規約

- マーケットプレイスカタログは `.claude-plugin/marketplace.json`。plugin を追加・改名・削除したら、カタログも同じ変更で更新する (`source: "./plugins/<name>"`)。source に相対パス以外 (github / url など外部 source) は使わない
- plugin を改名・削除したら、カタログ top-level の `renames` に旧名 → 新名 (削除なら `null`) を追記する。append-only で消さない。書かないとインストール済みの環境で plugin が見つからなくなる
- 配布物は `plugins/<name>/` にフラット配置する。マニフェストは `plugins/<name>/.claude-plugin/plugin.json`
- `<name>` は kebab-case とし、`claude-` / `anthropic-` / `anthropics-` / `cc-plugin-` で始めない。カタログ entry の `name` と `plugin.json` の `name` を一致させる
- `version` は `plugin.json` に明示し、plugin の中身を変えたら必ず bump する。カタログ entry には `version` を書かない。`version` は cache key で、据え置くと GitHub 経由の購読者に更新が届かない。この規約は `.githooks/check-plugins.sh` が commit 前に検査する (判定範囲は merge-base からのブランチ全体)
- 機能は skills で構成し、commands は作らない
- 各 plugin にオリエンテーション skill を 1 つ置く。配置は `skills/<plugin-name>/SKILL.md`
- 各 plugin は自己完結に保つ。GitHub 経由のインストールでは plugin ディレクトリだけが cache へコピーされるため、`../` で repo 内の他ファイルを参照しない。ローカルパス登録 (開発モード) では in-place で読まれて動いてしまうので、手元で動いたことを根拠にしない
- `claude plugin validate .` (カタログ) と `claude plugin validate plugins/<name>` (各 plugin) は `.githooks/check-plugins.sh` が commit 前に実行する。基準は既定モード (警告は許容、エラーで停止) で、`--strict` は求めない。validate は index を一時ディレクトリへ書き出して実行し、commit される内容で判定する。validate は source の実在を見ないため、カタログと `plugins/` の整合 (source の実在 / name の一致と kebab-case / 掲載漏れ / entry の `version` / 消えた plugin の `renames`) も同じ hook が検査する
- hook は `core.hooksPath` で有効になる。clone 直後は `git config core.hooksPath .githooks` を実行する。未設定だと全検査が無言で抜ける
- hook を変えたら `bats tests/` を通す

## 設計原則

<!-- springhead default。このリポジトリの事情に合わせて上書き・追記してよい。 -->
以下はリポジトリ運用の default 原則である。各リポジトリの事情に合わせて上書き・追記してよい。

1. **推論と決定論の適材適所**: 判断・自然言語理解・非定型の探索は推論 (モデル) に任せ、入力から出力が規則で一意に決まる処理は決定論的手段 (hook / script / 設定) に置く。判定基準は「規則・表・条件分岐で書けるか」
2. **モデルを理由付きで切り替える**: 単純作業は安いモデル、微妙な判断は能力の高いモデルへ。切り替えた理由を残す
3. **トークン消費を監視する**: 不要な再読・冗長な出力・巨大な文脈の持ち回りを見つけたら手段を見直す
4. **orchestration を階層化する**: 制御フローは決定論側 (script) に置き、判断を要するステップだけをエージェントに任せる
5. **context は有限資源**: 長いセッションでは圧縮を促し、圧縮前に作業状態を保存し、圧縮後は要約でなく原典を正とする

<!-- 根拠 doc への差し替えポイント: このリポジトリにモデル選択やコスト設計の一次資料があれば、ここに参照を書く。 -->

用語:

- **能力の床**: あるタスクに最低限必要なモデル能力の下限。これを下回ると失敗するため、意図的に下限を敷くこと
- **コスト隔離**: 安いモデルで足りる作業を高いモデルから切り離し、コストを局所化すること
