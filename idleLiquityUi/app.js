//
// =======================
// 📊 CHART
// =======================
const ctx = document.getElementById('yieldChart');

const yieldChart = new Chart(ctx, {
    type: 'bar',
    data: {
        labels: ['Without YieldPilot', 'With YieldPilot'],
        datasets: [{
            label: 'APY %',
            data: [5.2, 9.8]
        }]
    },
    options: {
        responsive: true
    }
});


// =======================
// 📡 EVENT LOG
// =======================
function log(msg) {
    const logBox = document.getElementById("log");
    const time = new Date().toLocaleTimeString();

    logBox.innerHTML += `[${time}] ${msg}<br>`;
    logBox.scrollTop = logBox.scrollHeight;
}


// =======================
// 🔗 STATE
// =======================
let provider, signer, userAddress;


// =======================
// 🔗 WALLET CONNECTION
// =======================
async function connectWallet() {
    try {
        // =======================
        // 🧠 META MASK CHECK (FIXED)
        // =======================
        if (!window.ethereum || !window.ethereum.isMetaMask) {
            alert("MetaMask not detected. Please open in Chrome/Brave with MetaMask installed.");
            log("MetaMask not available");
            return;
        }

        // =======================
        // 🔗 PROVIDER INIT
        // =======================
        provider = new ethers.BrowserProvider(window.ethereum);

        // =======================
        // 📡 REQUEST ACCOUNTS
        // =======================
        const accounts = await provider.send("eth_requestAccounts", []);

        if (!accounts || accounts.length === 0) {
            log("No wallet account returned");
            return;
        }

        // =======================
        // 🔐 SIGNER
        // =======================
        signer = await provider.getSigner();
        userAddress = await signer.getAddress();

        // =======================
        // 🎯 UI UPDATE
        // =======================
        document.getElementById("wallet").innerText = userAddress;

        log("Wallet connected: " + userAddress);

        // =======================
        // 🔄 AUTO REFRESH DASHBOARD
        // =======================
        if (typeof updateDashboard === "function") {
            updateDashboard();
        }

    } catch (err) {
        console.error(err);

        // Better error visibility
        if (err.code === 4001) {
            log("User rejected wallet connection");
        } else {
            log("Wallet connection failed: " + err.message);
        }
    }
}

// =======================
// 🔁 REBALANCE (REAL TX)
// =======================
async function runRebalance(event) {
    try {
        if (!signer) {
            alert("Connect wallet first");
            return;
        }

        const button = event?.target || document.querySelector(".secondary");

        button.innerText = "Rebalancing...";
        button.disabled = true;

        log("Sending rebalance transaction...");

        const contract = getContract();

        const pid = "0xPOOL_ID"; // ⚠️ replace with real PoolId

        const tx = await contract.rebalance(pid, 0, 10);

        log("TX sent: " + tx.hash);

        await tx.wait();

        log("Rebalance confirmed on-chain");

    } catch (err) {
        console.error(err);
        log("Rebalance failed");

    } finally {
        const button = document.querySelector(".secondary");
        button.innerText = "Run Rebalance";
        button.disabled = false;
    }
}


// =======================
// 🔁 SWAP SIMULATION
// =======================
function triggerSwap() {
    document.getElementById("flowState").innerText =
        "Swap detected in Uniswap pool";

    log("Swap detected");

    setTimeout(() => log("Idle liquidity marked"), 800);
    setTimeout(() => log("$12,400 moved to Aave"), 1600);
    setTimeout(() => log("Rebalance complete"), 2400);
}


// =======================
// 📈 ROI SIMULATOR
// =======================
const slider = document.getElementById("roiSlider");
const output = document.getElementById("roiOutput");

if (slider && output) {
    slider.oninput = function () {
        const base = 5.2;
        const boosted = 9.8;

        const ratio =
            (this.value - 10000) / (200000 - 10000);

        const estimate = base + (boosted - base) * ratio;

        output.innerText = `Estimated Yield: ${estimate.toFixed(2)}%`;

        log("ROI recalculated");
    };
}


// =======================
// 📊 DASHBOARD HOOK (FOR NEXT STEP)
// =======================
async function updateDashboard() {
    try {
        // placeholder for future on-chain sync
        // will connect:
        // - LP count
        // - TVL
        // - user positions

        log("Dashboard sync (placeholder)");

    } catch (err) {
        console.error(err);
    }
}