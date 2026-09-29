param([Parameter(Mandatory=$true)][string]$UsageExe, [switch]$SmokeTest)

$ErrorActionPreference = 'Stop'

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
$panel.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#171b24')
$panel.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#343a49')
$panel.BorderThickness = 1
$panel.CornerRadius = 12
$panel.Visibility = 'Collapsed'
$panelGrid = New-Object System.Windows.Controls.DockPanel
$panelGrid.Margin = 14
$panel.Child = $panelGrid
$title = New-Object System.Windows.Controls.TextBlock
$title.Text = 'AI Usage  ·  arraste para mover'
$title.Foreground = [System.Windows.Media.Brushes]::White
$title.FontFamily = 'Segoe UI'; $title.FontSize = 14; $title.FontWeight = 'Bold'
$title.Margin = '0,0,0,12'
[System.Windows.Controls.DockPanel]::SetDock($title, 'Top')
$panelGrid.Children.Add($title) | Out-Null
$scroll = New-Object System.Windows.Controls.ScrollViewer
$scroll.VerticalScrollBarVisibility = 'Auto'
$rows = New-Object System.Windows.Controls.StackPanel
$scroll.Content = $rows
$panelGrid.Children.Add($scroll) | Out-Null
$root.Children.Add($panel) | Out-Null

$script:entries = @()
$script:selected = if ($saved) { [string]$saved.provider } else { '' }
$script:expanded = $false
$script:anchorX = $window.Left
$script:anchorY = $window.Top

function Save-Position {
    @{ x=$script:anchorX; y=$script:anchorY; provider=$script:selected } |
        ConvertTo-Json -Compress | Set-Content -Path $settingsFile -Encoding UTF8
}

function Set-Ring([double]$percent, [string]$severity) {
    $colors = @{ green='#53ce99'; yellow='#f8bd58'; orange='#f8a45b'; red='#f46d77' }
    $color = if ($colors.ContainsKey($severity)) { $colors[$severity] } else { '#6ca8ff' }
    $ring.Stroke = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
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

function Draw-Report {
    $entry = @($script:entries | Where-Object { $_.id -eq $script:selected } | Select-Object -First 1)
    if (-not $entry.Count) {
        $entry = @($script:entries | Where-Object { $_.metrics -and @($_.metrics).Count -gt 0 } | Select-Object -First 1)
    }
    if (-not $entry.Count) { $entry = @($script:entries | Select-Object -First 1) }
    $metric = @($entry[0].metrics | Where-Object { -not $_.group } | Select-Object -First 1)
    if (-not $metric.Count) { $metric = @($entry[0].metrics | Select-Object -First 1) }
    $percent = if ($metric.Count) { [double]$metric[0].percent } else { 0 }
    Set-Ring $percent ([string]$metric[0].severity)
    $compactText.Text = if ($metric.Count) { '{0:0}%' -f $percent } else { '…' }
    $rows.Children.Clear()
    if (-not $script:entries.Count) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = 'Nenhum provider disponível.'
        $empty.Foreground = [System.Windows.Media.Brushes]::White
        $rows.Children.Add($empty) | Out-Null
    }
    foreach ($item in $script:entries) {
        $name = if ($item.display_name) { $item.display_name } else { $item.name }
        $heading = New-Object System.Windows.Controls.TextBlock
        $heading.Text = [string]$name
        $heading.Foreground = [System.Windows.Media.Brushes]::White
        $heading.FontWeight = 'Bold'; $heading.FontSize = 12
        $heading.Margin = '0,4,0,4'
        $rows.Children.Add($heading) | Out-Null
        $metrics = @($item.metrics)
        if (-not $metrics.Count -and $item.error) {
            $metrics = @([pscustomobject]@{ label='Erro'; value=$item.error; percent=0; severity='red' })
        }
        foreach ($m in $metrics) {
            $line = New-Object System.Windows.Controls.TextBlock
            $line.Text = '{0}: {1}' -f $m.label, $m.value
            $line.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#a8b0c0')
            $line.TextTrimming = 'CharacterEllipsis'
            $rows.Children.Add($line) | Out-Null
            $bar = New-Object System.Windows.Controls.ProgressBar
            $bar.Minimum = 0; $bar.Maximum = 100
            $bar.Value = [Math]::Max(0, [Math]::Min(100, [double]$m.percent))
            $bar.Height = 5; $bar.Margin = '0,3,0,8'
            $rows.Children.Add($bar) | Out-Null
        }
    }
}

function Set-Expanded([bool]$open) {
    if ($script:expanded -eq $open) { return }
    $script:expanded = $open
    if ($open) {
        $circle.Visibility = 'Collapsed'; $panel.Visibility = 'Visible'
        $window.Width = 320; $window.Height = 420
        $window.Left = [Math]::Max([System.Windows.SystemParameters]::VirtualScreenLeft, [Math]::Min($script:anchorX, [System.Windows.SystemParameters]::VirtualScreenLeft + [System.Windows.SystemParameters]::VirtualScreenWidth - 320))
        $window.Top = [Math]::Max([System.Windows.SystemParameters]::VirtualScreenTop, [Math]::Min($script:anchorY, [System.Windows.SystemParameters]::VirtualScreenTop + [System.Windows.SystemParameters]::VirtualScreenHeight - 420))
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
        $script:entries = @($report.entries)
        Draw-Report
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
    } catch {
        $compactText.Text = '!'
    }
}
$refreshItem.Add_Click({ Refresh-Report })
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMinutes(5)
$timer.Add_Tick({ Refresh-Report })
$timer.Start()
$window.Add_ContentRendered({ Refresh-Report })
$window.Add_Closed({ $timer.Stop(); $mutex.ReleaseMutex(); $mutex.Dispose() })
if ($SmokeTest) {
    $script:entries = @(
        [pscustomobject]@{ id='anthropic'; name='Claude'; display_name='Claude'; error='Not signed in'; metrics=@() }
        [pscustomobject]@{
            id='openai'; name='Codex'; display_name='Codex'; error=$null
            metrics=@([pscustomobject]@{
                label='Weekly'; value='37% used'; percent=37; severity='green'; group=$null
            })
        }
    )
    Draw-Report
    if ($compactText.Text -ne '37%') { throw 'The compact meter did not render the report.' }
    Set-Expanded $true
    if ($panel.Visibility -ne 'Visible') { throw 'The details panel did not expand.' }
    Set-Expanded $false
    if ($circle.Visibility -ne 'Visible') { throw 'The compact meter did not return.' }
    $timer.Stop()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
    exit 0
}
$window.ShowDialog() | Out-Null
