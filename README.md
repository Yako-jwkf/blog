# blog

GitHub Pages で公開しているブログです。記事は Markdown で `_posts/` に置き、`main` に入ると GitHub Actions が Jekyll でビルド・検査して公開します。

- 公開先: https://yako-jwkf.github.io/blog/
- 記事の書き方・公開のしくみ・元に戻す方法: [admin.md](admin.md)

## 構成

| 場所 | 内容 |
| --- | --- |
| `_posts/` | 記事の原本 |
| `_layouts/`, `_includes/`, `_data/` | ページの共通部分とメニュー |
| `assets/` | CSS・JavaScript・画像 |
| `index.html`, `tags.html`, `categories.html`, `search.html`, `about.md`, `404.html` | 各ページ |
| `search.json`, `feed.xml`, `sitemap.xml` | 検索用データ・RSS 2.0・サイトマップ(ビルド時に生成) |
| `scripts/` | 記事の検査とビルド結果の検査(Ruby の標準ライブラリのみ) |
| `test/` | 検査のテストと、特殊な文字を含むテスト用記事 |
| `.github/workflows/` | 公開(`pages.yml`)と検査(`article-validation.yml`) |

外部の CDN・フォント・JavaScript ライブラリは使っていません。使う GitHub Actions は GitHub 公式の `actions/*` だけです。
