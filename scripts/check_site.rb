#!/usr/bin/env ruby
# frozen_string_literal: true

# 使い方: ruby scripts/check_site.rb <ビルド結果のフォルダ> [リポジトリのフォルダ]
# Jekyll が作ったサイトを公開前に検査する。問題があれば一覧を表示して、終了コード 1 で終わる。

require "cgi"
require "json"
require "rexml/document"
require "time"
require "uri"
require "yaml"
require_relative "lib/posts"

Encoding.default_external = Encoding::UTF_8

site = File.expand_path(ARGV.fetch(0) { abort "使い方: ruby scripts/check_site.rb <ビルド結果のフォルダ> [リポジトリのフォルダ]" })
root = File.expand_path(ARGV[1] || File.join(__dir__, ".."))
abort "ビルド結果のフォルダがありません: #{site}" unless File.directory?(site)

config = YAML.safe_load(File.read(File.join(root, "_config.yml")))
base_url = config.fetch("url").chomp("/")
base_path = config.fetch("baseurl", "").to_s.chomp("/")
site_root_url = "#{base_url}#{base_path}/"
feed_limit = Integer(config.fetch("feed_limit", 20))

errors = []
error = ->(file, message) { errors << [file, message] }

posts = BlogPosts.load(root)
unless posts.all? { |post| post.errors.empty? }
  abort "記事の書式に問題があります。先に ruby scripts/validate_posts.rb を通してください"
end
published = posts.select(&:published?)
unpublished = posts.reject(&:published?)

# 1. 必ずあるはずのファイル
%w(
  index.html 404.html feed.xml search.json sitemap.xml
  tags/index.html categories/index.html search/index.html about/index.html
  assets/css/style.css assets/js/search.js
).each do |file|
  error.call(file, "ファイルがありません") unless File.file?(File.join(site, file))
end

# 2. 記事ごとのページ(下書きは出力されていないこと)
published.each do |post|
  file = File.join(post.url_path.delete_prefix("/"), "index.html")
  error.call(post.path, "記事のページ #{file} が作られていません") unless File.file?(File.join(site, file))
end
unpublished.each do |post|
  file = File.join(post.url_path.delete_prefix("/"), "index.html")
  error.call(post.path, "published: false の記事が公開されています") if File.exist?(File.join(site, file))
end

# 3. RSS 2.0
feed_path = File.join(site, "feed.xml")
if File.file?(feed_path)
  begin
    feed = REXML::Document.new(File.read(feed_path))
    rss = feed.root
    error.call("feed.xml", "RSS 2.0 の形になっていません") unless rss&.name == "rss" && rss.attributes["version"] == "2.0"
    channel = rss&.elements&.[]("channel")
    %w(title link description).each do |name|
      error.call("feed.xml", "channel に #{name} がありません") if channel&.elements&.[](name)&.text.to_s.strip.empty?
    end
    items = channel ? channel.get_elements("item") : []
    expected = [published.size, feed_limit].min
    error.call("feed.xml", "記事が #{items.size} 件しかありません(#{expected} 件のはず)") if items.size != expected
    items.each_with_index do |item, i|
      %w(title link guid pubDate description).each do |name|
        error.call("feed.xml", "#{i + 1} 件目に #{name} がありません") if item.elements[name].nil?
      end
      link = item.elements["link"]&.text.to_s
      error.call("feed.xml", "#{i + 1} 件目のリンクが公開先の URL ではありません: #{link}") unless link.start_with?(site_root_url)
      begin
        Time.rfc2822(item.elements["pubDate"]&.text.to_s)
      rescue ArgumentError
        error.call("feed.xml", "#{i + 1} 件目の pubDate が正しい日時ではありません")
      end
    end
  rescue REXML::ParseException => e
    error.call("feed.xml", "XML として読めません: #{e.message.lines.first.strip}")
  end
end

# 4. 検索用データ
search_path = File.join(site, "search.json")
if File.file?(search_path)
  begin
    entries = JSON.parse(File.read(search_path))
    if !entries.is_a?(Array)
      error.call("search.json", "配列になっていません")
    else
      error.call("search.json", "記事が #{entries.size} 件です(#{published.size} 件のはず)") if entries.size != published.size
      entries.each_with_index do |entry, i|
        %w(title url date tags categories content).each do |key|
          error.call("search.json", "#{i + 1} 件目に #{key} がありません") unless entry.is_a?(Hash) && entry.key?(key)
        end
        url = entry.is_a?(Hash) ? entry["url"].to_s : ""
        error.call("search.json", "#{i + 1} 件目の url が #{base_path}/ で始まっていません") unless url.start_with?("#{base_path}/")
      end
    end
  rescue JSON::ParserError => e
    error.call("search.json", "JSON として読めません: #{e.message.lines.first.strip}")
  end
end

# 5. サイトマップ
sitemap_path = File.join(site, "sitemap.xml")
if File.file?(sitemap_path)
  begin
    sitemap = REXML::Document.new(File.read(sitemap_path))
    locs = REXML::XPath.match(sitemap, "//*[local-name()='loc']").map { |loc| loc.text.to_s }
    error.call("sitemap.xml", "URL がありません") if locs.empty?
    locs.each do |loc|
      error.call("sitemap.xml", "公開先の URL ではありません: #{loc}") unless loc.start_with?(site_root_url)
    end
  rescue REXML::ParseException => e
    error.call("sitemap.xml", "XML として読めません: #{e.message.lines.first.strip}")
  end
end

# 6. サイト内リンク・画像の参照先があるか(サブパス公開でも壊れないか)
html_files = Dir.glob("**/*.html", base: site).sort
ids_cache = {}
ids_in = lambda do |file|
  ids_cache[file] ||= File.read(File.join(site, file)).scan(/\sid="([^"]*)"/).flatten.map { |id| CGI.unescapeHTML(id) }
end
resolve = lambda do |path|
  candidates = path.end_with?("/") ? ["#{path}index.html"] : [path, "#{path}/index.html"]
  candidates.map { |c| c.delete_prefix("/") }.find { |c| File.file?(File.join(site, c)) }
end

html_files.each do |file|
  page_dir = "/#{File.dirname(file)}/".sub(%r{/\./\z}, "/")
  File.read(File.join(site, file)).scan(/\s(?:href|src)="([^"]*)"/).flatten.each do |raw|
    link = CGI.unescapeHTML(raw)
    next if link.empty? || link.match?(%r{\A(?:[a-z][a-z0-9+.-]*:|//)}i)

    target, fragment = link.split("#", 2)
    target = target.split("?", 2).first.to_s
    if target.empty?
      target_file = file
    elsif target.start_with?("/")
      unless target == base_path || target.start_with?("#{base_path}/")
        error.call(file, "#{link} は #{base_path}/ で始まっていません(公開先で壊れます)")
        next
      end
      target_file = resolve.call(URI.decode_www_form_component(target.delete_prefix(base_path)).then { |t| t.empty? ? "/" : t })
    else
      target_file = resolve.call(File.expand_path(URI.decode_www_form_component(target), page_dir))
    end

    if target_file.nil?
      error.call(file, "リンク先がありません: #{link}")
    elsif fragment && !fragment.empty? && target_file.end_with?(".html")
      id = URI.decode_www_form_component(fragment)
      error.call(file, "リンク先 #{target_file} に ##{id} がありません") unless ids_in.call(target_file).include?(id)
    end
  end
end

# 7. 秘密情報が紛れ込んでいないか
SECRET_PATTERNS = {
  "GitHub のトークン" => /\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b/,
  "秘密鍵" => /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
  "AWS のアクセスキー" => /\bAKIA[0-9A-Z]{16}\b/,
  "Slack のトークン" => /\bxox[abposr]-[A-Za-z0-9-]{10,}\b/
}.freeze
Dir.glob("**/*", base: site).each do |file|
  path = File.join(site, file)
  next unless File.file?(path)

  content = File.read(path, mode: "rb")
  SECRET_PATTERNS.each do |label, pattern|
    error.call(file, "#{label}らしき文字列が含まれています") if content.match?(pattern)
  end
end

if errors.empty?
  puts "サイトの検査: HTML #{html_files.size} ファイル、記事 #{published.size} 件、問題なし"
  exit 0
end

errors.each do |file, message|
  if ENV["GITHUB_ACTIONS"] == "true"
    puts "::error title=サイトの検査::#{file}: #{message}"
  else
    puts "#{file}: #{message}"
  end
end
warn "サイトの検査: #{errors.size} 件の問題があります"
exit 1
