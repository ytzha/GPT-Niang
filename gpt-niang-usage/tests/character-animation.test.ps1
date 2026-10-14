param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$appSource=Split-Path $TestRoot -Parent
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('gpt-niang-animation-'+[Guid]::NewGuid().ToString('N'))
$testApp=Join-Path $testRoot 'app'
$assetRoot=Join-Path $testApp 'assets\pixel-dragon'
$stateDir=Join-Path $testRoot 'state'
$null=New-Item -ItemType Directory -Path $assetRoot -Force
$null=New-Item -ItemType Directory -Path $stateDir -Force
function Assert($condition,[string]$message){if(!$condition){throw $message}}
try{
  $sourceAssets=Join-Path $appSource 'assets\pixel-dragon'
  Copy-Item -LiteralPath (Join-Path $sourceAssets 'idle.json') -Destination $assetRoot
  foreach($i in 1..9){$name=('idle-{0:d2}.png' -f $i);Copy-Item -LiteralPath (Join-Path $sourceAssets $name) -Destination $assetRoot}
  . (Join-Path $appSource 'runtime\character-animation.ps1')
  $script:appDir=$testApp;$script:dataDir=$stateDir
  $legacy=Read-WidgetCharacterActions $testApp
  Assert ($legacy.idle.Frames.Count-eq 9 -and $legacy.idle.Playback-eq 'loop') 'Legacy registry fallback failed'
  [IO.File]::WriteAllText((Join-Path $assetRoot 'animations.json'),'{bad json',[Text.UTF8Encoding]::new($false))
  $corruptFallback=Read-WidgetCharacterActions $testApp
  Assert ($corruptFallback.ContainsKey('idle')) 'Corrupt registry did not fall back to legacy idle'
  $null=New-Item -ItemType Directory -Path (Join-Path $assetRoot 'press') -Force
  foreach($i in 1..2){$name=('idle-{0:d2}.png' -f $i);Copy-Item -LiteralPath (Join-Path $sourceAssets $name) -Destination (Join-Path $assetRoot 'press')}
  $pressManifest=@{width=192;height=192;anchor=@{x=85;y=184};frames=@(@{file='idle-01.png';durationMs=40},@{file='idle-02.png';durationMs=60})}
  [IO.File]::WriteAllText((Join-Path $assetRoot 'press\press.json'),($pressManifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  $registry=@{schemaVersion=1;defaultAction='idle';actions=@{idle=@{manifest='idle.json';playback='loop'};press=@{manifest='press/press.json';playback='once'};drag=@{manifest='press/press.json';playback='loop'};click=@{manifest='press/press.json';playback='once'};complete=@{manifest='press/press.json';playback='once'}}}
  [IO.File]::WriteAllText((Join-Path $assetRoot 'animations.json'),($registry|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $actions=Read-WidgetCharacterActions $testApp
  Assert ($actions.idle.Frames.Count-eq 9) 'Variable-frame idle was not accepted'
  Assert ($actions.press.Frames.Count-eq 2 -and $actions.press.Frames[1].Duration-eq 60) 'Variable frame timing was not loaded'
  Assert ($actions.drag.Playback-eq 'loop') 'Registered drag action playback is incorrect'
  $registry.actions.press.manifest='press\missing.json'
  [IO.File]::WriteAllText((Join-Path $assetRoot 'animations.json'),($registry|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $withoutPress=Read-WidgetCharacterActions $testApp
  Assert ($withoutPress.ContainsKey('idle') -and !$withoutPress.ContainsKey('press')) 'Broken optional action was not isolated'
  $registry.actions.press.manifest='press.json'
  $pressManifest.frames=@(@{file='..\..\outside.png';durationMs=40})
  [IO.File]::WriteAllText((Join-Path $assetRoot 'press\press.json'),($pressManifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $assetRoot 'animations.json'),($registry|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $safePaths=Read-WidgetCharacterActions $testApp
  Assert (!$safePaths.ContainsKey('press')) 'Path traversal action was accepted'
  $pressManifest.frames=@(@{file='idle-01.png';durationMs=39})
  [IO.File]::WriteAllText((Join-Path $assetRoot 'press\press.json'),($pressManifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  $badTiming=Read-WidgetCharacterActions $testApp
  Assert (!$badTiming.ContainsKey('press')) 'Out-of-range duration was accepted'
  $badIdle=@{width=192;height=192;anchor=@{x=85;y=184};frames=@()}
  [IO.File]::WriteAllText((Join-Path $assetRoot 'idle.json'),($badIdle|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  $failure=$null
  try{Read-WidgetCharacterActions $testApp|Out-Null}catch{$failure=$_.Exception.Message}
  Assert ($failure) 'An invalid required idle was not rejected'
  Copy-Item -LiteralPath (Join-Path $sourceAssets 'idle.json') -Destination (Join-Path $assetRoot 'idle.json') -Force
  $registry.actions.press.manifest='press/press.json'
  $pressManifest.frames=@(@{file='idle-01.png';durationMs=40},@{file='idle-02.png';durationMs=60})
  [IO.File]::WriteAllText((Join-Path $assetRoot 'press\press.json'),($pressManifest|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText((Join-Path $assetRoot 'animations.json'),($registry|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  $script:window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $appSource 'widget.xaml'),[Text.Encoding]::UTF8))
  $script:ui=@{Girl=$script:window.FindName('Girl')}
  $script:bitmap=[Windows.Media.Imaging.BitmapImage]::new([Uri](Join-Path $appSource 'assets\gpt-dragon-niang-bust.png'))
  $script:characterMode='pixel';$script:runtimeClosed=$false
  function Pump([int]$milliseconds){
    $frame=[Windows.Threading.DispatcherFrame]::new();$timer=[Windows.Threading.DispatcherTimer]::new()
    $timer.Interval=[TimeSpan]::FromMilliseconds($milliseconds)
    $timer.Tag=$frame;$timer.Add_Tick({param($t,$e)$t.Stop();$t.Tag.Continue=$false});$timer.Start()
    [Windows.Threading.Dispatcher]::PushFrame($frame)
  }
  Initialize-WidgetCharacter;$script:window.Show();Pump 80
  Assert ($script:characterAnimation.CurrentAction-eq 'idle' -and $script:characterAnimation.Clips.idle.Frames.Count-eq 9) 'Registered idle did not start'
  Assert ($script:alphaPixels[3]-eq 0 -and $script:alphaPixels[(54*192+84)*4+3]-eq 255) 'Frame alpha cache was not updated'
  $state=$script:characterAnimation
  foreach($id in @('press','drag','click','complete')){
    $frames=@((New-WidgetCharacterFrame $state.Frames[0].Bitmap 40),(New-WidgetCharacterFrame $state.Frames[1].Bitmap 40))
    $playback=if($id-in @('press','drag')){'loop'}else{'once'}
    $state.Clips[$id]=@{Id=$id;Frames=$frames;Playback=$playback}
  }
  $null=Set-WidgetCharacterInteraction 'press'
  Assert ($state.CurrentAction-eq 'press' -and $state.Timer.IsEnabled) 'Press action did not start'
  $null=Set-WidgetCharacterInteraction 'drag'
  Assert ($state.CurrentAction-eq 'drag' -and $state.Pressed) 'Drag did not take priority over press'
  $null=Set-WidgetCharacterInteraction 'idle' -Click $true
  Assert ($state.CurrentAction-eq 'click' -and !$state.Pressed) 'Click did not start after release'
  $null=Request-WidgetCharacterAction 'complete' -Success $true
  $null=Request-WidgetCharacterAction 'complete' -Success $true
  Assert ($state.CompletePending) 'Completion was not queued during click'
  Advance-WidgetCharacterAnimation
  Assert ($state.CurrentAction-eq 'click' -and $state.Index-eq 1) 'Click did not advance its frames'
  Advance-WidgetCharacterAnimation
  Assert ($state.CurrentAction-eq 'complete' -and !$state.CompletePending) ('Queued completion did not play once after click: action='+$state.CurrentAction+', pending='+$state.CompletePending+', index='+$state.Index+', timer='+$state.Timer.IsEnabled)
  Advance-WidgetCharacterAnimation;Advance-WidgetCharacterAnimation
  Assert ($state.CurrentAction-eq 'idle') 'One-shot completion did not return to idle'
  $state.Clips.press.Playback='once'
  $null=Set-WidgetCharacterInteraction 'press';Advance-WidgetCharacterAnimation;Advance-WidgetCharacterAnimation
  Assert ($state.CurrentAction-eq 'press' -and !$state.Timer.IsEnabled -and $state.Finished) 'Single-shot press did not hold its last frame'
  $null=Set-WidgetCharacterInteraction 'idle'
  Assert ($state.CurrentAction-eq 'idle' -and !$state.Finished) 'Press release did not restore idle'
  $script:window.Hide()
  $null=Request-WidgetCharacterAction 'complete' -Success $true
  Assert ($state.CompletePending -and !$state.Timer.IsEnabled) 'Hidden completion was not deferred'
  $script:window.Show()
  Assert ($state.CurrentAction-eq 'complete' -and $state.Timer.IsEnabled) 'Showing the widget did not resume a deferred completion'
  Advance-WidgetCharacterAnimation;Advance-WidgetCharacterAnimation
  Assert ($state.CurrentAction-eq 'idle') 'Resumed completion did not return to idle'
  $null=Set-WidgetCharacterInteraction 'press'
  $null=Request-WidgetCharacterAction 'complete' -Success $true
  $null=Set-WidgetCharacterInteraction 'idle'
  Assert ($state.CurrentAction-eq 'complete' -and !$state.CompletePending) 'Interaction-end completion did not play'
  $null=Set-WidgetCharacterMode 'original'
  Assert ($script:characterMode-eq 'original' -and !$state.CompletePending) 'Switching to original mode did not clear queued animation'
  $null=Request-WidgetCharacterAction 'complete' -Success $true
  Assert (!$state.CompletePending) 'Original mode accepted a pixel completion action'
  $null=Set-WidgetCharacterMode 'pixel'
  Assert ($script:characterMode-eq 'pixel') 'Pixel mode did not reload animations'
  Stop-WidgetCharacterAnimation;$script:window.Close()
  Write-Output 'PASS: registry compatibility, variable clips, safe paths, optional fallback, interaction priority, one-shot completion, hidden pause and alpha synchronization'
}finally{
  if($script:window){try{Stop-WidgetCharacterAnimation;$script:window.Close()}catch{}}
  $resolved=[IO.Path]::GetFullPath($testRoot)
  $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
  if(!$resolved.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved)-notlike 'gpt-niang-animation-*'){throw 'Unsafe animation-test cleanup path.'}
  if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
