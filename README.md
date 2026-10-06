# blog

Astro で作ったブログです。`main` ブランチに変更が入ると、GitHub Actions が自動でビルドして Cloudflare Workers に公開します。

## 記事の追加

`src/content/blog/` に Markdown ファイル(`.md`)を1つ置くと、記事が1本増えます。ファイル名がそのまま URL になります(例: `hello.md` → `/blog/hello/`)。ファイル名は半角英数字とハイフンにしてください。

ファイルの先頭には、次の4行を `---` で囲んで書きます。

```markdown
---
title: '記事のタイトル'
description: '一覧や検索結果に出る短い説明'
pubDate: '2026-10-06'
---

ここから本文を書きます。
```

`pubDate` は公開日です。新しい日付の記事ほど上に並びます。

## 公開のしくみ

- `.github/workflows/deploy.yml` が `main` への push のたびに `npx astro build` と `wrangler deploy` を実行します。
- Cloudflare の API トークンを、リポジトリの Settings → Secrets and variables → Actions に `CLOUDFLARE_API_TOKEN` という名前で登録しておく必要があります。登録されていない間は、公開の手順をとばして終了します。
- 公開先の Worker の名前は `wrangler.jsonc` の `name`(`blog`)です。

## 手元で動かす場合

| コマンド | 内容 |
| :-- | :-- |
| `npm install` | 必要なパッケージを入れる |
| `npm run dev` | 確認用サーバーを `localhost:4321` で起動する |
| `npm run build` | `./dist/` に公開用のファイルを作る |
| `npx wrangler dev` | ビルド結果を Cloudflare と同じしくみで確認する |
