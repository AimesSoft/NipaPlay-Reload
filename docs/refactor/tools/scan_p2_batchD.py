import json
import os
import re

BS = chr(92)
BANNED_IMPORT = re.compile(
    r"package:nipaplay/(providers|services|plugins|pages|controllers|player_menu|downloads|search|settings)/"
    r"|package:nipaplay/utils/(globals|video_player_state|storage_service|subtitle_manager|decoder_manager|player_kernel_manager)"
    r"|package:nipaplay/(danmaku_gpu|danmaku_dfm)/"
    r"|package:nipaplay/player_abstraction/(player_factory|player_abstraction)")
BANNED_SYMBOL = re.compile(
    r"\b(FocusNode|GestureDetector|onFocusChange|onKeyEvent|RawKeyboard|HardwareKeyboard"
    r"|KeyboardListener|Listener\(|onPointerDown|onPointerMove|onPointerUp|onPointerCancel"
    r"|Shortcuts\(|FocusScope|requestFocus|autofocus)\b")
KNOWN_A = {
    'lib/themes/nipaplay/widgets/typing_text.dart',
    'lib/themes/nipaplay/widgets/bounce_hover_scale.dart',
    'lib/themes/nipaplay/widgets/transparent_page_route.dart',
    'lib/themes/nipaplay/widgets/control_shadow.dart',
    'lib/themes/nipaplay/widgets/custom_refresh_indicator.dart',
    'lib/themes/nipaplay/widgets/settings_no_ripple_theme.dart',
    'lib/themes/nipaplay/widgets/large_screen_mode_scope.dart',
}

candidates = []
for dp, _, fns in os.walk('lib/themes'):
    for fn in fns:
        if not fn.endswith('.dart'):
            continue
        full = os.path.join(dp, fn).replace(BS, '/')
        text = open(full, encoding='utf-8', errors='replace').read()
        if BANNED_IMPORT.search(text):
            continue
        if BANNED_SYMBOL.search(text):
            continue
        candidates.append(full)

candidates = [c for c in candidates if '/cupertino/' not in c and not c.endswith('theme_registry.dart')]
print('候选总数:', len(candidates))
for c in sorted(KNOWN_A - set(candidates)):
    print('!! 盘点认定的 A 级被过滤:', c)
for c in sorted(candidates):
    print(' ', c)
json.dump(sorted(candidates), open('docs/refactor/tools/p2-batchD-candidates.json', 'w'), indent=1)
