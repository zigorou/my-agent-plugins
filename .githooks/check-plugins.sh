#!/usr/bin/env bash
# pre-commit から呼ばれる plugin 検査。
#
# 1. plugin.json に version が無い plugin を落とす (明示 bump 方針の前提)
# 2. 中身が変わったのに version が据え置きの plugin を落とす
#    (version は cache key であり、据え置くと GitHub 経由の購読者に更新が届かない)
# 3. `claude plugin validate` をカタログと各 plugin に通す
#
# 判定は index (staged) を正とする。commit されるものを見るため。
# bump の判定範囲はブランチ全体 (merge-base から index まで)。squash merge 運用では
# ブランチが 1 commit に潰れるため、bump を担う単位は個々の commit ではなくブランチである。
# 判定ロジックは headwaters の .claude/hooks/plugin-version-bump.sh に倣う。
#
# fail-closed。jq / claude が無ければ止める。意図的な迂回は `git commit --no-verify`。
set -euo pipefail

MANIFEST_REL=".claude-plugin/plugin.json"

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

# index 側の version。無ければ空。
version_in_index() {
  git show ":plugins/$1/$MANIFEST_REL" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true
}

# <ref> 時点の version。無ければ空。
version_at_ref() {
  git show "$1:plugins/$2/$MANIFEST_REL" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true
}

# 比較の起点。default branch 上や base が引けないときは空を返し、bump 判定を飛ばす
# (default branch への直 commit は git-guard が別途止める)。
resolve_base() {
  local default cur
  default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
  [[ -z $default ]] && default=main
  cur=$(git branch --show-current 2>/dev/null || true)
  [[ -z $cur || $cur == "$default" ]] && return 0
  git merge-base "origin/$default" HEAD 2>/dev/null ||
    git merge-base "$default" HEAD 2>/dev/null ||
    true
}

errors=()
base=$(resolve_base)

while IFS= read -r name; do
  [[ -z $name ]] && continue
  if ! git cat-file -e ":plugins/$name/$MANIFEST_REL" 2>/dev/null; then
    errors+=("plugins/$name/$MANIFEST_REL が index にありません")
    continue
  fi
  new=$(version_in_index "$name")
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
CATALOG=".claude-plugin/marketplace.json"
catalog=$(git show ":$CATALOG" 2>/dev/null) || { errors+=("$CATALOG が index にありません"); catalog='{"plugins":[]}'; }
while IFS=$'\t' read -r entry src has_version; do
  [[ -z $entry ]] && continue
  dir=${src#./}
  manifest_name=$(git show ":$dir/$MANIFEST_REL" 2>/dev/null | jq -r '.name // empty' 2>/dev/null || true)
  if [[ -z $manifest_name ]]; then
    errors+=("カタログ entry $entry の source $src に $MANIFEST_REL がありません")
  elif [[ $manifest_name != "$entry" ]]; then
    errors+=("カタログ entry $entry と $dir/$MANIFEST_REL の name ($manifest_name) が一致しません")
  fi
  [[ $has_version == true ]] && errors+=("カタログ entry $entry に version があります (plugin.json 側だけに書く)")
done < <(printf '%s' "$catalog" | jq -r '.plugins[] | [.name, (.source | tostring), (has("version") | tostring)] | @tsv')
while IFS= read -r name; do
  [[ -z $name ]] && continue
  printf '%s' "$catalog" | jq -e --arg s "./plugins/$name" 'any(.plugins[]; .source == $s)' >/dev/null ||
    errors+=("plugins/$name がカタログに載っていません")
done < <(indexed_plugins)

if ((${#errors[@]})); then
  echo "check-plugins: commit を停止しました。" >&2
  printf '  - %s\n' "${errors[@]}" >&2
  [[ -n $base ]] && echo "  (bump の判定範囲は $base から index までのブランチ全体)" >&2
  exit 1
fi

# validate は作業ツリーを読む。staged と作業ツリーがずれていると、commit されない内容で判定される。
claude plugin validate . >/dev/null || {
  claude plugin validate . >&2 || true
  echo "check-plugins: カタログの validate に失敗しました。" >&2
  exit 1
}
while IFS= read -r name; do
  [[ -z $name ]] && continue
  claude plugin validate "plugins/$name" >/dev/null || {
    claude plugin validate "plugins/$name" >&2 || true
    echo "check-plugins: plugins/$name の validate に失敗しました。" >&2
    exit 1
  }
done < <(indexed_plugins)
