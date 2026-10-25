# Preferences of a fresh winlab profile: Next consent (Labs) and the Next interface on.
param([string]$Profile = 'winlab')
$root = "D:\nipaplay-next\win-next\lab\$Profile"
New-Item -ItemType Directory -Force $root | Out-Null
$prefs = '{"flutter.labs_enable_agent_endpoint":true,"flutter.labs_use_next_interface":true}'
[System.IO.File]::WriteAllText("$root\preferences.json", $prefs, (New-Object System.Text.UTF8Encoding $false))
"seeded $root\preferences.json"
