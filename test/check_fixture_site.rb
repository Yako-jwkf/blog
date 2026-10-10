#!/usr/bin/env ruby
# frozen_string_literal: true

# 使い方: ruby test/check_fixture_site.rb <テスト用サイトのビルド結果>
# test/fixtures の記事が正しく出力されたか(特殊な文字が壊れず、下書きが出ていないか)を確かめる。

require "json"
require "rexml/document"

Encoding.default_external = Encoding::UTF_8

site = File.expand_path(ARGV.fetch(0) { abort "使い方: ruby test/check_fixture_site.rb <ビルド結果>" })
TITLE = %(記号 <テスト> & "引用" 'single' ]]> \\ 😀)
POST = File.join(site, "posts/2026/10/09/special-chars/index.html")
failures = []
check = ->(name, ok) { ok ? puts("ok   #{name}") : (puts("FAIL #{name}"); failures << name) }

html = File.read(POST)
check.call("記事のタイトルが HTML として解釈されない", html.include?("&lt;テスト&gt;") && !html.include?("<テスト>"))
check.call("raw で囲んだ {{ }} がそのまま表示される", html.gsub(/<[^>]+>/, "").include?("{{ site.title }}"))
check.call("コード内の script が実行されない形で出力される", html.include?("&lt;script&gt;") && !html.match?(/<script>alert/))
check.call("画像がサブパス付きで参照される", html.include?('src="/blog/assets/images/fixture-sample.png"'))
check.call("画像ファイルが出力される", File.file?(File.join(site, "assets/images/fixture-sample.png")))
check.call("コメントのリンクが出る", html.include?('href="https://github.com/Yako-jwkf/blog/discussions/1"'))

feed = REXML::Document.new(File.read(File.join(site, "feed.xml")))
titles = REXML::XPath.match(feed, "//item/title").map(&:text)
check.call("RSS のタイトルが元の文字のまま読める", titles.include?(TITLE))

index = JSON.parse(File.read(File.join(site, "search.json")))
check.call("検索データのタイトルが元の文字のまま読める", index.any? { |e| e["title"] == TITLE })
check.call("検索データにタグが入る", index.any? { |e| e["tags"].include?("C++") && e["tags"].include?("スペース 入り") })

all_output = Dir.glob("**/*", base: site).select { |f| File.file?(File.join(site, f)) }
                .map { |f| File.read(File.join(site, f), mode: "rb").force_encoding("UTF-8") }.join
check.call("下書きが公開サイトに出ていない", !all_output.include?("DRAFT-MARKER"))

tags = File.read(File.join(site, "tags/index.html"))
check.call("記号を含むタグにページ内リンクができる", tags.include?('id="tag-c"') && tags.include?('id="tag-スペース-入り"'))

puts
if failures.empty?
  puts "テスト用サイトの確認: すべて成功"
else
  puts "テスト用サイトの確認: #{failures.size} 件失敗"
  exit 1
end
