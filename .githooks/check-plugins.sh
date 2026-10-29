#!/usr/bin/env bash
# pre-commit から呼ばれる plugin 検査。
#
# 1. plugin.json に version が無い plugin を落とす (明示 bump 方針の前提)
# 2. 中身が変わったのに version が据え置きの plugin を落とす
#    (version は cache key であり、据え置くと GitHub 経由の購読者に更新が届かない)
# 3. カタログと plugins/ の整合 (source / name / 掲載漏れ / entry の version / renames) を見る
# 4. `claude plugin validate` をカタログと各 plugin に通す
#
# 判定は index (staged) を正とする。commit されるものを見るため。
# bump の判定範囲はブランチ全体 (merge-base から index まで)。squash merge 運用では
# ブランチが 1 commit に潰れるため、bump を担う単位は個々の commit ではなくブランチである。
# 判定ロジックは headwaters の .claude/hooks/plugin-version-bump.sh に倣う。
#
# fail-closed。jq / claude が無ければ止める。意図的な迂回は `git commit --no-verify`。
set -euo pipefail

MANIFEST_REL=".claude-plugin/plugin.json"
CATALOG=".claude-plugin/marketplace.json"
NAME_RE='^[a-z0-9]+(-[a-z0-9]+)*$'

for bin in jq claude; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "check-plugins: $bin が見つからないため commit を停止しました。" >&2
    echo "  意図的に迂回する場合のみ: git commit --no-verify" >&2
    exit 1
  fi
done

# index にある plugin 名を列挙する。
indexed_plugins() {
  git ls-files -- plugins/ | awk -F/ 'NF >= 3 { print $2 }' | sort -u
}

# <ref> 時点にあった plugin 名を列挙する。
plugins_at_ref() {
  git ls-tree --name-only "$1" plugins/ 2>/dev/null | awk -F/ '{ print $2 }' | grep -v '^\.' || true
}

# <ref> 時点の version。無ければ空。
version_at_ref() {
  git show "$1:plugins/$2/$MANIFEST_REL" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true
}

# 比較の起点。origin を先に引くので、default branch 上でも未 push 分を切り出せる。
# 引けなければ空を返す (呼び出し側が警告して bump と renames の判定を飛ばす)。
resolve_base() {
  local default
  default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
  [[ -z $default ]] && default=main
  git merge-base "origin/$default" HEAD 2>/dev/null ||
    git merge-base "$default" HEAD 2>/dev/null ||
    true
}

errors=()
base=$(resolve_base)
[[ -z $base ]] && echo "check-plugins: 比較の起点 (merge-base) を解決できないため、bump と renames の判定を飛ばします。" >&2

while IFS= read -r name; do
  [[ -z $name ]] && continue
  [[ $name =~ $NAME_RE ]] || errors+=("plugins/$name: plugin 名が kebab-case ではありません")
  if ! manifest=$(git show ":plugins/$name/$MANIFEST_REL" 2>/dev/null); then
    errors+=("plugins/$name/$MANIFEST_REL が index にありません")
    continue
  fi
  if ! printf '%s' "$manifest" | jq -e . >/dev/null 2>&1; then
    errors+=("plugins/$name/$MANIFEST_REL が JSON として不正です")
    continue
  fi
  new=$(printf '%s' "$manifest" | jq -r '.version // empty')
  if [[ -z $new ]]; then
    errors+=("plugins/$name/$MANIFEST_REL に version がありません (明示 bump 方針のため必須)")
    continue
  fi
  [[ -z $base ]] && continue
  old=$(version_at_ref "$base" "$name")
  # base に居ない = このブランチで生まれた plugin。初版に bump は要らない。
  [[ -z $old ]] && continue
  if [[ -n $(git diff --cached --name-only "$base" -- "plugins/$name/") && $old == "$new" ]]; then
    errors+=("plugins/$name の中身が変わったのに version が $old のままです")
  fi
done < <(indexed_plugins)

# カタログと plugins/ の整合。`claude plugin validate` は source の実在を見ないため、ここで見る。
if ! catalog=$(git show ":$CATALOG" 2>/dev/null); then
  errors+=("$CATALOG が index にありません")
elif ! printf '%s' "$catalog" | jq -e . >/dev/null 2>&1; then
  errors+=("$CATALOG が JSON として不正です")
else
  while IFS=$'\t' read -r entry src_type src has_version; do
    [[ -z $entry ]] && continue
    [[ $has_version == true ]] && errors+=("カタログ entry $entry に version があります (plugin.json 側だけに書く)")
    if [[ $src_type != string ]]; then
      errors+=("カタログ entry $entry: この repo では source に相対パス (./plugins/<name>) 以外を使いません")
      continue
    fi
    dir=${src#./}
    dir=${dir%/}
    manifest_name=$(git show ":$dir/$MANIFEST_REL" 2>/dev/null | jq -r '.name // empty' 2>/dev/null || true)
    if [[ -z $manifest_name ]]; then
      errors+=("カタログ entry $entry の source $src に $MANIFEST_REL がありません")
    elif [[ $manifest_name != "$entry" ]]; then
      errors+=("カタログ entry $entry と $dir/$MANIFEST_REL の name ($manifest_name) が一致しません")
    fi
  done < <(printf '%s' "$catalog" | jq -r '.plugins[] | [.name, (.source | type), (.source | tostring), (has("version") | tostring)] | @tsv')

  while IFS= read -r name; do
    [[ -z $name ]] && continue
    printf '%s' "$catalog" | jq -e --arg s "plugins/$name" \
      'any(.plugins[]; (.source | type) == "string" and (.source | ltrimstr("./") | rtrimstr("/")) == $s)' >/dev/null ||
      errors+=("plugins/$name がカタログに載っていません")
  done < <(indexed_plugins)

  # base にあって index から消えた plugin (削除・改名) は renames に旧名が要る。
  # 書かないとインストール済みの環境で plugin が見つからなくなる。
  if [[ -n $base ]]; then
    while IFS= read -r name; do
      [[ -z $name ]] && continue
      [[ -n $(git ls-files -- "plugins/$name/") ]] && continue
      printf '%s' "$catalog" | jq -e --arg n "$name" '(.renames // {}) | has($n)' >/dev/null ||
        errors+=("plugins/$name が消えましたが、カタログの renames に $name がありません (改名なら新名、削除なら null)")
    done < <(plugins_at_ref "$base")
  fi
fi

if ((${#errors[@]})); then
  echo "check-plugins: commit を停止しました。" >&2
  printf '  - %s\n' "${errors[@]}" >&2
  [[ -n $base ]] && echo "  (bump と renames の判定範囲は $base から index まで)" >&2
  exit 1
fi

# validate は渡したディレクトリを読む。index を一時ディレクトリへ書き出して渡し、
# commit される内容で判定する (stash は worktree 間で共有されるため使わない)。
snapshot=$(mktemp -d)
trap 'rm -rf "$snapshot"' EXIT
git checkout-index -a --prefix="$snapshot/"

validate() { # <dir> <label>
  claude plugin validate "$1" >/dev/null && return 0
  claude plugin validate "$1" >&2 || true
  echo "check-plugins: $2 の validate に失敗しました。" >&2
  exit 1
}
validate "$snapshot" "$CATALOG"
while IFS= read -r name; do
  [[ -z $name ]] && continue
  validate "$snapshot/plugins/$name" "plugins/$name"
done < <(indexed_plugins)
