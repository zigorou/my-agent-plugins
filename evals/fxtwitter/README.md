# fxtwitter: skill の発火評価

`fxtwitter-read` / `fxtwitter-show` / `fxtwitter-thread` の description がどれだけ正しく発火するかを測るクエリ集と、その実測値。
description を変えたら同じクエリ集で測り直し、下の基準値と比べる。

## クエリ集

| ファイル | 対象 | 内訳 |
|---|---|---|
| `trigger-read.json` | `fxtwitter-read` | 発火すべき 10 / すべきでない 10 |
| `trigger-show.json` | `fxtwitter-show` | 発火すべき 10 / すべきでない 10 |
| `trigger-thread.json` | `fxtwitter-thread` | 発火すべき 10 / すべきでない 10 |

`should_trigger` は「**その skill 自身が**選ばれるべきか」を表す。兄弟 skill 向けの依頼 (read の集にある「スレッドを全部まとめて」など) は `false` である。使い分けを測るためで、`true` にすると最適化が 3 skill を「X の URL なら何でも拾う」方向へ寄せ、使い分けが消える。

## 測り方

skill-creator (claude-plugins-official) の `scripts.run_loop` で測る。ただし次の 2 点を整えてから走らせる。

- **兄弟 skill を競わせる**: `run_eval.py` は対象 skill だけを `.claude/commands/` に置いて測る。そのままでは read / show / thread の取り違えが測れないので、評価用ディレクトリの `.claude/commands/` に兄弟 2 つを現行 description で置く
- **並列実行の不具合を避ける**: 上流の `run_eval.py` は、並列 worker が 1 つの `.claude/commands/` を共有する。各 `claude -p` に対象 skill の一時コピーが worker 数ぶん見え、他 worker のコピーが選ばれると未発火と数えるため、発火率が大きく低く出る。呼び出しごとに一時ディレクトリを作り、兄弟 skill と対象 skill をそこに置いて `claude -p` を走らせるよう手元で直して測った
- 評価用ディレクトリは repo の外に置く。`run_eval.py` は cwd から辿って最初の `.claude/` に書き込むため、repo 内で走らせると main checkout の `.claude/` を汚す
- plugin の UserPromptSubmit hook は効かない状態で測っている。値は「description だけでの発火率」である

## 基準値 (2026-10-30)

設定: `--runs-per-query 2 --max-iterations 3 --holdout 0.4` (train 12 / test 8)、モデル `claude-opus-5-5`、description は PR #3 時点のもの。

| skill | train (クエリ) | test (クエリ) | 備考 |
|---|---|---|---|
| `fxtwitter-read` | 12/12 | 8/8 | 精度・再現率とも 100% |
| `fxtwitter-show` | 12/12 | 8/8 | 精度・再現率とも 100% |
| `fxtwitter-thread` | 12/12 | 8/8 | ログの試行単位では 23/24 (1 回は記録に残らず)。クエリ単位の誤りは無し |

3 skill とも初回評価で全クエリに合格し、改善ループに入らなかった (`exit_reason: all_passed`)。description は変更していない。
