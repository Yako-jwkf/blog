# 管理・投稿の手順

このファイルはサイトには載りません(`_config.yml` の `exclude` に入れています)。

## 記事を書く

1. iA Writer などで本文を書く。
2. GitHub のリポジトリで `_posts` フォルダを開き、「Add file」→「Create new file」を選ぶ。
3. ファイル名を `YYYY-MM-DD-英小文字と数字とハイフン.md` にする(例: `2026-10-09-first-post.md`)。
   - 日付の後ろの部分(例: `first-post`)が記事の URL になります。ほかの記事と同じ名前は使えません。
   - 公開した記事のファイル名は変えないでください。URL が変わり、古いリンクが切れます。
4. 先頭に次の Front Matter を書き、その下に本文を貼る。

```markdown
---
title: "記事のタイトル"
date: 2026-10-09 12:00:00 +0900
description: "一覧や RSS に出る短い説明"
tags:
  - 技術
categories:
  - 日記
---

ここから本文。
```

5. 「Commit changes」で `main` に保存する。数分で自動的に公開されます。

| 項目 | 必須 | 書き方 |
| --- | --- | --- |
| `title` | 必須 | 記事のタイトル |
| `date` | 必須 | 公開日時。`+0900` のようにタイムゾーンを付ける。日付はファイル名と同じにする |
| `description` | 任意 | 短い説明。なければ本文の最初の段落を使う |
| `tags` / `categories` | 任意 | `- 名前` を1行ずつ並べる。記号だけの名前や、記号以外が同じ名前(`C++` と `C#` など)は使えない |
| `discussion_url` | 任意 | コメント用の GitHub Discussion の URL(下記) |
| `published` | 任意 | `false` にすると公開しない |

### 画像

画像は `assets/images/` に入れ、本文では次のように書きます(公開先の `/blog/` を自動で付けるため)。

```markdown
![説明]({{ '/assets/images/ファイル名.png' | relative_url }})
```

### 書けないもの

- 本文に `{{` や `{%` をそのまま書くと、Jekyll の命令として扱われて記事が壊れます。コードなどでそのまま見せたいときは `{% raw %}` と `{% endraw %}` で囲んでください。
- `<script>` や `<iframe>`、`onclick=` などの HTML は、コードブロック(```` ``` ````)の外には書けません。

どちらも、検査に引っかかったときはエラーの内容が GitHub の Actions に表示されます。

## 下書き

このリポジトリは公開されているので、ここに置いたファイルは誰でも読めます。`published: false` はブログに載せないだけで、隠すことはできません。下書きは iA Writer の中に置いておき、公開するときにリポジトリへ入れてください。

## コメント

1. リポジトリの Settings → General → Features で Discussions をオンにする(最初の1回だけ)。
2. Discussions で記事用のスレッドを作る。
3. その URL を記事の `discussion_url` に書く。書いていない記事にはコメント欄が出ません。

## 公開のしくみ

- `main` に変更が入ると `.github/workflows/pages.yml` が動き、記事の検査 → Jekyll でビルド → 生成物の検査 → GitHub Pages へ公開、の順に進みます。
- どこかで失敗すると、公開は行われず、前のサイトがそのまま残ります。
- `.github/workflows/article-validation.yml` は、すべての push とプルリクエストで同じ検査とテストを行います(公開はしません)。
- 使う GitHub Actions は GitHub 公式の `actions/*` だけで、バージョンはコミットの番号で固定しています。

## 失敗したとき・元に戻すとき

- 失敗の理由は、リポジトリの Actions タブで、赤い × の付いた実行を開くと見られます。
- 記事を直して保存し直せば、もう一度自動で公開されます。Actions タブの「Build and deploy blog」→「Run workflow」で手動でも実行できます。
- 前の状態に戻したいときは、戻したいコミットを `git revert` するか、GitHub 上でファイルを前の内容に直して保存します。履歴はすべて Git に残っています。

## 手元での確認(パソコンがある場合)

```sh
ruby scripts/validate_posts.rb          # 記事の検査
ruby test/run_tests.rb                  # 検査のテスト
```

ビルドまで試すには、GitHub Pages と同じ `github-pages` gem(バージョン 232)を使ってください。
