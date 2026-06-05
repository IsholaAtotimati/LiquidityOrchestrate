let provider;
let signer;
let userAddress;

let tick = 50;
let yieldAmount = 0;
let eventStreamTimer = null;
let eventStreamEnabled = false;

const feed = document.getElementById("feed");
const tickEl = document.getElementById("tick");
const yieldEl = document.getElementById("yield");
const lpStatus = document.getElementById("lpStatus");
const streamToggleBtn = document.getElementById("streamToggle");

/* -------------------------
   EVENT STREAM UI
--------------------------*/
function addEvent(text) {
  const div = document.createElement("div");
  div.className = "event";
  div.innerText = "› " + text;
  feed.prepend(div);
}

function updateStreamToggleLabel() {
  if (!streamToggleBtn) return;

  streamToggleBtn.textContent = eventStreamEnabled
    ? "Pause live feed"
    : "Start live feed";
}

/* -------------------------
   WALLET CONNECT (REAL)
--------------------------*/
async function connectWallet() {
  if (location.protocol === "file:") {
    alert("Open this app from a local web server such as http://127.0.0.1:8000/ instead of file://. Wallet providers require an HTTP origin.");
    return;
  }

  if (!window.ethereum) {
    alert("MetaMask was not detected in this browser. Please open this app in Chrome or Edge with the MetaMask extension installed and enabled, then try again.");
    return;
  }

  provider = new ethers.BrowserProvider(window.ethereum);
  await provider.send("eth_requestAccounts", []);

  signer = await provider.getSigner();
  userAddress = await signer.getAddress();

  document.getElementById("walletBtn").innerText =
    userAddress.slice(0, 6) + "..." + userAddress.slice(-4);

  addEvent("Wallet connected: " + userAddress);
  addEvent("Live feed is ready — press Start live feed when you want protocol updates.");
}

/* -------------------------
   FAKE LIVE STREAM
--------------------------*/
function startEventStream() {
  if (eventStreamTimer) return;

  eventStreamEnabled = true;
  updateStreamToggleLabel();

  addEvent("Connecting to PoolManager stream...");
  setTimeout(() => {
    if (eventStreamEnabled) {
      addEvent("Event stream active");
    }
  }, 800);

  eventStreamTimer = setInterval(() => {
    const events = [
      "Swap executed",
      "Tick updated",
      "LiquidityIdle detected",
      "Rebalance triggered",
      "Yield index updated"
    ];

    const e = events[Math.floor(Math.random() * events.length)];
    addEvent(e);

    if (e.includes("LiquidityIdle")) {
      lpStatus.innerText = "IDLE";
    }

    if (e.includes("Tick")) {
      tick += Math.floor(Math.random() * 20 - 10);
      tickEl.innerText = tick;
    }

    if (e.includes("Yield")) {
      yieldAmount += 0.5;
      yieldEl.innerText = yieldAmount.toFixed(2) + " USDC";
    }
  }, 2500);
}

function stopEventStream() {
  if (!eventStreamTimer) return;

  clearInterval(eventStreamTimer);
  eventStreamTimer = null;
  eventStreamEnabled = false;
  updateStreamToggleLabel();
  addEvent("Live feed paused by user");
}

function toggleEventStream() {
  if (eventStreamEnabled) {
    stopEventStream();
    return;
  }

  startEventStream();
}

/* -------------------------
   DEMO ACTIONS
--------------------------*/
function addLiquidity() {
  lpStatus.innerText = "ACTIVE";
  addEvent("Liquidity added");
}

function simulateSwap() {
  tick = 250;
  tickEl.innerText = tick;

  addEvent("Swap detected");
  setTimeout(() => {
    lpStatus.innerText = "IDLE";
    addEvent("Liquidity became idle");
  }, 600);
}

function rebalance() {
  addEvent("Rebalance initiated");

  setTimeout(() => {
    addEvent("Depositing into Aave");
  }, 700);

  let i = setInterval(() => {
    yieldAmount += 0.6;
    yieldEl.innerText = yieldAmount.toFixed(2) + " USDC";

    if (yieldAmount > 6) {
      clearInterval(i);
      addEvent("Yield accruing from protocol");
    }
  }, 400);
}