param([Parameter(Mandatory=$true)][string]$UsageExe, [switch]$SmokeTest, [string]$ScreenshotPath)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$mutex = [System.Threading.Mutex]::new($false, 'Local\AIUsageBarCornerWidget')
if (-not $mutex.WaitOne(0)) {
    if ($SmokeTest) { throw 'Another corner widget instance prevented the smoke test.' }
    exit
}

$settingsDir = Join-Path $env:LOCALAPPDATA 'ai-usagebar'
$settingsFile = Join-Path $settingsDir 'corner-widget.json'
$displayFile = Join-Path (Join-Path $settingsDir 'widget') 'display.json'
New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
$saved = $null
try { $saved = Get-Content $settingsFile -Raw | ConvertFrom-Json } catch { }

$window = New-Object System.Windows.Window
$window.Title = 'AI Usage corner widget'
$window.WindowStyle = 'None'
$window.ResizeMode = 'NoResize'
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.Topmost = $true
$window.ShowInTaskbar = $false
$window.SizeToContent = 'Manual'
$window.Width = 72
$window.Height = 72
$window.Left = if ($null -ne $saved -and $null -ne $saved.x) { [double]$saved.x } else { [System.Windows.SystemParameters]::WorkArea.Right - 84 }
$window.Top = if ($null -ne $saved -and $null -ne $saved.y) { [double]$saved.y } else { [System.Windows.SystemParameters]::WorkArea.Top + 12 }

$root = New-Object System.Windows.Controls.Grid
$window.Content = $root
$circle = New-Object System.Windows.Controls.Grid
$circle.Width = 72; $circle.Height = 72
$ringBackground = New-Object System.Windows.Shapes.Ellipse
$ringBackground.Width = 68; $ringBackground.Height = 68
$ringBackground.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#171b24')
$ringBackground.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#343a49')
$ringBackground.StrokeThickness = 2
$circle.Children.Add($ringBackground) | Out-Null
$ring = New-Object System.Windows.Shapes.Path
$ring.StrokeThickness = 6
$ring.StrokeStartLineCap = 'Round'; $ring.StrokeEndLineCap = 'Round'
$circle.Children.Add($ring) | Out-Null
$compactText = New-Object System.Windows.Controls.TextBlock
$compactText.Foreground = [System.Windows.Media.Brushes]::White
$compactText.FontFamily = 'Segoe UI'; $compactText.FontSize = 15; $compactText.FontWeight = 'Bold'
$compactText.HorizontalAlignment = 'Center'; $compactText.VerticalAlignment = 'Center'
$circle.Children.Add($compactText) | Out-Null
$root.Children.Add($circle) | Out-Null

$panel = New-Object System.Windows.Controls.Border
$panel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#ffffff')
$panel.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#c9c9c9')
$panel.BorderThickness = 1
$panel.CornerRadius = 8
$panel.Visibility = 'Collapsed'
$panelGrid = New-Object System.Windows.Controls.DockPanel
$panelGrid.Margin = 16
$panel.Child = $panelGrid
$header = New-Object System.Windows.Controls.StackPanel
$header.Margin = '0,0,0,12'
[System.Windows.Controls.DockPanel]::SetDock($header, 'Top')
$panelGrid.Children.Add($header) | Out-Null
$title = New-Object System.Windows.Controls.TextBlock
$title.Text = 'AI Usage'
$title.Foreground = [System.Windows.Media.Brushes]::Black
$title.FontFamily = 'Segoe UI'; $title.FontSize = 17; $title.FontWeight = 'SemiBold'
$header.Children.Add($title) | Out-Null
$subtitle = New-Object System.Windows.Controls.TextBlock
$subtitle.Text = 'Consumo em tempo real'
$subtitle.FontSize = 10
$header.Children.Add($subtitle) | Out-Null
$tabs = New-Object System.Windows.Controls.StackPanel
$tabs.Orientation = 'Horizontal'
$tabsScroll = New-Object System.Windows.Controls.ScrollViewer
$tabsScroll.Content = $tabs
$tabsScroll.HorizontalScrollBarVisibility = 'Auto'
$tabsScroll.VerticalScrollBarVisibility = 'Disabled'
$tabsScroll.Margin = '0,0,0,12'
[System.Windows.Controls.DockPanel]::SetDock($tabsScroll, 'Top')
$panelGrid.Children.Add($tabsScroll) | Out-Null
$scroll = New-Object System.Windows.Controls.ScrollViewer
$scroll.VerticalScrollBarVisibility = 'Auto'
$rows = New-Object System.Windows.Controls.StackPanel
$card = New-Object System.Windows.Controls.Border
$card.CornerRadius = 8
$card.BorderThickness = 1
$card.Padding = 14
$card.VerticalAlignment = 'Top'
$card.Child = $rows
$scroll.Content = $card
$panelGrid.Children.Add($scroll) | Out-Null
$root.Children.Add($panel) | Out-Null

$script:allEntries = @()
$script:entries = @()
$script:display = $null
$script:displayRaw = ''
$script:theme = 'light'
$script:showAs = 'used'
$script:selected = if ($saved) { [string]$saved.provider } else { '' }
$script:expanded = $false
$script:anchorX = $window.Left
$script:anchorY = $window.Top

function Save-Position {
    @{ x=$script:anchorX; y=$script:anchorY; provider=$script:selected } |
        ConvertTo-Json -Compress | Set-Content -Path $settingsFile -Encoding UTF8
}

function Color-Brush([string]$color) {
    [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
}

function Apply-Theme {
    $dark = $script:theme -eq 'dark'
    $panel.Background = Color-Brush $(if ($dark) { '#15171b' } else { '#f7f7f5' })
    $panel.BorderBrush = Color-Brush $(if ($dark) { '#34363c' } else { '#d6d8d6' })
    $card.Background = Color-Brush $(if ($dark) { '#202227' } else { '#ffffff' })
    $card.BorderBrush = Color-Brush $(if ($dark) { '#34363c' } else { '#e2e3e0' })
    $ringBackground.Fill = Color-Brush $(if ($dark) { '#15171b' } else { '#ffffff' })
    $ringBackground.Stroke = Color-Brush $(if ($dark) { '#34363c' } else { '#d6d8d6' })
    $compactText.Foreground = Color-Brush $(if ($dark) { '#f5f5f2' } else { '#242529' })
    $title.Foreground = Color-Brush $(if ($dark) { '#f5f5f2' } else { '#242529' })
    $subtitle.Foreground = Color-Brush $(if ($dark) { '#92969e' } else { '#6a6d72' })
}

function Progress-Brush([double]$percent) {
    if ($percent -gt 80 -or $percent -lt 20) { return Color-Brush '#ff5f57' }
    Color-Brush $(if ($script:theme -eq 'dark') { '#f5f5f2' } else { '#242529' })
}

function Set-Ring([double]$percent) {
    $ring.Stroke = Progress-Brush $percent
    $percent = [Math]::Max(0, [Math]::Min(100, $percent))
    $angle = 2 * [Math]::PI * [Math]::Min(99.99, $percent) / 100
    $start = [System.Windows.Point]::new(36, 8)
    $end = [System.Windows.Point]::new((36 + 28 * [Math]::Sin($angle)), (36 - 28 * [Math]::Cos($angle)))
    $figure = New-Object System.Windows.Media.PathFigure
    $figure.StartPoint = $start
    $arc = New-Object System.Windows.Media.ArcSegment
    $arc.Point = $end; $arc.Size = [System.Windows.Size]::new(28, 28)
    $arc.IsLargeArc = $percent -gt 50
    $arc.SweepDirection = 'Clockwise'
    $figure.Segments.Add($arc)
    $geometry = New-Object System.Windows.Media.PathGeometry
    $geometry.Figures.Add($figure)
    $ring.Data = $geometry
}

function Format-Reset([string]$timestamp) {
    if (-not $timestamp) { return '—' }
    try {
        $remaining = [DateTimeOffset]::Parse($timestamp) - [DateTimeOffset]::UtcNow
        if ($remaining.TotalSeconds -le 0) { return 'Agora' }
        if ($remaining.TotalDays -ge 1) { return ('{0}d {1}h' -f [int][Math]::Floor($remaining.TotalDays), $remaining.Hours) }
        if ($remaining.TotalHours -ge 1) { return ('{0}h {1}min' -f [int][Math]::Floor($remaining.TotalHours), $remaining.Minutes) }
        return ('{0}min' -f [Math]::Max(1, [int][Math]::Ceiling($remaining.TotalMinutes)))
    } catch { return '—' }
}

function Draw-Report {
    $entry = @($script:entries | Where-Object { $_.id -eq $script:selected } | Select-Object -First 1)
    if (-not $entry.Count) {
        $entry = @($script:entries | Where-Object { $_.metrics -and @($_.metrics).Count -gt 0 } | Select-Object -First 1)
    }
    if (-not $entry.Count) { $entry = @($script:entries | Select-Object -First 1) }
    if ($entry.Count -and $script:selected -ne $entry[0].id) {
        $script:selected = [string]$entry[0].id
        Save-Position
    }
    $metric = @($entry[0].metrics | Where-Object { -not $_.group } | Select-Object -First 1)
    if (-not $metric.Count) { $metric = @($entry[0].metrics | Select-Object -First 1) }
    $percent = if ($metric.Count) { [double]$metric[0].percent } else { 0 }
    $shownPercent = if ($script:showAs -eq 'left') { 100 - $percent } else { $percent }
    Set-Ring $shownPercent
    $compactText.Text = if ($metric.Count) { '{0:0}%' -f $shownPercent } else { '—' }
    $compactText.Foreground = Progress-Brush $shownPercent
    $tabsScroll.Visibility = if ($script:entries.Count -gt 1) { 'Visible' } else { 'Collapsed' }
    $tabs.Children.Clear()
    $rows.Children.Clear()
    $dark = $script:theme -eq 'dark'
    $foreground = Color-Brush $(if ($dark) { '#f5f5f2' } else { '#242529' })
    $secondary = Color-Brush $(if ($dark) { '#92969e' } else { '#6a6d72' })
    foreach ($item in $script:entries) {
        $tab = New-Object System.Windows.Controls.Border
        $tab.Tag = [string]$item.id
        $tab.Padding = '8,6,8,6'
        $tab.Margin = '0,0,4,0'
        $tab.CornerRadius = 4
        $tab.Background = Color-Brush $(if ($item.id -eq $script:selected) {
            if ($dark) { '#34363c' } else { '#e8e9e6' }
        } else { '#00ffffff' })
        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text = if ($item.short_name) { [string]$item.short_name } else { [string]$item.name }
        $label.Foreground = if ($item.id -eq $script:selected) { $foreground } else { $secondary }
        $label.FontSize = 11
        $label.FontWeight = if ($item.id -eq $script:selected) { 'SemiBold' } else { 'Normal' }
        $tab.Child = $label
        $tab.Add_MouseLeftButtonDown({
            $script:selected = [string]$this.Tag
            Save-Position
            Draw-Report
        })
        $tabs.Children.Add($tab) | Out-Null
    }
    if (-not $entry.Count) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = 'Nenhum provider ativo em Settings.'
        $empty.Foreground = $foreground
        $empty.TextWrapping = 'Wrap'
        $rows.Children.Add($empty) | Out-Null
        return
    }
    $item = $entry[0]
    $heading = New-Object System.Windows.Controls.TextBlock
    $heading.Text = if ($item.display_name) { [string]$item.display_name } else { [string]$item.name }
    $heading.Foreground = $foreground
    $heading.FontWeight = 'SemiBold'; $heading.FontSize = 13
    $heading.Margin = '0,0,0,12'
    $rows.Children.Add($heading) | Out-Null
    $metrics = @($item.metrics)
    if (-not $metrics.Count) {
        $message = New-Object System.Windows.Controls.TextBlock
        $message.Text = if ($item.error) { [string]$item.error } else { 'Sem métricas disponíveis.' }
        $message.Foreground = $secondary
        $message.TextWrapping = 'Wrap'
        $rows.Children.Add($message) | Out-Null
    }
    foreach ($m in $metrics) {
        $usedPercent = [Math]::Max(0, [Math]::Min(100, [double]$m.percent))
        $meterPercent = if ($script:showAs -eq 'left') { 100 - $usedPercent } else { $usedPercent }
        $line = New-Object System.Windows.Controls.DockPanel
        $line.Margin = '0,2,0,4'
        $value = New-Object System.Windows.Controls.TextBlock
        $value.Text = if ($m.headline -eq 'percent') {
            '{0:0}% {1}' -f $meterPercent, $script:showAs
        } else { [string]$m.value }
        $value.Foreground = Progress-Brush $meterPercent
        $value.FontSize = 11
        [System.Windows.Controls.DockPanel]::SetDock($value, 'Right')
        $line.Children.Add($value) | Out-Null
        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text = [string]$m.label
        $label.Foreground = $foreground
        $label.FontSize = 11
        $line.Children.Add($label) | Out-Null
        $rows.Children.Add($line) | Out-Null
        $bar = New-Object System.Windows.Controls.Grid
        $bar.Width = 256; $bar.Height = 6; $bar.Margin = '0,0,0,4'
        $bar.HorizontalAlignment = 'Left'
        $track = New-Object System.Windows.Controls.Border
        $track.Background = Color-Brush $(if ($dark) { '#34363c' } else { '#e8e9e6' })
        $track.CornerRadius = 3
        $bar.Children.Add($track) | Out-Null
        $fill = New-Object System.Windows.Controls.Border
        $fill.Width = 256 * $meterPercent / 100
        $fill.HorizontalAlignment = 'Left'
        $fill.Background = Progress-Brush $meterPercent
        $fill.CornerRadius = 3
        $bar.Children.Add($fill) | Out-Null
        $rows.Children.Add($bar) | Out-Null
        if ($m.detail -and -not $m.reset_at) {
            $detail = New-Object System.Windows.Controls.TextBlock
            $detail.Text = [string]$m.detail
            $detail.Foreground = $secondary
            $detail.FontSize = 10
            $detail.TextWrapping = 'Wrap'
            $detail.Margin = '0,0,0,10'
            $rows.Children.Add($detail) | Out-Null
        }
    }
    $weekly = @($metrics | Where-Object { $_.window_secs -ge 604800 -or $_.label -match 'weekly|semanal' } | Select-Object -First 1)
    $credits = $item.reset_credits
    if ($weekly.Count -or $null -ne $credits) {
        $stats = New-Object System.Windows.Controls.Grid
        $stats.Margin = '0,12,0,0'
        $stats.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
        $stats.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
        $index = 0
        foreach ($stat in @(
            @{ label='PRÓXIMO RESET'; value=$(if ($weekly.Count) { Format-Reset ([string]$weekly[0].reset_at) } else { '—' }) },
            @{ label='RESETS DISPONÍVEIS'; value=$(if ($null -ne $credits -and $null -ne $credits.available) { [string]$credits.available } else { '—' }) }
        )) {
            $box = New-Object System.Windows.Controls.Border
            $box.Background = Color-Brush $(if ($dark) { '#292b30' } else { '#f4f5f2' })
            $box.CornerRadius = 6
            $box.Padding = '10,8,10,8'
            if ($index -eq 0) { $box.Margin = '0,0,5,0' } else { $box.Margin = '5,0,0,0' }
            [System.Windows.Controls.Grid]::SetColumn($box, $index)
            $content = New-Object System.Windows.Controls.StackPanel
            $caption = New-Object System.Windows.Controls.TextBlock
            $caption.Text = $stat.label; $caption.FontSize = 9; $caption.FontWeight = 'SemiBold'; $caption.Foreground = $secondary
            $number = New-Object System.Windows.Controls.TextBlock
            $number.Text = $stat.value; $number.FontSize = 16; $number.FontWeight = 'SemiBold'; $number.Foreground = $foreground
            $number.Margin = '0,3,0,0'
            $content.Children.Add($caption) | Out-Null
            $content.Children.Add($number) | Out-Null
            $box.Child = $content
            $stats.Children.Add($box) | Out-Null
            $index++
        }
        $rows.Children.Add($stats) | Out-Null
    }
}

function Apply-Display {
    $script:entries = @()
    if ($script:display -and $null -ne $script:display.visible) {
        foreach ($id in @($script:display.visible)) {
            $match = @($script:allEntries | Where-Object { $_.id -eq $id } | Select-Object -First 1)
            if ($match.Count) { $script:entries += $match[0] }
        }
    }
    $script:theme = if ($script:display -and $script:display.theme -eq 'dark') { 'dark' } else { 'light' }
    $script:showAs = if ($script:display -and $script:display.showAs -eq 'left') { 'left' } else { 'used' }
    Apply-Theme
    Draw-Report
    if ($script:expanded) {
        $window.Height = if ($script:entries.Count -gt 1) { 280 } else { 240 }
        $window.Top = [Math]::Max([System.Windows.SystemParameters]::VirtualScreenTop, [Math]::Min($script:anchorY, [System.Windows.SystemParameters]::VirtualScreenTop + [System.Windows.SystemParameters]::VirtualScreenHeight - $window.Height))
    }
    if ($providerMenu) {
        $providerMenu.Items.Clear()
        foreach ($item in $script:entries) {
            $choice = New-Object System.Windows.Controls.MenuItem
            $choice.Header = if ($item.display_name) { $item.display_name } else { $item.name }
            $choice.Tag = [string]$item.id
            $choice.Add_Click({
                $script:selected = [string]$this.Tag
                Save-Position
                Draw-Report
            })
            $providerMenu.Items.Add($choice) | Out-Null
        }
    }
}

function Load-Display {
    try {
        $raw = Get-Content $displayFile -Raw -ErrorAction Stop
        if ($raw -ne $script:displayRaw) {
            $script:display = $raw | ConvertFrom-Json
            $script:displayRaw = $raw
            Apply-Display
        }
    } catch { }
}

function Set-Expanded([bool]$open) {
    if ($script:expanded -eq $open) { return }
    $script:expanded = $open
    if ($open) {
        $circle.Visibility = 'Collapsed'; $panel.Visibility = 'Visible'
        $height = if ($script:entries.Count -gt 1) { 280 } else { 240 }
        $window.Width = 320; $window.Height = $height
        $window.Left = [Math]::Max([System.Windows.SystemParameters]::VirtualScreenLeft, [Math]::Min($script:anchorX, [System.Windows.SystemParameters]::VirtualScreenLeft + [System.Windows.SystemParameters]::VirtualScreenWidth - 320))
        $window.Top = [Math]::Max([System.Windows.SystemParameters]::VirtualScreenTop, [Math]::Min($script:anchorY, [System.Windows.SystemParameters]::VirtualScreenTop + [System.Windows.SystemParameters]::VirtualScreenHeight - $height))
    } else {
        $panel.Visibility = 'Collapsed'; $circle.Visibility = 'Visible'
        $window.Width = 72; $window.Height = 72
        $window.Left = $script:anchorX; $window.Top = $script:anchorY
    }
}

$circle.Add_MouseEnter({ Set-Expanded $true })
$window.Add_MouseLeave({
    $window.Dispatcher.BeginInvoke([action]{
        $point = [System.Windows.Input.Mouse]::GetPosition($window)
        if ($point.X -lt 0 -or $point.Y -lt 0 -or $point.X -ge $window.ActualWidth -or $point.Y -ge $window.ActualHeight) {
            Set-Expanded $false
        }
    }) | Out-Null
})
$window.Add_MouseLeftButtonDown({
    try {
        $window.DragMove()
        $script:anchorX = $window.Left
        $script:anchorY = $window.Top
        Save-Position
    } catch { }
})

$menu = New-Object System.Windows.Controls.ContextMenu
$refreshItem = New-Object System.Windows.Controls.MenuItem
$refreshItem.Header = 'Atualizar agora'
$menu.Items.Add($refreshItem) | Out-Null
$menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null
$providerMenu = New-Object System.Windows.Controls.MenuItem
$providerMenu.Header = 'Mostrar no círculo'
$menu.Items.Add($providerMenu) | Out-Null
$quitItem = New-Object System.Windows.Controls.MenuItem
$quitItem.Header = 'Sair'
$quitItem.Add_Click({ $window.Close() })
$menu.Items.Add($quitItem) | Out-Null
$root.ContextMenu = $menu

function Refresh-Report {
    try {
        $raw = & $UsageExe usage --json 2>$null | Out-String
        $report = $raw | ConvertFrom-Json
        $script:allEntries = @($report.entries)
        Load-Display
        Apply-Display
    } catch {
        $compactText.Text = '!'
    }
}
$refreshItem.Add_Click({ Refresh-Report })
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMinutes(5)
$timer.Add_Tick({ Refresh-Report })
$timer.Start()
$displayTimer = New-Object System.Windows.Threading.DispatcherTimer
$displayTimer.Interval = [TimeSpan]::FromSeconds(2)
$displayTimer.Add_Tick({ Load-Display })
$displayTimer.Start()
$window.Add_ContentRendered({ Refresh-Report })
$window.Add_Closed({ $timer.Stop(); $displayTimer.Stop(); $mutex.ReleaseMutex(); $mutex.Dispose() })
if ($SmokeTest) {
    $script:allEntries = @(
        [pscustomobject]@{ id='anthropic'; name='Claude'; display_name='Claude'; error='Not signed in'; metrics=@() }
        [pscustomobject]@{
            id='openai'; name='Codex'; display_name='Codex'; error=$null
            metrics=@([pscustomobject]@{
                label='Codex weekly'; value='37% used'; percent=37; severity='high'; headline='percent'; group=$null
                window_secs=604800; reset_at=([DateTimeOffset]::UtcNow.AddDays(3).AddHours(17).ToString('o'))
            })
            reset_credits=[pscustomobject]@{ available=2 }
        }
    )
    $script:display = [pscustomobject]@{ visible=@('openai'); theme='dark'; showAs='left' }
    Apply-Display
    if ($script:entries.Count -ne 1 -or $script:entries[0].id -ne 'openai') { throw 'Inactive providers were shown.' }
    if ($compactText.Text -ne '63%') { throw 'The compact meter did not follow Show Usage As.' }
    if ($ring.Stroke.ToString() -ne '#FFF5F5F2') { throw 'Normal progress is not white.' }
    foreach ($criticalPercent in @(19, 81)) {
        $script:allEntries[1].metrics[0].percent = 100 - $criticalPercent
        Apply-Display
        if ($ring.Stroke.ToString() -ne '#FFFF5F57') { throw "Progress at $criticalPercent% is not red." }
    }
    $script:allEntries[1].metrics[0].percent = 37
    Apply-Display
    if (-not (@($rows.Children | Where-Object { $_ -is [System.Windows.Controls.Grid] }).Count)) { throw 'Weekly reset details were not shown.' }
    Set-Expanded $true
    if ($panel.Visibility -ne 'Visible') { throw 'The details panel did not expand.' }
    if ($ScreenshotPath) {
        $size = [System.Windows.Size]::new(320, $window.Height)
        $root.Measure($size)
        $root.Arrange([System.Windows.Rect]::new([System.Windows.Point]::new(0, 0), $size))
        $image = [System.Windows.Media.Imaging.RenderTargetBitmap]::new(320, [int]$window.Height, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
        $image.Render($root)
        $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($image))
        $file = [System.IO.File]::Create($ScreenshotPath)
        try { $encoder.Save($file) } finally { $file.Dispose() }
    }
    Set-Expanded $false
    if ($circle.Visibility -ne 'Visible') { throw 'The compact meter did not return.' }
    $timer.Stop()
    $displayTimer.Stop()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
    exit 0
}
$window.ShowDialog() | Out-Null
