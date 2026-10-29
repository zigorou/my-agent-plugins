#!/usr/bin/env bash
# UserPromptSubmit hook: プロンプト中の X (Twitter) ポスト URL を検出し、
# fxtwitter-read skill で読むよう促す短い文脈を注入する。
#
# プロンプトインジェクション対策: プロンプトの文字列を注入へ写さない。
# 厳密な正規表現で数字のポスト ID だけを取り出し、正規化した URL を固定文面に埋める。
# 通信はしない (取得は skill が担う)。
#
# fail-open。判定できない事情があっても exit 0 で何も注入せず通す (プロンプト送信を塞がない)。
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
prompt=$(jq -r '.prompt // empty' 2>/dev/null) || exit 0
[[ -z $prompt ]] && exit 0

# ホスト名とスキームは大文字小文字を区別しない。ID の直後は区切り文字か末尾に固定し、
# 長すぎる数字列を別の ID に切り詰めない。
ids=$(printf '%s' "$prompt" |
  grep -oiE 'https?://([a-z]+\.)?(x|twitter|fxtwitter|fixupx|vxtwitter|fixvx)\.com/([A-Za-z0-9_]{1,15}|i|i/web)/status(es)?/[0-9]{1,25}([^0-9]|$)' |
  grep -oiE '/status(es)?/[0-9]+' | grep -oE '[0-9]+' | awk '!seen[$0]++' | head -n 5) || true
has_article=$(printf '%s' "$prompt" |
  grep -oiE 'https?://([a-z]+\.)?(x|twitter|fxtwitter|fixupx|vxtwitter|fixvx)\.com/i/article/' | head -n 1) || true
[[ -z $ids && -z $has_article ]] && exit 0

context=""
if [[ -n $ids ]]; then
  urls=$(printf '%s\n' "$ids" | sed 's#^#- https://x.com/i/status/#')
  context="プロンプトに X のポスト URL が含まれている:
$urls
中身が必要なら fxtwitter plugin の skill で読む (x.com を WebFetch で直接読まない)。ポストの表示を頼まれたら fxtwitter:fxtwitter-show、スレッドや連投なら fxtwitter:fxtwitter-thread、それ以外で中身を踏まえて答えるなら fxtwitter:fxtwitter-read。"
fi
if [[ -n $has_article ]]; then
  [[ -n $context ]] && context="$context
"
  context="${context}プロンプトに X の記事 URL (/i/article/) が含まれている。x.com を WebFetch しても中身は読めず、fxtwitter plugin も記事 URL を直接は扱えない。中身が必要なら、記事を載せたポストの URL (…/status/<数字>) を渡すようユーザーに頼む。"
fi

jq -n --arg c "$context" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
