"""Only supplement the real opening-comment observation; no dialogue/UI rerun."""
from pathlib import Path

source = Path(__file__).with_name('x33_experiment.py').read_text()
exec(source.split('\ntry:\n    launch(0)', 1)[0])
evidence = evidence/'public-cache'
evidence.mkdir(exist_ok=True)

try:
    import hashlib
    import xml.etree.ElementTree as ET
    import zlib
    # Public series catalogue verifies that this CID belongs to episode 1.
    catalogue_url = 'https://api.bilibili.com/pgc/view/web/season?season_id=44813'
    with urllib.request.urlopen(urllib.request.Request(catalogue_url, headers={'User-Agent': 'Mozilla/5.0'}), timeout=20) as response:
        catalogue = json.load(response)
    first = catalogue['result']['episodes'][0]
    assert first['cid'] == 1034761585 and first['title'] == '1'
    pool_url = f'https://comment.bilibili.com/{first["cid"]}.xml'
    # Acquisition is an experiment input; the app imports the saved pool using its existing client/parser.
    # A public pool was already acquired during source diagnosis; do not fetch it twice.
    acquired = Path('/tmp/nipa-next/x33-public/episode-1.xml')
    raw = acquired.read_bytes()
    pool = ET.fromstring(raw).findall('d')
    comments = media/'episode-1.xml'
    comments.write_bytes(raw)
    (evidence/'episode-1.xml').write_bytes(raw)
    record('public-source', {'title': catalogue['result']['title'], 'episode': first['title'], 'episodeTitle': first['long_title'],
        'cid': first['cid'], 'bvid': first['bvid'], 'catalogueUrl': catalogue_url, 'poolUrl': pool_url,
        'sha256': hashlib.sha256(raw).hexdigest(), 'entries': len(pool),
        'openingEntries': sum(float(v.get('p').split(',')[0]) < 180 for v in pool)})
    title, anime_id, episode_id = catalogue['result']['title'], 33002, 3300201
    fixture = media/'episode-1.mkv'
    fixture.write_bytes(b'X33 projection fixture; not video\n')
    schema = (workspace/'lib/models/watch_history_database.dart').read_text().split('CREATE TABLE watch_history(', 1)[1].split("''');", 1)[0]
    with sqlite3.connect(root/'data/watch_history.db') as db:
        db.execute('CREATE TABLE watch_history('+schema)
        db.execute('PRAGMA user_version=2')
        db.execute('INSERT INTO watch_history(file_path,anime_name,episode_title,anime_id,episode_id,watch_progress,last_position,duration,last_watch_time,is_from_scan) VALUES(?,?,?,?,?,?,?,?,?,?)',
            (str(fixture), title, '第 1 集 '+first['long_title'], anime_id, episode_id, 0, 0, 100000, '2026-10-12T00:00:00', 1))
    launch(0)
    call('media.library.import_history', {})
    work_id = call('state.query', {'view': 'library.works'})['rows'][0]['workId']
    episodes = ui('episodes', workId=work_id)
    call('danmaku.import', {'filePath': str(comments), 'platform': 'bilibili', 'platformVideoId': str(first['cid']),
        'entityId': episodes[0]['episodeId'], 'note': '公开第一集弹幕缓存'})
    work = ui('work', workId=work_id)
    record('real-opening-comments', {'title': work['title'], 'danmaku': work['danmaku']})
    matches = []
    for text in work['danmaku']:
        comment = next(v for v in pool if ' '.join((v.text or '').split()) == text)
        t = float(comment.get('p').split(',')[0])
        assert t < 180 and t < 100
        matches.append({'text': text, 'timeSeconds': t})
    record('verified-source-matches', matches)
    assert len(matches) == 6
finally:
    try:
        stop()
    finally:
        server.shutdown()
        server.server_close()
        shutil.rmtree(root)
        shutil.rmtree('/tmp/nipa-next/x33-public')
        record('cleanup', {'pids': [p.pid for p in apps], 'processesExited': all(p.poll() is not None for p in apps), 'profileRemoved': not root.exists()})
