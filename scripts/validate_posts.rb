#!/usr/bin/env ruby
# frozen_string_literal: true

# 使い方: ruby scripts/validate_posts.rb [リポジトリのフォルダ]
# 記事の書式に問題があれば一覧を表示して、終了コード 1 で終わる。

require_relative "lib/posts"

Encoding.default_external = Encoding::UTF_8

root = File.expand_path(ARGV[0] || File.join(__dir__, ".."))
posts = BlogPosts.load(root)
problems = posts.reject { |post| post.errors.empty? }

if problems.empty?
  puts "記事の検査: #{posts.size} 件、問題なし"
  exit 0
end

problems.each do |post|
  post.errors.each do |message|
    if ENV["GITHUB_ACTIONS"] == "true"
      puts "::error file=#{post.path}::#{message}"
    else
      puts "#{post.path}: #{message}"
    end
  end
end
warn "記事の検査: #{problems.size} 件の記事に問題があります"
exit 1
