"""A library folder with awkward paths: deeper than 260 characters, Chinese, spaces, brackets."""
import os, shutil
base = r'D:\nipaplay-next\win-next\media\awkward'
seg = '番剧 [字幕组] 很长很长的目录名称用来测试路径长度限制 '
deep = base
shutil.rmtree('\\?\\' + base, ignore_errors=True)
for i in range(1, 9):
    deep = os.path.join(deep, seg + str(i))
print('deep path length', len(deep))
long = '\\\\?\\' + deep
os.makedirs(long, exist_ok=True)
lib = r'D:\nipaplay-next\win-next\media\library'
shutil.copyfile(os.path.join(lib, 'Sintel.2010.720p.mkv'), long + '\\[Sintel] 第01话 (720p).mkv')
shutil.copyfile(os.path.join(lib, 'Sintel.2010.720p.zh-Hans.srt'), long + '\\[Sintel] 第01话 (720p).zh-Hans.srt')
short = os.path.join(base, '普通 目录')
os.makedirs(short, exist_ok=True)
shutil.copyfile(os.path.join(lib, 'BigBuckBunny.mp4'), os.path.join(short, 'Big Buck Bunny 【测试】.mp4'))
for root, _, files in os.walk('\\\\?\\' + base):
    for f in files:
        print(len(os.path.join(root, f)) - 4, f)
