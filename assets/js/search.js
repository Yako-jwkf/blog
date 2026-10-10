(function () {
  'use strict';

  var MAX_RESULTS = 50;
  var script = document.currentScript;
  var indexUrl = script && script.getAttribute('data-index');
  var input = document.getElementById('search-input');
  var status = document.getElementById('search-status');
  var results = document.getElementById('search-results');
  if (!indexUrl || !input || !status || !results) return;

  var posts = null;

  // 全角・半角や大文字・小文字の違いをそろえる
  function normalize(text) {
    return String(text || '').normalize('NFKC').toLowerCase();
  }

  function prepare(list) {
    return list.map(function (post, order) {
      var tags = Array.isArray(post.tags) ? post.tags : [];
      var categories = Array.isArray(post.categories) ? post.categories : [];
      return {
        post: post,
        order: order,
        title: normalize(post.title),
        body: normalize([post.content, tags.join(' '), categories.join(' ')].join(' '))
      };
    });
  }

  function setStatus(message) {
    status.textContent = message;
  }

  function render(matches) {
    results.textContent = '';
    matches.slice(0, MAX_RESULTS).forEach(function (entry) {
      var item = document.createElement('li');
      var time = document.createElement('time');
      var parts = String(entry.post.date).split('-');
      time.dateTime = entry.post.date;
      time.textContent = parts.length === 3
        ? parts[0] + '年' + Number(parts[1]) + '月' + Number(parts[2]) + '日'
        : entry.post.date;
      var link = document.createElement('a');
      link.href = entry.post.url;
      link.textContent = entry.post.title;
      item.appendChild(time);
      item.appendChild(link);
      results.appendChild(item);
    });
  }

  function search(query) {
    var terms = normalize(query).split(/\s+/).filter(Boolean);
    if (terms.length === 0) {
      results.textContent = '';
      setStatus('');
      return;
    }
    var matches = posts.filter(function (entry) {
      return terms.every(function (term) {
        return entry.title.indexOf(term) !== -1 || entry.body.indexOf(term) !== -1;
      });
    });
    // タイトルに含まれる記事を先に、その中では新しい順(インデックスの並び)
    matches.sort(function (a, b) {
      var at = terms.every(function (t) { return a.title.indexOf(t) !== -1; }) ? 0 : 1;
      var bt = terms.every(function (t) { return b.title.indexOf(t) !== -1; }) ? 0 : 1;
      return at - bt || a.order - b.order;
    });
    render(matches);
    if (matches.length === 0) {
      setStatus('「' + query + '」に一致する記事は見つかりませんでした。');
    } else if (matches.length > MAX_RESULTS) {
      setStatus(matches.length + ' 件見つかりました(先頭の ' + MAX_RESULTS + ' 件を表示)。');
    } else {
      setStatus(matches.length + ' 件見つかりました。');
    }
  }

  var initial = new URLSearchParams(window.location.search).get('q') || '';
  input.value = initial;
  setStatus('検索の準備をしています…');

  fetch(indexUrl, { credentials: 'same-origin' })
    .then(function (response) {
      if (!response.ok) throw new Error('HTTP ' + response.status);
      return response.json();
    })
    .then(function (data) {
      if (!Array.isArray(data)) throw new Error('invalid index');
      posts = prepare(data);
      setStatus('');
      search(input.value);
      input.addEventListener('input', function () {
        search(input.value);
      });
    })
    .catch(function () {
      setStatus('検索データを読み込めませんでした。時間をおいてページを再読み込みしてください。');
    });
})();
