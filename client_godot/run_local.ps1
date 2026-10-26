$ErrorActionPreference = 'Stop'
$env:MIR2X_WORLD_RES = Join-Path $PSScriptRoot 'build/world_res'
$env:MIR2X_TEXTURE_RES = Join-Path $PSScriptRoot '../build/Release/res/texture'
$env:MIR2X_AUDIO_RES = Join-Path $PSScriptRoot 'build/audio'
$godotExecutable = (Get-Command 'Godot_v4.7.2-stable_win64.exe' -ErrorAction Stop).Source
Start-Process -FilePath $godotExecutable -ArgumentList @('--path', ('"{0}"' -f $PSScriptRoot)) -WorkingDirectory $PSScriptRoot -RedirectStandardOutput (Join-Path $PSScriptRoot 'build/client.stdout.log') -RedirectStandardError (Join-Path $PSScriptRoot 'build/client.stderr.log') -PassThru
