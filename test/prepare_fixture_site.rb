#!/usr/bin/env ruby
# frozen_string_literal: true

# 使い方: ruby test/prepare_fixture_site.rb <作業用フォルダ>
# リポジトリを作業用フォルダへコピーし、test/fixtures の記事と画像を足す。
# 特殊な文字を含む記事や下書きでサイトが壊れないかを、本番と同じビルドで確かめるために使う。

require "fileutils"

root = File.expand_path("..", __dir__)
dest = File.expand_path(ARGV.fetch(0) { abort "使い方: ruby test/prepare_fixture_site.rb <作業用フォルダ>" })
abort "#{dest} はすでにあります" if File.exist?(dest)

SKIP = %w(.git _site .jekyll-cache vendor).freeze
FileUtils.mkdir_p(dest)
Dir.children(root).each do |name|
  next if SKIP.include?(name) || name.start_with?("_fixture")

  FileUtils.cp_r(File.join(root, name), dest)
end
FileUtils.cp_r(File.join(root, "test", "fixtures", "."), dest)
puts "テスト用サイトの元を作りました: #{dest}"
