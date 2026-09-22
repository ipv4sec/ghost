# -*- coding: utf-8 -*-
"""从 open.115.com/doc/ 下载全部文档（串行，每个请求间隔 1 秒，避免并发过高）"""
import json
import sys
import time
import urllib.parse
import urllib.request

BASE = 'https://open.115.com'
HEADERS = {
    'Referer': 'https://open.115.com/doc/',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 115Browser/36.0.1 Chromium/125.0',
}
DELAY = 1.0  # 每个请求间隔（秒），串行执行保证并发为 1


def collect_files(node, out):
    if node.get('type') == 'file':
        out.append(node['path'])
    for child in node.get('children', []):
        collect_files(child, out)


def main():
    with open('tree-index.json', encoding='utf-8') as f:
        tree = json.load(f)

    paths = []
    collect_files(tree, paths)
    total = len(paths)
    print('total docs:', total)

    ok, fail = 0, 0
    for i, p in enumerate(paths, 1):
        rel = p[len('/doc/'):]
        url = BASE + urllib.parse.quote(p) + '?raw=true'
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            data = urllib.request.urlopen(req, timeout=30).read()
            # SPA 回退页面特征：返回的是 HTML 而非 markdown
            if data[:20].lstrip().lower().startswith(b'<!doctype') or b'<html' in data[:200].lower():
                raise ValueError('got HTML fallback page')
            with open(rel, 'wb') as f:
                f.write(data)
            ok += 1
            print('[%d/%d] ok  %s (%d bytes)' % (i, total, rel, len(data)))
        except Exception as e:
            fail += 1
            print('[%d/%d] FAIL %s -> %s' % (i, total, rel, e))
        time.sleep(DELAY)

    print('done. ok=%d fail=%d' % (ok, fail))
    sys.exit(1 if fail else 0)


if __name__ == '__main__':
    main()
