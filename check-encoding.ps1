# Windows 中文亂碼健檢：只檢查、不修改任何設定或檔案。
# 用法（在要檢查的專案資料夾裡開 PowerShell）：
#   powershell -ExecutionPolicy Bypass -File .\check-encoding.ps1
#   powershell -ExecutionPolicy Bypass -File .\check-encoding.ps1 -Path C:\你的專案
# 三層對應文章：https://www.coolkidlab.com/newbie-pitfalls/claude-code-chinese-garbled.html
param([string]$Path = (Get-Location).Path)

$problems = 0
function Say($tag, $msg) {
    $color = @{ '[OK]' = 'Green'; '[X]' = 'Red'; '[!]' = 'Yellow'; '[--]' = 'Gray' }[$tag]
    Write-Host ("  {0,-5}" -f $tag) -ForegroundColor $color -NoNewline
    Write-Host $msg
    if ($tag -eq '[X]') { $script:problems++ }
}
function Fix($msg) { Write-Host "         修法：$msg" -ForegroundColor Cyan }
$cpName = @{ 950 = 'Big5 繁中舊編碼'; 936 = 'GBK 簡中舊編碼'; 932 = 'Shift-JIS'; 1252 = '西歐'; 437 = '英文 OEM'; 65001 = 'UTF-8' }
function Get-CodePageLabel($n) { $n = [int]$n; if ($cpName[$n]) { "$n ($($cpName[$n]))" } else { "$n" } }

Write-Host "`nWindows 中文亂碼健檢（只檢查、不修改）" -ForegroundColor White
Write-Host "PowerShell $($PSVersionTable.PSVersion)　檢查資料夾：$Path`n"

# ---------- 第 1 層：顯示層 ----------
Write-Host "[第 1 層] 顯示層：終端機用什麼編碼" -ForegroundColor White
$nls = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -ErrorAction SilentlyContinue
$acp = [int]$nls.ACP
$console = [Console]::OutputEncoding.CodePage
if ($acp -eq 65001) {
    Say '[OK]' "系統已開「Beta: 使用 Unicode UTF-8」，新開的視窗預設就是 UTF-8"
} elseif ($console -eq 65001) {
    Say '[!]' "這個視窗是 UTF-8，但系統預設是 $(Get-CodePageLabel $acp)：重開視窗、排程、別的程式還是舊編碼"
    Fix "想永久生效，到「變更系統地區設定」勾選 Beta UTF-8 後重開機（文章第 1 步）"
} else {
    Say '[X]' "系統預設 $(Get-CodePageLabel $acp)，這個視窗 $(Get-CodePageLabel $console)：程式輸出 UTF-8 中文會變亂碼"
    Fix "當下視窗打 chcp 65001；永久生效到「變更系統地區設定」勾選 Beta UTF-8 後重開機（文章第 1 步）"
}

# ---------- 第 2 層：執行層 ----------
Write-Host "`n[第 2 層] 執行層：Python 印中文會不會 UnicodeEncodeError" -ForegroundColor White
$vars = 'PYTHONIOENCODING', 'PYTHONUTF8'
$saved = @{}
$persisted = @{}
foreach ($v in $vars) {
    $saved[$v] = [Environment]::GetEnvironmentVariable($v, 'Process')
    $u = [Environment]::GetEnvironmentVariable($v, 'User')
    $persisted[$v] = if ($u) { $u } else { [Environment]::GetEnvironmentVariable($v, 'Machine') }
    Say '[--]' ("{0,-17}= {1}（永久設定，排程看得到的值）" -f $v, $(if ($persisted[$v]) { $persisted[$v] } else { '沒設' }))
}
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) {
    Say '[--]' "沒找到 python，略過實測"
} else {
    # 模擬排程：只帶永久設定的變數、輸出接到管線（不是終端機），看 Python 實際用什麼編碼輸出。
    # 只動這支腳本自己的行程環境，結束前還原，不影響系統。
    try {
        foreach ($v in $vars) { [Environment]::SetEnvironmentVariable($v, $persisted[$v], 'Process') }
        $enc = & $py.Source -c "import sys; print(sys.stdout.encoding)" 2>$null
        $code = $LASTEXITCODE
    } finally {
        foreach ($v in $vars) { [Environment]::SetEnvironmentVariable($v, $saved[$v], 'Process') }
    }
    if ($code -ne 0 -or -not $enc) {
        Say '[--]' "python 跑不起來（可能是 Microsoft Store 的空殼捷徑），略過實測"
    } elseif ("$enc".Trim() -match '^utf-?8$') {
        Say '[OK]' "排程情境下 Python 輸出編碼是 $("$enc".Trim())，印中文不會出錯"
    } else {
        Say '[X]' "排程情境下 Python 輸出編碼是 $("$enc".Trim())：手動跑正常、排程跑就 UnicodeEncodeError"
        Fix "PowerShell 打 [Environment]::SetEnvironmentVariable('PYTHONUTF8','1','User') 後重開終端機（文章第 2 步）"
    }
}

# ---------- 第 3 層：儲存層 ----------
Write-Host "`n[第 3 層] 儲存層：檔案存的格式對不對" -ForegroundColor White
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Say '[--]' "找不到資料夾 $Path，略過"
} else {
    $root = (Resolve-Path -LiteralPath $Path).Path
    $skipDirs = '.git', 'node_modules', '.venv', 'venv', '__pycache__', 'dist', 'build'
    $textExt = '.py', '.md', '.txt', '.json', '.csv', '.yaml', '.yml', '.js', '.ts', '.html', '.css', '.ini', '.toml', '.bat', '.cmd'
    $strict = New-Object System.Text.UTF8Encoding($false, $true)
    $limit = 5000
    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($root)
    # ponytail: 最多掃 5000 個檔、每檔 1MB 以下，夠一般專案用；要掃整顆硬碟再加參數
    while ($queue.Count -and $files.Count -lt $limit) {
        $dir = $queue.Dequeue()
        foreach ($item in (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
            if ($item.PSIsContainer) {
                if ($skipDirs -notcontains $item.Name) { $queue.Enqueue($item.FullName) }
            } elseif ($files.Count -lt $limit) { $files.Add($item) }
        }
    }
    $ps1 = @(); $envBom = @(); $legacy = @()
    foreach ($f in $files) {
        $ext = $f.Extension.ToLower()
        $isPs = '.ps1', '.psm1', '.psd1' -contains $ext
        $isEnv = $f.Name -eq '.env' -or $f.Name -like '.env.*'
        if (-not ($isPs -or $isEnv -or $textExt -contains $ext) -or $f.Length -gt 1MB -or $f.Length -eq 0) { continue }
        try { $b = [System.IO.File]::ReadAllBytes($f.FullName) } catch { continue }
        $bom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
        $rel = $f.FullName.Substring($root.Length).TrimStart('\')
        if ($isEnv) { if ($bom) { $envBom += $rel }; continue }
        # 嚴格解碼失敗 = 不是 UTF-8；解碼成功但字數 < 位元組數 = 含中文等多位元組字
        try { $s = $strict.GetString($b) } catch { $legacy += $rel; continue }
        if ($s.Length -eq $b.Length) { continue }
        if ($isPs -and -not $bom) { $ps1 += $rel }
    }
    $note = if ($files.Count -ge $limit) { "（只掃了前 $limit 個檔，請把 -Path 指到專案資料夾）" } else { '' }
    Say '[--]' "掃了 $($files.Count) 個檔$note"
    function List($items) { $items | Select-Object -First 10 | ForEach-Object { Write-Host "           $_" }; if ($items.Count -gt 10) { Write-Host "           ……還有 $($items.Count - 10) 個" } }

    if ($ps1.Count) {
        if ($acp -eq 65001) {
            Say '[!]' "$($ps1.Count) 個 .ps1 含中文但沒有 BOM：你這台開了 Beta UTF-8 跑得動，別人的電腦會報假的語法錯誤"
        } elseif ($PSVersionTable.PSVersion.Major -ge 6) {
            Say '[!]' "$($ps1.Count) 個 .ps1 含中文但沒有 BOM：PowerShell 7 讀得懂，但用內建 PowerShell 5.1 跑會亂碼、報假的語法錯誤"
        } else {
            Say '[X]' "$($ps1.Count) 個 .ps1 含中文但沒有 BOM：PowerShell 5.1 會用舊編碼讀，報 UnexpectedToken 這類假的語法錯誤"
        }
        List $ps1
        Fix "重存成「具有 BOM 的 UTF-8」，或註解改英文（文章第 3 步、加碼段）"
    } else { Say '[OK]' ".ps1 都沒問題（沒有中文，或已存 BOM）" }

    if ($envBom.Count) {
        Say '[X]' "$($envBom.Count) 個 .env 開頭有 BOM：第一個變數名稱會多出隱形字元，值永遠讀不到"
        List $envBom
        Fix "重存成「UTF-8」（不要選具有 BOM 的那個）（文章第 3 步）"
    } else { Say '[OK]' ".env 都沒有 BOM" }

    if ($legacy.Count) {
        Say '[!]' "$($legacy.Count) 個文字檔不是 UTF-8（多半是 Big5 舊編碼存的）：用 UTF-8 打開會變 ??? 或方塊"
        List $legacy
        Fix "用記事本開啟確認內容正常後，另存成 UTF-8（文章 FAQ「方向相反」那題）"
    } else { Say '[OK]' "文字檔都是 UTF-8" }
}

Write-Host ""
if ($problems) { Write-Host "結論：找到 $problems 個需要修的地方（紅色 [X]），照「修法」那行處理。" -ForegroundColor Red }
else { Write-Host "結論：沒有紅色問題。黃色 [!] 是提醒，你這台不一定會出事。" -ForegroundColor Green }
exit [int]($problems -gt 0)
