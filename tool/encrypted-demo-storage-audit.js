(function () {
  "use strict";
  // Read-only diagnostics for these two disposable demo origins only.
  // Outputs boolean outcomes, never storage values, credentials or medical text.
  if (!["innera-demo-encrypted-patient.web.app", "innera-demo-encrypted-doctor.web.app"].includes(location.hostname)) return;
  const container = document.createElement("aside"), button = document.createElement("button"), output = document.createElement("p");
  container.style.cssText = "position:fixed;bottom:0;right:0;z-index:10000;background:white;color:#233e36;padding:8px;font:14px system-ui;max-width:420px";
  button.textContent = "檢查 Demo storage"; output.id = "demoStorageResult"; output.setAttribute("role", "status");
  container.append(button, output); document.body.append(container);
  function medical(value) {
    const serialized = typeof value === "string" ? value : JSON.stringify(value);
    return /"(?:domains|patternSummary|facts|sourcePeriod|sourceVersions|sources|durationMinutes|sleepConditions|symptoms|overallMood|ingredientLines|bodyMeasurement)"\s*:|固定規則合成測試|僅為固定規則整理/.test(serialized || "");
  }
  async function databaseAudit() {
    if (!indexedDB.databases) throw Error();
    const databases = await indexedDB.databases(); let found = false;
    for (const info of databases) {
      if (!info.name) throw Error();
      await new Promise((resolve, reject) => {
        const open = indexedDB.open(info.name);
        open.onupgradeneeded = () => { open.transaction.abort(); reject(Error()); }; // Never create a database.
        open.onerror = () => reject(Error());
        open.onsuccess = () => {
          const db = open.result, names = Array.from(db.objectStoreNames);
          if (!names.length) { db.close(); resolve(); return; }
          const tx = db.transaction(names, "readonly"); let count = 0;
          tx.oncomplete = () => { db.close(); resolve(); };
          tx.onerror = tx.onabort = () => { db.close(); reject(Error()); };
          for (const name of names) {
            const request = tx.objectStore(name).openCursor();
            request.onerror = () => tx.abort();
            request.onsuccess = () => {
              const cursor = request.result;
              if (!cursor) return;
              if (++count > 1000) { tx.abort(); return; }
              try { if (medical(cursor.value)) found = true; cursor.continue(); } catch { tx.abort(); }
            };
          }
        };
      });
    }
    return found;
  }
  button.onclick = async () => {
    button.disabled = true; output.textContent = "檢查中…";
    try {
      const result = {};
      for (const [label, storage] of [["Local", localStorage], ["Session", sessionStorage]]) {
        result[label] = false;
        for (let i = 0; i < storage.length; i++) if (medical(storage.getItem(storage.key(i)))) result[label] = true;
      }
      result.IndexedDB = await databaseAudit(); result.Cache = false;
      for (const name of await caches.keys()) {
        const cache = await caches.open(name);
        for (const request of await cache.keys()) {
          const response = await cache.match(request);
          // Bundled JS/HTML contains fixed synthetic fixtures by design; inspect cached data responses, not code assets.
          if (response?.headers.get("content-type")?.includes("json") && medical(await response.clone().json())) result.Cache = true;
        }
      }
      output.textContent = Object.entries(result).map(([label, found]) => `${label}：${found ? "發現醫療欄位，驗收失敗" : "未發現醫療欄位"}`).join("；");
    } catch { output.textContent = "Storage 檢查未完成，不能判定通過；請人工檢查。"; }
    finally { button.disabled = false; }
  };
})();
