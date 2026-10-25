# Preferences of a fresh winlab profile: Next consent (Labs) and the Next interface on; and the mesh off
# (data\next\mesh.json {"enabled": false}), so an experiment instance never registers itself with the official
# device network service, whatever the build's default is.
param([string]$Profile = 'winlab')
$root = "D:\nipaplay-next\win-next\lab\$Profile"
New-Item -ItemType Directory -Force $root, "$root\data\next" | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
$prefs = '{"flutter.labs_enable_agent_endpoint":true,"flutter.labs_use_next_interface":true}'
[System.IO.File]::WriteAllText("$root\preferences.json", $prefs, $utf8)
[System.IO.File]::WriteAllText("$root\data\next\mesh.json", '{"enabled": false}', $utf8)
"seeded $root\preferences.json and data\next\mesh.json"
