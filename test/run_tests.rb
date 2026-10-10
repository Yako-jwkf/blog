#!/usr/bin/env ruby
# frozen_string_literal: true

# 使い方:
#   ruby test/run_tests.rb                 記事の検査(validate_posts.rb)のテスト
#   ruby test/run_tests.rb <ビルド結果>    加えて、サイトの検査(check_site.rb)が壊れたサイトを見つけるかのテスト

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

Encoding.default_external = Encoding::UTF_8

ROOT = File.expand_path("..", __dir__)
RUBY = RbConfig.ruby
$failures = []
$count = 0

def run(script, *args)
  out, status = Open3.capture2e(RUBY, File.join(ROOT, "scripts", script), *args)
  [status.success?, out]
end

def check(name, ok)
  $count += 1
  if ok
    puts "ok   #{name}"
  else
    puts "FAIL #{name}"
    $failures << name
  end
end

GOOD_FRONT = <<~MD
  ---
  title: "記事"
  date: 2026-10-09 12:00:00 +0900
  tags:
    - 技術
  categories:
    - 日記
  description: "説明"
  ---
MD

def with_posts(files)
  Dir.mktmpdir do |dir|
    FileUtils.mkdir_p(File.join(dir, "_posts"))
    files.each { |name, text| File.write(File.join(dir, "_posts", name), text) }
    yield dir
  end
end

def expect_posts(name, files, pass:, message: nil)
  with_posts(files) do |dir|
    ok, out = run("validate_posts.rb", dir)
    check(name, ok == pass && (message.nil? || out.include?(message)))
    puts out.gsub(/^/, "       ") unless ok == pass
  end
end

# --- 記事の検査 ---
expect_posts "正しい記事は通る", { "2026-10-09-first-post.md" => "#{GOOD_FRONT}\n本文\n" }, pass: true
expect_posts "Front Matter がない記事を見つける", { "2026-10-09-a.md" => "本文だけ\n" }, pass: false, message: "Front Matter"
expect_posts "title がない記事を見つける",
             { "2026-10-09-a.md" => GOOD_FRONT.sub(/^title:.*\n/, "") }, pass: false, message: "title"
expect_posts "タイムゾーンのない date を見つける",
             { "2026-10-09-a.md" => GOOD_FRONT.sub("12:00:00 +0900", "12:00:00") }, pass: false, message: "タイムゾーン"
expect_posts "ファイル名と違う日付を見つける",
             { "2026-10-08-a.md" => GOOD_FRONT }, pass: false, message: "ファイル名の日付"
expect_posts "UTC で書いても日本時間で同じ日なら通る",
             { "2026-10-10-a.md" => GOOD_FRONT.sub("2026-10-09 12:00:00 +0900", "2026-10-09 23:00:00 +0000") }, pass: true
expect_posts "日本語のファイル名を拒否する", { "2026-10-09-日記.md" => GOOD_FRONT }, pass: false, message: "ファイル名"
expect_posts "大文字のファイル名を拒否する", { "2026-10-09-First.md" => GOOD_FRONT }, pass: false, message: "ファイル名"
expect_posts "日付のないファイル名を拒否する", { "first-post.md" => GOOD_FRONT }, pass: false, message: "ファイル名"
expect_posts "パス区切りを含む名前を拒否する", { "2026-10-09-..md" => GOOD_FRONT }, pass: false, message: "ファイル名"
expect_posts "重複した slug を見つける",
             { "2026-10-09-same.md" => GOOD_FRONT, "2026-10-10-same.md" => GOOD_FRONT.sub("2026-10-09", "2026-10-10") },
             pass: false, message: "同じです"
expect_posts "tags を文字で書いた記事を見つける",
             { "2026-10-09-a.md" => GOOD_FRONT.sub("tags:\n  - 技術", "tags: 技術") }, pass: false, message: "tags"
expect_posts "知らない項目(書き間違い)を見つける",
             { "2026-10-09-a.md" => GOOD_FRONT.sub("tags:", "tag:") }, pass: false, message: "知らない項目"
expect_posts "本文の {{ を見つける", { "2026-10-09-a.md" => "#{GOOD_FRONT}\n値は {{ site.title }} です\n" },
             pass: false, message: "{% raw %}"
expect_posts "raw で囲んだ {{ は通る",
             { "2026-10-09-a.md" => "#{GOOD_FRONT}\n{% raw %}\n```\n{{ x }}\n```\n{% endraw %}\n" }, pass: true
expect_posts "画像の relative_url は通る",
             { "2026-10-09-a.md" => "#{GOOD_FRONT}\n![写真]({{ '/assets/images/a.png' | relative_url }})\n" }, pass: true
expect_posts "script タグを見つける", { "2026-10-09-a.md" => "#{GOOD_FRONT}\n<script>alert(1)</script>\n" },
             pass: false, message: "HTML"
expect_posts "onerror 属性を見つける", { "2026-10-09-a.md" => "#{GOOD_FRONT}\n<img src=x onerror=alert(1)>\n" },
             pass: false, message: "HTML"
expect_posts "コードブロック内の script は通る",
             { "2026-10-09-a.md" => "#{GOOD_FRONT}\n```html\n<script>alert(1)</script>\n```\n" }, pass: true
expect_posts "間違った discussion_url を見つける",
             { "2026-10-09-a.md" => GOOD_FRONT.sub(/---\n\z/, "discussion_url: https://example.com/x\n---\n") },
             pass: false, message: "discussion_url"
expect_posts "正しい discussion_url は通る",
             { "2026-10-09-a.md" => GOOD_FRONT.sub(/---\n\z/, "discussion_url: https://github.com/Yako-jwkf/blog/discussions/1\n---\n") },
             pass: true
expect_posts "区別できないタグ(C++ と C#)を見つける",
             { "2026-10-09-a.md" => GOOD_FRONT.sub("  - 技術", "  - C++\n  - C#") }, pass: false, message: "区別できません"
expect_posts "記号だけのタグを見つける",
             { "2026-10-09-a.md" => GOOD_FRONT.sub("  - 技術", "  - \"++\"") }, pass: false, message: "文字か数字"
expect_posts "大文字小文字だけ違うタグを見つける",
             { "2026-10-09-a.md" => GOOD_FRONT, "2026-10-10-b.md" => GOOD_FRONT.sub("2026-10-09", "2026-10-10").sub("  - 技術", "  - Web\n  - web") },
             pass: false, message: "区別できません"
expect_posts "YAML の書き間違いを見つける", { "2026-10-09-a.md" => "---\ntitle: [壊れた\n---\n" },
             pass: false, message: "Front Matter を読めません"

# --- サイトの検査(ビルド結果が渡されたときだけ) ---
if (built = ARGV[0])
  built = File.expand_path(built)
  ok, out = run("check_site.rb", built, ROOT)
  check("ビルド結果がサイトの検査を通る", ok)
  puts out.gsub(/^/, "       ") unless ok

  mutate = lambda do |name, message, &block|
    Dir.mktmpdir do |dir|
      copy = File.join(dir, "site")
      FileUtils.cp_r(built, copy)
      block.call(copy)
      ok, out = run("check_site.rb", copy, ROOT)
      check(name, !ok && out.include?(message))
      puts out.gsub(/^/, "       ") if ok || !out.include?(message)
    end
  end

  mutate.call("feed.xml の欠落を見つける", "feed.xml: ファイルがありません") { |s| File.delete(File.join(s, "feed.xml")) }
  mutate.call("壊れた RSS を見つける", "XML として読めません") { |s| File.write(File.join(s, "feed.xml"), "<rss><channel>") }
  mutate.call("壊れた検索データを見つける", "JSON として読めません") { |s| File.write(File.join(s, "search.json"), "[{") }
  mutate.call("リンク切れを見つける", "リンク先がありません") do |s|
    File.open(File.join(s, "index.html"), "a") { |f| f.puts('<a href="/blog/no-such-page/">x</a>') }
  end
  mutate.call("サブパスを無視したリンクを見つける", "で始まっていません") do |s|
    File.open(File.join(s, "index.html"), "a") { |f| f.puts('<a href="/tags/">x</a>') }
  end
  mutate.call("存在しないタグへのリンクを見つける", "がありません") do |s|
    File.open(File.join(s, "index.html"), "a") { |f| f.puts('<a href="/blog/tags/#tag-no-such-tag">x</a>') }
  end
  mutate.call("トークンの混入を見つける", "GitHub のトークン") do |s|
    File.write(File.join(s, "assets", "js", "leak.js"), "const t = 'ghp_#{'a' * 36}';")
  end
end

puts
if $failures.empty?
  puts "テスト: #{$count} 件すべて成功"
else
  puts "テスト: #{$failures.size} / #{$count} 件失敗"
  exit 1
end
