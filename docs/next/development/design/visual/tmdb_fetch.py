import json, os, urllib.request, urllib.parse
TOKEN = open('/tmp/nipa-next/tmdb.token').read().split()[0]
OUT = '/tmp/nipa-next/visual/tmdb'
def api(path, **q):
    url = 'https://api.themoviedb.org/3' + path + ('?' + urllib.parse.urlencode(q) if q else '')
    r = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + TOKEN, 'accept': 'application/json'})
    return json.load(urllib.request.urlopen(r, timeout=30))
def img(path, size, name):
    if not path: return None
    dest = f'{OUT}/{name}{os.path.splitext(path)[1]}'
    if not os.path.exists(dest):
        urllib.request.urlretrieve(f'https://image.tmdb.org/t/p/{size}{path}', dest)
    return os.path.basename(dest)
WORKS = [('frieren','tv','葬送的芙莉莲'),('bocchi','tv','孤独摇滚'),('violet','tv','紫罗兰永恒花园'),
         ('lycoris','tv','Lycoris Recoil'),('changan','tv','长安十二时辰'),('kusuriya','tv','药屋少女的呢喃'),
         ('dungeon','tv','迷宫饭'),('oshinoko','tv','我推的孩子'),('spyfamily','tv','间谍过家家'),
         ('edgerunners','tv','赛博朋克：边缘行者'),('sintel','movie','Sintel')]
meta = {}
for key, kind, q in WORKS:
    res = api(f'/search/{kind}', query=q, language='zh-CN')['results']
    if not res: print('未找到', q); continue
    wid = res[0]['id']
    d = api(f'/{kind}/{wid}', language='zh-CN', append_to_response='images', include_image_language='zh,ja,en,null')
    ims = d.get('images', {})
    def pick(lst, langs):
        for l in langs:
            for i in sorted(lst, key=lambda x: -x.get('vote_average', 0)):
                if i.get('iso_639_1') == l: return i['file_path']
        return lst[0]['file_path'] if lst else None
    back = pick(ims.get('backdrops', []), [None, 'ja', 'en', 'zh'])
    logo = pick(ims.get('logos', []), ['zh', 'en', 'ja', None])
    m = {'id': wid, 'kind': kind, 'title': d.get('name') or d.get('title'), 'original': d.get('original_name') or d.get('original_title'),
         'year': (d.get('first_air_date') or d.get('release_date') or '')[:4], 'genres': [g['name'] for g in d.get('genres', [])],
         'rating': d.get('vote_average'), 'votes': d.get('vote_count'), 'overview': d.get('overview'),
         'episodes': d.get('number_of_episodes'), 'seasons': d.get('number_of_seasons'), 'runtime': d.get('runtime'),
         'studio': ([c['name'] for c in d.get('production_companies', [])] or [''])[0],
         'backdrop': img(back, 'w1920_and_h1080_bestv2' if back else '', f'{key}-backdrop') if back else None,
         'backdrop2': img((ims.get('backdrops') or [{}, {}])[1].get('file_path') if len(ims.get('backdrops', []))>1 else None, 'w1280', f'{key}-backdrop2'),
         'poster': img(d.get('poster_path'), 'w500', f'{key}-poster'), 'logo': img(logo, 'w500', f'{key}-logo')}
    if key in ('frieren', 'lycoris') and kind == 'tv':
        s = api(f'/tv/{wid}/season/1', language='zh-CN')
        m['eps'] = [{'n': e['episode_number'], 'name': e.get('name'), 'runtime': e.get('runtime'),
                     'still': img(e.get('still_path'), 'w500', f'{key}-ep{e["episode_number"]}')} for e in s.get('episodes', [])[:12]]
    meta[key] = m
    print(key, '|', m['title'], m['year'], m['rating'], '| 背景', bool(m['backdrop']), '海报', bool(m['poster']), 'Logo', bool(m['logo']), '| 集', len(m.get('eps', [])))
json.dump(meta, open(f'{OUT}/meta.json', 'w'), ensure_ascii=False, indent=1)
