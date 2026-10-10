# frozen_string_literal: true

# 記事ファイル(_posts)を読み込み、書式の決まりを検査する。
# Ruby の標準ライブラリだけを使う(GitHub Actions のランナーに最初から入っている)。

require "date"
require "yaml"

module BlogPosts
  FILENAME = /\A(\d{4})-(\d{2})-(\d{2})-([a-z0-9]+(?:-[a-z0-9]+)*)\.(md|markdown)\z/.freeze
  FRONT_MATTER = /\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|\z)/m.freeze
  TIMEZONE_SUFFIX = /(?:[+-]\d{2}:?\d{2}|Z)\z/.freeze
  RAW_BLOCK = /\{%-?\s*raw\s*-?%\}.*?\{%-?\s*endraw\s*-?%\}/m.freeze
  LIQUID = /\{\{|\{%/.freeze
  # 画像などのリンクに使う {{ '/assets/...' | relative_url }} だけは許可する
  ALLOWED_LIQUID = /\{\{\s*(['"])[^'"{}]+\1\s*\|\s*relative_url\s*\}\}/.freeze
  DANGEROUS_HTML = /<\s*(?:script|iframe|object|embed|form|style|meta|link|base)\b|\son[a-z]+\s*=|javascript:/i.freeze
  FENCED_CODE = /^(```|~~~).*?^\1/m.freeze
  INLINE_CODE = /`[^`\n]*`/.freeze
  DISCUSSION_URL = %r{\Ahttps://github\.com/[\w.-]+/[\w.-]+/discussions/\d+\z}.freeze
  # _config.yml の timezone: Asia/Tokyo に合わせる
  SITE_UTC_OFFSET = "+09:00"
  KNOWN_KEYS = %w(
    layout title date description tags categories published discussion_url
    allow_liquid allow_html last_modified_at
  ).freeze

  Post = Struct.new(:path, :slug, :data, :body, :errors, keyword_init: true) do
    def published?
      data.is_a?(Hash) && data["published"] != false
    end

    # 公開 URL のパス(baseurl を除く)。permalink: /posts/:year/:month/:day/:title/
    def url_path
      time = data["date"].getlocal(SITE_UTC_OFFSET)
      format("/posts/%<y>04d/%<m>02d/%<d>02d/%<slug>s/", y: time.year, m: time.month, d: time.day, slug: slug)
    end
  end

  module_function

  def load(root)
    dir = File.join(root, "_posts")
    return [] unless File.directory?(dir)

    posts = Dir.children(dir).sort.reject { |name| name == ".gitkeep" }.map do |name|
      read(File.join(dir, name), File.join("_posts", name))
    end
    check_duplicate_slugs(posts)
    check_term_slugs(posts)
    posts
  end

  # Jekyll 3.10 の slugify(既定モード)と同じ変換。タグ・カテゴリのページ内リンク(#tag-...)に使われる
  def slugify(text)
    text.gsub(/[^[:alnum:]]+/, "-").gsub(/^-|-$/, "").downcase
  end

  def read(full_path, path)
    name = File.basename(path)
    errors = []
    post = Post.new(path: path, slug: nil, data: nil, body: "", errors: errors)

    if File.directory?(full_path)
      errors << "_posts の中にフォルダは置けません"
      return post
    end

    match = FILENAME.match(name)
    unless match
      errors << "ファイル名は「YYYY-MM-DD-英小文字や数字とハイフン.md」の形にしてください(例: 2026-10-09-first-post.md)"
      return post
    end
    post.slug = match[4]

    text = File.read(full_path, mode: "rb").force_encoding(Encoding::UTF_8)
    unless text.valid_encoding?
      errors << "文字コードを UTF-8 にしてください"
      return post
    end
    text = text.delete_prefix("﻿")

    front = FRONT_MATTER.match(text)
    unless front
      errors << "先頭に --- で囲んだ Front Matter(title や date)がありません"
      return post
    end
    post.body = text[front.end(0)..] || ""

    begin
      data = YAML.safe_load(front[1], permitted_classes: [Date, Time], aliases: false)
    rescue Psych::Exception => e
      errors << "Front Matter を読めません: #{e.message.lines.first.strip}"
      return post
    end
    unless data.is_a?(Hash)
      errors << "Front Matter は「名前: 値」の形で書いてください"
      return post
    end
    post.data = data

    check_front_matter(post, front[1], match)
    check_body(post)
    post
  end

  def check_front_matter(post, raw, filename_match)
    data = post.data
    errors = post.errors

    (data.keys - KNOWN_KEYS).each do |key|
      errors << "Front Matter に知らない項目「#{key}」があります(書き間違いがないか確かめてください)"
    end

    title = data["title"]
    errors << "title(タイトル)が必要です" unless title.is_a?(String) && !title.strip.empty?

    raw_date = raw[/^date:[ \t]*(.+?)[ \t]*$/, 1].to_s.delete("\"'")
    date = data["date"]
    if !date.is_a?(Time)
      errors << "date(公開日時)を「2026-10-09 12:00:00 +0900」の形で書いてください"
    elsif !raw_date.match?(TIMEZONE_SUFFIX)
      errors << "date にタイムゾーン(例: +0900)を付けてください"
    else
      file_date = filename_match[1..3].join("-")
      local_date = date.getlocal(SITE_UTC_OFFSET).strftime("%Y-%m-%d")
      if local_date != file_date
        errors << "date の日付(日本時間で #{local_date})とファイル名の日付(#{file_date})が違います"
      end
    end

    %w(tags categories).each do |key|
      value = data[key]
      next if value.nil?

      unless value.is_a?(Array) && value.all? { |item| item.is_a?(String) && !item.strip.empty? }
        errors << "#{key} は「- 名前」を1行ずつ並べるリストで書いてください"
      end
    end

    if data.key?("description") && !data["description"].is_a?(String)
      errors << "description は文字で書いてください"
    end
    if data.key?("layout") && data["layout"] != "post"
      errors << "layout は書かないか、post にしてください"
    end
    %w(published allow_liquid allow_html).each do |key|
      if data.key?(key) && ![true, false].include?(data[key])
        errors << "#{key} は true か false にしてください"
      end
    end
    url = data["discussion_url"]
    if !url.nil? && !(url.is_a?(String) && url.match?(DISCUSSION_URL))
      errors << "discussion_url は https://github.com/持ち主/リポジトリ/discussions/番号 の形にしてください"
    end
  end

  def check_body(post)
    body = post.body
    unless post.data["allow_liquid"] == true
      rest = body.gsub(RAW_BLOCK) { |block| "\n" * block.count("\n") }.gsub(ALLOWED_LIQUID, "")
      if (index = rest.index(LIQUID))
        line = rest[0...index].count("\n") + 1
        post.errors << "本文 #{line} 行目付近に {{ または {% があります。そのまま載せたい場合は {% raw %} と {% endraw %} で囲んでください"
      end
    end
    unless post.data["allow_html"] == true
      prose = body.gsub(FENCED_CODE, "").gsub(INLINE_CODE, "")
      if (found = prose[DANGEROUS_HTML])
        post.errors << "本文に危険なおそれのある HTML(#{found.strip})があります。コードとして見せたい場合は ``` で囲んでください"
      end
    end
  end

  # 別々のタグ(例: C++ と C#)が同じリンク先になってしまわないかを調べる
  def check_term_slugs(posts)
    { "tags" => "タグ", "categories" => "カテゴリ" }.each do |key, label|
      owners = Hash.new { |hash, slug| hash[slug] = Hash.new { |h, name| h[name] = [] } }
      posts.each do |post|
        next unless post.data.is_a?(Hash) && post.data[key].is_a?(Array)

        post.data[key].each do |name|
          next unless name.is_a?(String)

          slug = slugify(name)
          if slug.empty?
            post.errors << "#{label}「#{name}」には文字か数字を入れてください"
          else
            owners[slug][name] << post
          end
        end
      end
      owners.each_value do |names|
        next if names.size < 2

        names.each do |name, owner_posts|
          others = (names.keys - [name]).map { |n| "「#{n}」" }.join("")
          owner_posts.uniq.each do |post|
            post.errors << "#{label}「#{name}」は#{others}と区別できません(英数字以外の記号は無視されます)。名前を変えてください"
          end
        end
      end
    end
  end

  def check_duplicate_slugs(posts)
    posts.select(&:slug).group_by(&:slug).each_value do |same|
      next if same.size < 2

      same.each do |post|
        others = (same - [post]).map(&:path).join(", ")
        post.errors << "ファイル名の後半(#{post.slug})が #{others} と同じです。別の名前にしてください"
      end
    end
  end
end
