# my-agent-plugins

## 目的

個人用 CC プラグインの marketplace

このリポジトリは Claude Code プラグイン集である。`.claude-plugin/marketplace.json` と `plugins/` フラット配置をとり、各プラグインは自己完結し orientation スキルを持つ。

## レイアウト規約

- マーケットプレイスカタログは `.claude-plugin/marketplace.json`。plugin を追加・改名したら、カタログも同じ変更で更新する (`source: "./plugins/<name>"`)
- 配布物は `plugins/<name>/` にフラット配置する。マニフェストは `plugins/<name>/.claude-plugin/plugin.json`
- plugin の中身を変えたら `plugin.json` の `version` を bump する。`version` は cache key で、据え置くと更新が届かない
- 機能は skills で構成し、commands は作らない
- 各 plugin にオリエンテーション skill を 1 つ置く。配置は `skills/<plugin-name>/SKILL.md`
- 各 plugin は自己完結に保つ。インストール時に cache へコピーされるため、`../` で repo 内の他ファイルを参照できない
- commit 前に `claude plugin validate .` (カタログ) と `claude plugin validate plugins/<name>` (各 plugin) を通す

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
