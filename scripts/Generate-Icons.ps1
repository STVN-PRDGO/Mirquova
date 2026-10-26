# Original geometric M mark, generated independently for this prototype.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class MirquovaIconHandle {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool DestroyIcon(IntPtr handle);
}
"@
$projectRoot = Split-Path -Parent $PSScriptRoot
function New-Mark([int]$Size) {
    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#215C45'))
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, ($Size * 0.085))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $points = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF(($Size * 0.25), ($Size * 0.70))),
        (New-Object System.Drawing.PointF(($Size * 0.25), ($Size * 0.30))),
        (New-Object System.Drawing.PointF(($Size * 0.50), ($Size * 0.55))),
        (New-Object System.Drawing.PointF(($Size * 0.75), ($Size * 0.30))),
        (New-Object System.Drawing.PointF(($Size * 0.75), ($Size * 0.70)))
    )
    $graphics.DrawLines($pen, $points)
    $pen.Dispose(); $graphics.Dispose()
    return ,$bitmap
}
$sizes = @{ 'mdpi'=48; 'hdpi'=72; 'xhdpi'=96; 'xxhdpi'=144; 'xxxhdpi'=192 }
foreach ($density in $sizes.Keys) {
    $bitmap = New-Mark $sizes[$density]
    try { $bitmap.Save((Join-Path $projectRoot "apps/mirquova_flutter/android/app/src/main/res/mipmap-$density/ic_launcher.png"), [System.Drawing.Imaging.ImageFormat]::Png) }
    finally { $bitmap.Dispose() }
}
$bitmap = New-Mark 256
$handle = $bitmap.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($handle)
$stream = [IO.File]::Create((Join-Path $projectRoot 'apps/mirquova_flutter/windows/runner/resources/app_icon.ico'))
try { $icon.Save($stream) }
finally { $stream.Dispose(); $icon.Dispose(); [MirquovaIconHandle]::DestroyIcon($handle) | Out-Null; $bitmap.Dispose() }
Write-Output 'Generated original Android and Windows prototype icons.'