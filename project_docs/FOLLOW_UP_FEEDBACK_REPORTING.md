# 回診摘要回饋：管理者查看與匯出

## 上線步驟（程式碼完成不代表已部署）

先在專案根目錄部署新增的兩支 Functions，再發布新版 App：

```sh
firebase deploy --project moodsogood-9e45b --only functions:submitFollowUpSummaryFeedback,functions:deleteFollowUpSummaryFeedback
```

Firestore 新增的明確拒絕規則與原本的預設拒絕具有相同效果；可隨既有 rules 發布流程部署。不要為查看回饋開放客戶端 read 權限。

新版 App 成功送出第一份回饋後，集合才會出現，無須手動新增空文件。

## 查看位置

Firebase Console → moodsogood-9e45b → Firestore Database → 資料 → **followUpSummaryFeedback**。

每個文件是一份摘要的最新回饋。文件 ID 是使用者 UID 與摘要 ID 的 SHA-256 雜湊，用於去重；屬於假名化資料，並非無法關聯的完全匿名資料。文件僅含 shownToDoctor、surfacedForgottenInfo、hadDeeperDiscussion、doctorRequestedAgain、submittedAt；不含摘要、姓名、Email、UID 或健康原文。一般 App 客戶端不可讀寫，僅 callable 以 Admin SDK 驗證擁有者後寫入；管理者透過 Firebase/Google Cloud IAM 權限查看。

submittedAt 為伺服器時間。每次重送覆蓋同一文件。刪除原摘要（包括帳號刪除所移除的摘要）後，刪除觸發器會移除對應回饋。

## CSV 與統計

使用具有該專案 Firestore 讀取 IAM 權限的管理者 Application Default Credentials（例如先執行 `gcloud auth application-default login`）。不要把服務帳戶金鑰加入 Git。

在專案根目錄執行：

```sh
node functions/scripts/export_follow_up_feedback.js moodsogood-9e45b follow-up-feedback.csv
```

工具分頁讀取資料，產生 Excel 可讀的 UTF-8 BOM CSV（UTC 時間、不含識別碼），並在終端印出題目計數與百分比。輸出檔已存在時會停止，請更換檔名。下載的 CSV 請存放在受控位置。

Q1 分母是回饋總數；Q2–Q4 分母僅為 shownToDoctor=true 的份數。不確定／沒有提到各自計數。分母為零時百分比是 null。這些是已回饋者的結果，不代表全部摘要使用者。

## 相容性與失敗重試

舊加密回饋不自動上傳至管理者集合；不會在使用者不知情時搬移原答案。新對話框會說明回饋選項供心域團隊改善功能。GA4 參數保持原樣，不傳 Q2–Q4。

App 先完成管理者集合寫入，再儲存原摘要中的加密回饋。若第二步失敗，入口仍允許重試；同一文件會覆蓋，不會增加份數。兩步皆成功才關閉表單並記錄 Analytics。後端尚未部署或 App Check 不通過時，送出會失敗，不能只發布 App。
