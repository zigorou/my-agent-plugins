#!/usr/bin/env bats
# .githooks/check-plugins.sh のシナリオテスト。使い捨て repo の中で hook を直接呼ぶ。
# 実行: bats tests/

HOOK="$BATS_TEST_DIRNAME/../.githooks/check-plugins.sh"

setup() {
  cd "$BATS_TEST_TMPDIR"
  git init -q -b trunk repo
  cd repo
  git config user.email t@example.com
  git config user.name t
  mkdir -p .claude-plugin plugins
  printf '{"name":"mp","owner":{"name":"t"},"plugins":[]}\n' > .claude-plugin/marketplace.json
  touch plugins/.gitkeep
}

# add_plugin <name> [version]
add_plugin() {
  mkdir -p "plugins/$1/.claude-plugin" "plugins/$1/skills/$1"
  jq -n --arg n "$1" --arg v "${2:-}" \
    '{name: $n, description: "d", author: {name: "t"}} + (if $v == "" then {} else {version: $v} end)' \
    > "plugins/$1/.claude-plugin/plugin.json"
  printf -- '---\nname: %s\ndescription: Orientation for %s. Use when starting.\n---\n\n# %s\n' "$1" "$1" "$1" \
    > "plugins/$1/skills/$1/SKILL.md"
  edit_catalog --arg n "$1" '.plugins += [{name: $n, source: ("./plugins/" + $n), description: "d"}]'
}

# edit_catalog [jq args...] <filter>
edit_catalog() {
  jq "$@" .claude-plugin/marketplace.json > m.tmp && mv m.tmp .claude-plugin/marketplace.json
}

set_version() {
  jq --arg v "$2" '.version = $v' "plugins/$1/.claude-plugin/plugin.json" > p.tmp &&
    mv p.tmp "plugins/$1/.claude-plugin/plugin.json"
}

# foo 0.1.0 を載せた commit を origin/main として公開し、feature ブランチへ移る。
publish_base_with_foo() {
  add_plugin foo 0.1.0
  git add -A && git commit -q --no-verify -m base
  git update-ref refs/remotes/origin/main HEAD
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  git checkout -q -b feature
}

stage_and_run() {
  git add -A
  run "$HOOK"
}

@test "plugin が無ければ通る" {
  stage_and_run
  [ "$status" -eq 0 ]
}

@test "version の無い plugin は止める" {
  publish_base_with_foo
  add_plugin bar
  stage_and_run
  [ "$status" -eq 1 ]
  [[ $output == *"plugins/bar/.claude-plugin/plugin.json に version がありません"* ]]
}

@test "ブランチで新設した plugin は bump 不要" {
  publish_base_with_foo
  add_plugin bar 0.1.0
  stage_and_run
  [ "$status" -eq 0 ]
}

@test "中身を変えて version 据え置きなら止める" {
  publish_base_with_foo
  echo extra >> plugins/foo/skills/foo/SKILL.md
  stage_and_run
  [ "$status" -eq 1 ]
  [[ $output == *"plugins/foo の中身が変わったのに version が 0.1.0 のままです"* ]]
}

@test "中身を変えて bump すれば通る" {
  publish_base_with_foo
  echo extra >> plugins/foo/skills/foo/SKILL.md
  set_version foo 0.1.1
  stage_and_run
  [ "$status" -eq 0 ]
}

@test "default branch 上でも未 push の据え置きを止める" {
  publish_base_with_foo
  git checkout -q -b main origin/main
  echo extra >> plugins/foo/skills/foo/SKILL.md
  stage_and_run
  [ "$status" -eq 1 ]
  [[ $output == *"version が 0.1.0 のままです"* ]]
}

@test "merge-base を解決できなければ警告して bump 判定を飛ばす" {
  add_plugin foo 0.1.0
  stage_and_run
  [ "$status" -eq 0 ]
  [[ $output == *"bump と renames の判定を飛ばします"* ]]
}

@test "source の先に plugin.json が無ければ止める" {
  publish_base_with_foo
  edit_catalog '.plugins[0].source = "./plugins/nope"'
  stage_and_run
  [ "$status" -eq 1 ]
  [[ $output == *"source ./plugins/nope に .claude-plugin/plugin.json がありません"* ]]
}

@test "source 末尾の / は許容する" {
  publish_base_with_foo
  edit_catalog '.plugins[0].source = "./plugins/foo/"'
  stage_and_run
  [ "$status" -eq 0 ]
}

@test "相対パス以外の source はその旨を伝えて止める" {
  publish_base_with_foo
  edit_catalog '.plugins += [{name: "ext", source: {source: "github", repo: "o/r"}}]'
  stage_and_run
  [ "$status" -eq 1 ]
  [[ $output == *"source に相対パス (./plugins/<name>) 以外を使いません"* ]]
}

@test "entry と plugin.json の name が違えば止める" {
  publish_base_with_foo
  edit_catalog '.plugins[0].name = "foo2"'
  stage_and_run
  [ "$status" -eq 1 ]
  [[ $output == *"name (foo) が一致しません"* ]]
}

@test "カタログ entry に version があれば止める" {
  publish_base_with_foo
  edit_catalog '.plugins[0].version = "0.1.0"'
  stage_and_run
  [ "$status" -eq 1 ]
  [[ $output == *"カタログ entry foo に version があります"* ]]
}

@test "カタログに載っていない plugin は止める" {
  publish_base_with_foo
  add_plugin bar 0.1.0
  edit_catalog 'del(.plugins[1])'
  stage_and_run
  [ "$status" -eq 1 ]
  [[ $output == *"plugins/bar がカタログに載っていません"* ]]
}

@test "kebab-case でない plugin 名は止める" {
  publish_base_with_foo
  add_plugin Foo_Bar 0.1.0
  stage_and_run
  [ "$status" -eq 1 ]
  [[ $output == *"plugins/Foo_Bar: plugin 名が kebab-case ではありません"* ]]
}

@test "plugin.json が JSON として不正なら、そう伝えて止める" {
  publish_base_with_foo
  echo '{' > plugins/foo/.claude-plugin/plugin.json
  stage_and_run
  [ "$status" -eq 1 ]
  [[ $output == *"plugins/foo/.claude-plugin/plugin.json が JSON として不正です"* ]]
}

@test "カタログが JSON として不正なら、そう伝えて止める" {
  publish_base_with_foo
  echo '{' > .claude-plugin/marketplace.json
  stage_and_run
  [ "$status" -eq 1 ]
  [[ $output == *".claude-plugin/marketplace.json が JSON として不正です"* ]]
}

@test "renames なしで plugin を消すと止める" {
  publish_base_with_foo
  git rm -rq plugins/foo
  edit_catalog 'del(.plugins[0])'
  stage_and_run
  [ "$status" -eq 1 ]
  [[ $output == *"カタログの renames に foo がありません"* ]]
}

@test "renames に旧名を書けば plugin を消せる" {
  publish_base_with_foo
  git rm -rq plugins/foo
  edit_catalog 'del(.plugins[0]) | .renames = {foo: null}'
  stage_and_run
  [ "$status" -eq 0 ]
}

@test "validate は index を読む: stage した壊れた manifest は作業ツリーを直しても止める" {
  publish_base_with_foo
  set_version foo 0.1.1
  jq '.skills = "./nope"' plugins/foo/.claude-plugin/plugin.json > p.tmp && mv p.tmp plugins/foo/.claude-plugin/plugin.json
  git add -A
  jq 'del(.skills)' plugins/foo/.claude-plugin/plugin.json > p.tmp && mv p.tmp plugins/foo/.claude-plugin/plugin.json
  run "$HOOK"
  [ "$status" -eq 1 ]
  [[ $output == *"validate に失敗しました"* && $output == *"Path not found: ./nope"* ]]
}

@test "validate は index を読む: 未 stage の壊れた WIP では止めない" {
  publish_base_with_foo
  jq '.skills = "./nope"' plugins/foo/.claude-plugin/plugin.json > p.tmp && mv p.tmp plugins/foo/.claude-plugin/plugin.json
  run "$HOOK"
  [ "$status" -eq 0 ]
}
