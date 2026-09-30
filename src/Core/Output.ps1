function Write-HBorder {
    param([string]$L, [string]$R, [string]$Fill = '═')
    Write-Host "  $L$($Fill * $W)$R" -ForegroundColor Cyan
}

function Write-EmptyRow {
    Write-Host "  ║$(' ' * $W)║" -ForegroundColor Cyan
}

function Write-CenteredRow {
    param([string]$Text, [ConsoleColor]$Color = 'Yellow')
    $pad  = [math]::Floor(($W - $Text.Length) / 2)
    $line = (' ' * $pad) + $Text + (' ' * ($W - $pad - $Text.Length))
    Write-Host '  ║' -NoNewline -ForegroundColor Cyan
    Write-Host $line  -NoNewline -ForegroundColor $Color
    Write-Host '║'   -ForegroundColor Cyan
}

function Write-MenuRow {
    param(
        [string]$Key,
        [string]$Label,
        [ConsoleColor]$KeyColor   = 'Green',
        [ConsoleColor]$LabelColor = 'White'
    )
    $spaces = ' ' * ($W - 5 - $Key.Length - $Label.Length)
    Write-Host '  ║  [' -NoNewline -ForegroundColor Cyan
    Write-Host $Key      -NoNewline -ForegroundColor $KeyColor
    Write-Host '] '      -NoNewline -ForegroundColor DarkGray
    Write-Host "$Label$spaces" -NoNewline -ForegroundColor $LabelColor
    Write-Host '║'       -ForegroundColor Cyan
}

function Write-SectionHeader {
    param([string]$Title)
    Clear-Host
    Write-Host ''
    Write-HBorder '╔' '╗'
    Write-CenteredRow $Title
    Write-HBorder '╚' '╝'
    Write-Host ''
}

function Pause-Continue {
    Write-Host ''
    Write-Host '  Pressione qualquer tecla para voltar ao menu...' -ForegroundColor DarkGray
    [void][Console]::ReadKey($true)
}

function Write-Step {
    param([string]$Message)
    Write-Host '  » ' -NoNewline -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor White
}

function Write-Ok {
    param([string]$Message)
    Write-Host '  ✔ ' -NoNewline -ForegroundColor Green
    Write-Host $Message -ForegroundColor White
}

function Write-Fail {
    param([string]$Message)
    Write-Host '  ✘ ' -NoNewline -ForegroundColor Red
    Write-Host $Message -ForegroundColor White
}

function Write-Warn {
    param([string]$Message)
    Write-Host '  ! ' -NoNewline -ForegroundColor Yellow
    Write-Host $Message -ForegroundColor White
}

function Write-WarningRow {
    param([string]$Text)
    $pad = ' ' * ($W - 6 - $Text.Length)
    Write-Host '  ║  [' -NoNewline -ForegroundColor Cyan
    Write-Host '!'       -NoNewline -ForegroundColor Red
    Write-Host "] $Text$pad" -NoNewline -ForegroundColor Yellow
    Write-Host '║'       -ForegroundColor Cyan
}

function Write-Phase {
    param([string]$Title)
    Write-Host ''
    Write-Host "  ─── $Title" -ForegroundColor Cyan
    Write-Host ''
}

function Write-DiagLine {
    param(
        [string]$Label,
        [string]$State,
        [string]$Detail = '',
        [string]$Fix    = ''
    )
    $pad = ' ' * [math]::Max(1, 26 - $Label.Length)
    switch ($State) {
        'ok'   {
            Write-Host '  ✔  ' -NoNewline -ForegroundColor Green
            Write-Host "$Label$pad" -NoNewline -ForegroundColor White
            Write-Host $Detail -ForegroundColor DarkGray
        }
        'fail' {
            Write-Host '  ✘  ' -NoNewline -ForegroundColor Red
            Write-Host "$Label$pad" -NoNewline -ForegroundColor DarkGray
            Write-Host $Detail -ForegroundColor DarkGray
            if ($Fix) {
                Write-Host '       → ' -NoNewline -ForegroundColor DarkGray
                Write-Host $Fix -ForegroundColor Yellow
            }
        }
        'warn' {
            Write-Host '  !  ' -NoNewline -ForegroundColor Yellow
            Write-Host "$Label$pad" -NoNewline -ForegroundColor White
            Write-Host $Detail -ForegroundColor DarkGray
            if ($Fix) {
                Write-Host '       → ' -NoNewline -ForegroundColor DarkGray
                Write-Host $Fix -ForegroundColor Yellow
            }
        }
        'info' {
            Write-Host '  ·  ' -NoNewline -ForegroundColor DarkGray
            Write-Host "$Label$pad" -NoNewline -ForegroundColor DarkGray
            Write-Host $Detail -ForegroundColor DarkGray
        }
    }
}
