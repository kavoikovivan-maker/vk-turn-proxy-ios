const $ = (selector) => document.querySelector(selector);
const byId = (id) => document.getElementById(id);

const tools = {
  speaker: ["динамик", "вода", "звук", "хрип", "частот"],
  photo: ["фото", "метадан", "gps", "геолокац", "сжать", "безопас", "exif"],
  network: ["интернет", "сеть", "ping", "пинг", "задерж", "vpn", "связ"],
  qr: ["qr", "код", "штрих"],
  password: ["парол", "безопасност", "сгенер"],
  text: ["текст", "пробел", "символ", "слова"]
};

byId("vpnConnect").addEventListener("click", () => {
  byId("vpnNote").textContent = "Открываю K&C Smart VPN…";
  window.location.href = "vkturnproxy://connect";
  window.setTimeout(() => {
    if (document.visibilityState === "visible") {
      byId("vpnNote").textContent = "Не удалось открыть VPN. Проверьте, что K&C Smart VPN установлен на iPhone.";
    }
  }, 1400);
});

function openTool(id, message) {
  const node = byId(id);
  if (!node) return;
  node.scrollIntoView({ behavior: "smooth", block: "start" });
  node.classList.remove("flash");
  requestAnimationFrame(() => node.classList.add("flash"));
  if (message) byId("agentAnswer").textContent = message;
}

document.querySelectorAll("[data-open]").forEach((button) => {
  button.addEventListener("click", () => openTool(button.dataset.open));
});

byId("commandForm").addEventListener("submit", (event) => {
  event.preventDefault();
  const query = byId("commandInput").value.trim().toLowerCase();
  if (!query) return;
  const found = Object.entries(tools).find(([, words]) => words.some((word) => query.includes(word)));
  if (found) {
    const title = byId(found[0]).querySelector("h2").textContent;
    openTool(found[0], `Нашёл подходящий инструмент: «${title}».`);
  } else {
    byId("agentAnswer").textContent = "Такого инструмента пока нет. Я сохранил направление для следующего модуля.";
  }
});

function updateOnlineStatus() {
  const online = navigator.onLine;
  const status = byId("onlineStatus");
  status.textContent = online ? "Сеть доступна" : "Без сети";
  status.className = `status ${online ? "online" : "offline"}`;
  byId("netOnline").textContent = online ? "Есть соединение" : "Нет соединения";
}
window.addEventListener("online", updateOnlineStatus);
window.addEventListener("offline", updateOnlineStatus);
updateOnlineStatus();

let audioContext;
let oscillator;
let gain;
let speakerTimer;
let speakerStartedAt;

function stopSpeaker() {
  clearInterval(speakerTimer);
  if (oscillator) {
    try { oscillator.stop(); } catch (_) {}
    oscillator.disconnect();
    oscillator = null;
  }
  if (gain) gain.disconnect();
  byId("speakerWave").classList.remove("active");
  byId("speakerStart").disabled = false;
  byId("speakerStop").disabled = true;
}

byId("speakerStart").addEventListener("click", async () => {
  stopSpeaker();
  audioContext = audioContext || new (window.AudioContext || window.webkitAudioContext)();
  await audioContext.resume();
  oscillator = audioContext.createOscillator();
  gain = audioContext.createGain();
  oscillator.type = "sine";
  oscillator.frequency.value = 165;
  gain.gain.value = 0.75;
  oscillator.connect(gain).connect(audioContext.destination);
  oscillator.start();
  speakerStartedAt = Date.now();
  byId("speakerWave").classList.add("active");
  byId("speakerStart").disabled = true;
  byId("speakerStop").disabled = false;
  speakerTimer = setInterval(() => {
    const elapsed = Date.now() - speakerStartedAt;
    const phase = (elapsed % 1500) / 1500;
    oscillator.frequency.setValueAtTime(150 + Math.sin(phase * Math.PI) * 120, audioContext.currentTime);
    byId("speakerProgress").style.width = `${Math.min(100, elapsed / 300)}%`;
    if (elapsed >= 30000) stopSpeaker();
  }, 100);
});
byId("speakerStop").addEventListener("click", stopSpeaker);

let selectedPhoto;
let selectedImage;
byId("photoInput").addEventListener("change", async (event) => {
  selectedPhoto = event.target.files[0];
  if (!selectedPhoto) return;
  selectedImage = new Image();
  selectedImage.src = URL.createObjectURL(selectedPhoto);
  await selectedImage.decode();
  byId("photoPreview").src = selectedImage.src;
  byId("photoFacts").textContent = `${selectedImage.naturalWidth}×${selectedImage.naturalHeight} · ${(selectedPhoto.size / 1024 / 1024).toFixed(2)} МБ · исходные метаданные не попадут в новую копию`;
  byId("photoResult").classList.remove("hidden");
});
byId("photoQuality").addEventListener("input", (event) => {
  byId("qualityValue").textContent = `${event.target.value}%`;
});
byId("photoDownload").addEventListener("click", () => {
  if (!selectedImage) return;
  const maxSide = 2400;
  const scale = Math.min(1, maxSide / Math.max(selectedImage.naturalWidth, selectedImage.naturalHeight));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(selectedImage.naturalWidth * scale);
  canvas.height = Math.round(selectedImage.naturalHeight * scale);
  canvas.getContext("2d").drawImage(selectedImage, 0, 0, canvas.width, canvas.height);
  canvas.toBlob((blob) => {
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `KC-safe-${Date.now()}.jpg`;
    link.click();
    setTimeout(() => URL.revokeObjectURL(link.href), 1000);
  }, "image/jpeg", Number(byId("photoQuality").value) / 100);
});

async function runNetworkTest() {
  updateOnlineStatus();
  const connection = navigator.connection || navigator.mozConnection || navigator.webkitConnection;
  byId("netType").textContent = connection?.effectiveType?.toUpperCase() || (connection?.type || "Не раскрывается iOS");
  byId("netPing").textContent = "Проверка…";
  const started = performance.now();
  try {
    await fetch(`./?kc_ping=${Date.now()}`, { method: "HEAD", cache: "no-store" });
    byId("netPing").textContent = `${Math.round(performance.now() - started)} мс`;
    byId("networkNote").textContent = "Сервер доступен. Расширенную проверку DNS и VPN добавим в нативную версию.";
  } catch (_) {
    byId("netPing").textContent = "Нет ответа";
    byId("networkNote").textContent = "Сервер не ответил: проверьте сеть или попробуйте другой маршрут.";
  }
  byId("netTime").textContent = new Date().toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" });
}
byId("networkRun").addEventListener("click", runNetworkTest);
runNetworkTest();

byId("qrInput").addEventListener("change", async (event) => {
  const file = event.target.files[0];
  const result = byId("qrResult");
  result.classList.remove("hidden");
  if (!file) return;
  if (!("BarcodeDetector" in window)) {
    result.textContent = "На этой версии Safari локальное распознавание QR недоступно. Камерный сканер добавим через Telegram и нативный модуль.";
    return;
  }
  try {
    const bitmap = await createImageBitmap(file);
    const detector = new BarcodeDetector({ formats: ["qr_code"] });
    const codes = await detector.detect(bitmap);
    result.textContent = codes[0]?.rawValue || "QR-код не найден.";
  } catch (_) {
    result.textContent = "Не удалось прочитать изображение.";
  }
});

function makePassword() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%*-_";
  const values = new Uint32Array(22);
  crypto.getRandomValues(values);
  return Array.from(values, (value) => alphabet[value % alphabet.length]).join("");
}
byId("passwordMake").addEventListener("click", () => { byId("passwordOutput").textContent = makePassword(); });
byId("passwordCopy").addEventListener("click", async () => {
  await navigator.clipboard.writeText(byId("passwordOutput").textContent);
  byId("passwordCopy").textContent = "Скопировано";
  setTimeout(() => { byId("passwordCopy").textContent = "Копировать"; }, 1200);
});

function updateTextFacts() {
  const value = byId("textInput").value;
  const words = value.trim() ? value.trim().split(/\s+/).length : 0;
  byId("textFacts").textContent = `${value.length} символов · ${words} слов`;
}
byId("textInput").addEventListener("input", updateTextFacts);
byId("textClean").addEventListener("click", () => {
  byId("textInput").value = byId("textInput").value.replace(/[ \t]+/g, " ").replace(/\n{3,}/g, "\n\n").trim();
  updateTextFacts();
});
byId("textCopy").addEventListener("click", () => navigator.clipboard.writeText(byId("textInput").value));

if ("serviceWorker" in navigator) window.addEventListener("load", () => navigator.serviceWorker.register("sw.js"));

if (window.Telegram?.WebApp) {
  window.Telegram.WebApp.ready();
  window.Telegram.WebApp.expand();
  // K&C One intentionally keeps its own light appearance even when Telegram
  // itself uses a dark theme. Importing Telegram's background here was what
  // turned the otherwise white interface blue/black on the user's iPhone.
  window.Telegram.WebApp.setHeaderColor?.("#f7f7f5");
  window.Telegram.WebApp.setBackgroundColor?.("#f7f7f5");
}
