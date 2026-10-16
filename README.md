# Windows 中文亂碼健檢

在 Windows 上用 Claude Code、Codex、VS Code 寫程式，中文變成 ??? 或方塊？Python 報 `UnicodeEncodeError: cp950`？.ps1 跳出一堆看不出哪裡錯的語法錯誤？

這支 PowerShell 腳本會一層一層檢查，告訴你問題出在哪一層、該怎麼修。

**只檢查，不修改**：不改系統設定、不改環境變數、不動任何檔案。修法會印在畫面上，要不要照做由你決定。

## 會檢查哪些地方？

| 層 | 檢查項目 |
|---|---|
| 顯示層 | 系統預設的字碼頁（有沒有開「Beta: 使用 Unicode UTF-8」）、目前這個視窗的字碼頁 |
| 執行層 | 只帶「排程看得到的環境變數」實際跑一次 Python，看輸出編碼是不是 UTF-8。手動跑正常、排程跑就掛掉，多半卡在這層 |
| 儲存層 | 掃資料夾，找出含中文卻沒存 BOM 的 .ps1、開頭有 BOM 的 .env、不是 UTF-8 的文字檔 |

## 怎麼用

1. 下載 `check-encoding.ps1`：用 `git clone https://github.com/Coolkidlab-Yin/windows-cjk-encoding-check.git`，或在 GitHub 頁面點 **Code → Download ZIP** 解壓縮。
2. 在要檢查的專案資料夾裡開 PowerShell，輸入：

```powershell
powershell -ExecutionPolicy Bypass -File .\check-encoding.ps1
```

想檢查別的資料夾，在後面加 `-Path`：

```powershell
powershell -ExecutionPolicy Bypass -File .\check-encoding.ps1 -Path C:\你的專案
```

`-ExecutionPolicy Bypass` 只對這一次執行有效，不會改到電腦的設定。Windows 預設不讓你直接執行下載來的 .ps1，所以需要加這一段。

## 結果怎麼看？

| 標記 | 意思 |
|---|---|
| `[OK]` 綠色 | 這項沒問題 |
| `[X]` 紅色 | 需要修，下一行「修法」寫了怎麼做 |
| `[!]` 黃色 | 提醒：你這台現在不一定會出事，換一台電腦或換一個執行方式就可能出事 |
| `[--]` 灰色 | 資訊，或沒有對應的東西可以檢查而略過 |

一台還在用 Big5（字碼頁 950）的電腦，跑出來大概長這樣：

```
[第 1 層] 顯示層：終端機用什麼編碼
  [X]  系統預設 950 (Big5 繁中舊編碼)，這個視窗 950 (Big5 繁中舊編碼)：程式輸出 UTF-8 中文會變亂碼
         修法：當下視窗打 chcp 65001；永久生效到「變更系統地區設定」勾選 Beta UTF-8 後重開機（文章第 1 步）

[第 2 層] 執行層：Python 印中文會不會 UnicodeEncodeError
  [X]  排程情境下 Python 輸出編碼是 cp950：手動跑正常、排程跑就 UnicodeEncodeError
         修法：PowerShell 打 [Environment]::SetEnvironmentVariable('PYTHONUTF8','1','User') 後重開終端機（文章第 2 步）

[第 3 層] 儲存層：檔案存的格式對不對
  [X]  1 個 .ps1 含中文但沒有 BOM：PowerShell 5.1 會用舊編碼讀，報 UnexpectedToken 這類假的語法錯誤
           bad.ps1
```

全部沒有紅色時，結束代碼是 0；有紅色是 1，可以拿去接在其他自動檢查後面。

## 限制

- 一次最多掃 5000 個檔，單檔超過 1MB 不看。會跳過 `.git`、`node_modules`、`.venv`、`venv`、`__pycache__`、`dist`、`build`。
- Python 只檢查 PATH 上找到的那個 `python`。
- 在 Windows 11 的 PowerShell 5.1 與 PowerShell 7 實測過。

## 原理與完整修法

三層各自為什麼會出錯、每一步怎麼修，寫在這篇：
[Claude Code 中文亂碼？Windows 3 步修好](https://www.coolkidlab.com/newbie-pitfalls/claude-code-chinese-garbled.html)

## 授權

MIT
