// Use global `ethers` provided by the local UMD bundle loaded in index.html
import {
    initHookContract,
    hookContract,
    fetchTrackedLPs,
    setHookAddress,
    fetchHookOwner,
    fetchPoolStatus,
    fetchStrategyConfig,
    isRealHookContract
} from './contract.js';

const ethers = window.ethers;

// =======================
// MOCK ON-CHAIN DATA
// =======================
const lpData = [
    {
        lp: '0xLP1',
        status: 'ACTIVE',
        liquidity: 1200,
        yield: 45,
        score: 88
    },
    {
        lp: '0xLP2',
        status: 'IDLE',
        liquidity: 800,
        yield: 12,
        score: 62
    },
    {
        lp: '0xLP3',
        status: 'ACTIVE',
        liquidity: 2000,
        yield: 120,
        score: 95
    }
];

// =======================
// EVENT STREAM
// =======================
export function logEvent(message, type = 'info') {
    const consoleBox =
        document.getElementById('eventConsole');

    if (!consoleBox) return;

    const row = document.createElement('div');

    row.className = `event-${type}`;

    row.innerHTML = `
        <span>[${new Date().toLocaleTimeString()}]</span>
        ${message}
    `;

    consoleBox.prepend(row);
}

// =======================
// METRICS
// =======================
export function updateMetrics() {
    const tvl =
        lpData.reduce(
            (a, b) => a + b.liquidity,
            0
        );

    const yieldTotal =
        lpData.reduce(
            (a, b) => a + b.yield,
            0
        );

    const active =
        lpData.filter(
            x => x.status === 'ACTIVE'
        ).length;

    document.getElementById('tvl').innerText =
        `$${tvl}`;

    document.getElementById('idle').innerText =
        '$800';

    document.getElementById('lps').innerText =
        active;

    document.getElementById('yield').innerText =
        `$${yieldTotal}`;

    // Tick Monitoring
    document.getElementById('currentTick').innerText =
        12;

    document.getElementById('lowerTick').innerText =
        -60;

    document.getElementById('upperTick').innerText =
        60;

    // Engine State
    document.getElementById('aTokenBalance').innerText =
        '1250';

    document.getElementById('rebalanceCount').innerText =
        '4';

    logEvent('Metrics refreshed');
}

// =======================
// TABLE
// =======================
export function renderTable() {
    const table =
        document.getElementById('table');

    table.innerHTML = '';

    lpData.forEach(lp => {
        table.innerHTML += `
            <tr>
                <td>${lp.lp}</td>
                <td>${lp.status}</td>
                <td>${lp.liquidity}</td>
                <td>${lp.yield}</td>
                <td>${lp.score}</td>
            </tr>
        `;
    });
}

// =======================
// DISPLAY TRACKED LPS
// =======================
export function displayTrackedLPs(addrs) {
    const table =
        document.getElementById('table');

    table.innerHTML = '';

    if (!addrs || addrs.length === 0) {
        table.innerHTML = `
            <tr>
                <td colspan="5">
                    No tracked LPs found
                </td>
            </tr>
        `;

        return;
    }

    addrs.forEach(addr => {
        table.innerHTML += `
            <tr>
                <td>${addr}</td>
                <td>ONCHAIN</td>
                <td>--</td>
                <td>--</td>
                <td>--</td>
            </tr>
        `;
    });

    logEvent(
        `Loaded ${addrs.length} tracked LPs`,
        'success'
    );
}

// =======================
// CHART
// =======================
export function drawChart() {
    const canvas =
        document.getElementById('chart');

    const ctx =
        canvas.getContext('2d');

    canvas.width = 800;
    canvas.height = 250;

    const data = [
        1000,
        1200,
        900,
        1400,
        1800,
        1600,
        2100
    ];

    ctx.clearRect(
        0,
        0,
        canvas.width,
        canvas.height
    );

    ctx.strokeStyle = '#34d399';
    ctx.lineWidth = 3;

    ctx.beginPath();

    data.forEach((v, i) => {
        const x = i * 120;
        const y = 220 - v / 10;

        if (i === 0) {
            ctx.moveTo(x, y);
        } else {
            ctx.lineTo(x, y);
        }
    });

    ctx.stroke();
}

// =======================
// WALLET + CONTRACT
// =======================
let signer;
let provider;
let userAddress;

// =======================
// CONNECT WALLET
// =======================
export async function connectWallet() {
    try {
        if (!window.ethereum) {
            alert('MetaMask not detected');
            return;
        }

        if (
            typeof window.ethers !== 'undefined' &&
            window.ethers.BrowserProvider
        ) {
            try {
                provider =
                    new window.ethers.BrowserProvider(
                        window.ethereum
                    );

                await provider.send(
                    'eth_requestAccounts',
                    []
                );

                signer =
                    await provider.getSigner();

                userAddress =
                    await signer.getAddress();

                const network =
                    await provider.getNetwork();

                initHookContract(signer);
                updateContractModeUI(isRealHookContract());

                console.log(
                    'Wallet:',
                    userAddress
                );

                console.log(
                    'Chain:',
                    network.chainId
                );

                updateWalletUI(
                    userAddress,
                    network.chainId
                );

                try {
                    const owner = await fetchHookOwner();
                    updateHookOwnerUI(owner);
                    logEvent(
                        `Hook owner: ${owner}`,
                        'success'
                    );
                    if (owner.toLowerCase() === userAddress.toLowerCase()) {
                        logEvent(
                            'Connected wallet is hook owner',
                            'success'
                        );
                    }
                } catch (err) {
                    console.warn('fetchHookOwner failed', err);
                }

                logEvent(
                    `Connected wallet ${userAddress}`,
                    'success'
                );

                const poolInput =
                    document.getElementById(
                        'poolIdInput'
                    );

                if (
                    poolInput &&
                    poolInput.value
                ) {
                    try {
                        const addrs =
                            await fetchTrackedLPs(
                                poolInput.value
                            );

                        displayTrackedLPs(addrs);
                    } catch (e) {
                        console.warn(
                            'fetchTrackedLPs failed',
                            e
                        );
                    }
                }

                return;
            } catch (err) {
                console.warn(
                    'BrowserProvider failed:',
                    err.message || err
                );
            }
        }

        provider = window.ethereum;

        const accounts =
            await provider.request({
                method:
                    'eth_requestAccounts'
            });

        if (
            !accounts ||
            accounts.length === 0
        ) {
            throw new Error('No accounts');
        }

        signer = {
            getAddress: async () =>
                accounts[0]
        };

        userAddress = accounts[0];

        const chainIdHex =
            await provider.request({
                method: 'eth_chainId'
            });

        const network = {
            chainId: parseInt(
                chainIdHex,
                16
            )
        };

        initHookContract(signer);

        updateWalletUI(
            userAddress,
            network.chainId
        );

    } catch (err) {
        console.error(err);

        logEvent(
            'Wallet connection failed',
            'error'
        );

        alert('Wallet connection failed');
    }
}

// =======================
// LOAD POOL
// =======================
export async function loadPool() {
    const poolInput =
        document.getElementById(
            'poolIdInput'
        );

    if (!poolInput) {
        return alert('No pool input');
    }

    const poolId =
        poolInput.value.trim();

    if (!poolId) {
        return alert('Enter a pool id');
    }

    // Hook address support
    if (
        poolId.startsWith('0x') &&
        poolId.length === 42
    ) {
        setHookAddress(poolId);
                updateContractModeUI(isRealHookContract());

        alert(
            'Hook address updated'
        );

        return;
    }

    try {
        if (!hookContract) {
            return alert(
                'Connect wallet first'
            );
        }

        const addrs =
            await fetchTrackedLPs(
                poolId
            );

        displayTrackedLPs(addrs);

        try {
            const status = await fetchPoolStatus(poolId);
            logEvent(
                `Pool ${poolId} approved=${status.approved} exists=${status.exists}`,
                'info'
            );
        } catch (err) {
            console.warn('fetchPoolStatus failed', err);
        }

        logEvent(
            `Pool loaded: ${poolId}`,
            'success'
        );

    } catch (err) {
        console.error(err);

        logEvent(
            'Failed to load tracked LPs',
            'error'
        );

        alert(
            'Failed to load tracked LPs'
        );
    }
}

// =======================
// WALLET UI
// =======================
export function updateWalletUI(
    address,
    chainId
) {
    const wallet =
        document.getElementById(
            'wallet'
        );

    const network =
        document.getElementById(
            'network'
        );

    if (wallet) {
        wallet.innerText =
            `${address.slice(0, 6)}...${address.slice(-4)}`;
    }

    if (network) {
        network.innerText =
            `Chain ID: ${chainId}`;
    }
}

export function updateHookOwnerUI(owner) {
    const hookOwner =
        document.getElementById(
            'hookOwner'
        );

    if (hookOwner) {
        hookOwner.innerText =
            `${owner.slice(0, 6)}...${owner.slice(-4)}`;
    }
}

export function updateContractModeUI(isReal) {
    const modeEl =
        document.getElementById(
            'contractMode'
        );

    if (!modeEl) return;

    modeEl.innerText =
        isReal ? 'Real Contract' : 'Stub Contract';
    modeEl.className =
        isReal ? 'status-active' : 'status-danger';
}


// =======================
// REBALANCE
// =======================
export async function rebalance(
    poolId
) {
    try {
        if (!hookContract) {
            alert(
                'Connect wallet first'
            );

            return;
        }

        logEvent(
            'Sending rebalance transaction...'
        );

        const tx =
            await hookContract.rebalance(
                poolId,
                0,
                20
            );

        logEvent(
            `Rebalance TX: ${tx.hash}`,
            'success'
        );

        await tx.wait();

        const count =
            document.getElementById(
                'rebalanceCount'
            );

        count.innerText =
            Number(count.innerText) + 1;

        logEvent(
            'Rebalance confirmed',
            'success'
        );

    } catch (err) {
        console.error(err);

        logEvent(
            'Rebalance failed',
            'error'
        );

        alert('Rebalance failed');
    }
}

// =======================
// HARVEST
// =======================
export async function harvest(
    poolId
) {
    try {
        if (!hookContract) {
            alert(
                'Connect wallet first'
            );

            return;
        }

        logEvent(
            'Harvesting yield...'
        );

        const tx =
            await hookContract.harvest(
                poolId,
                0
            );

        logEvent(
            `Harvest TX: ${tx.hash}`,
            'success'
        );

        await tx.wait();

        logEvent(
            'Yield harvested successfully',
            'success'
        );

    } catch (err) {
        console.error(err);

        logEvent(
            'Harvest failed',
            'error'
        );

        alert('Harvest failed');
    }
}

// =======================
// REENTER
// =======================
export async function reenter(
    poolId
) {
    try {
        if (!hookContract) {
            alert(
                'Connect wallet first'
            );

            return;
        }

        logEvent(
            'Preparing reenter batch...'
        );

        const tx =
            await hookContract.prepareReenterBatch(
                poolId,
                0,
                20
            );

        logEvent(
            `Reenter TX: ${tx.hash}`,
            'success'
        );

        await tx.wait();

        logEvent(
            'Reenter complete',
            'success'
        );

    } catch (err) {
        console.error(err);

        logEvent(
            'Reenter failed',
            'error'
        );

        alert('Reenter failed');
    }
}

// =======================
// SIMULATE SWAP
// =======================
export async function simulateSwap() {
    const currentTick =
        document.getElementById(
            'currentTick'
        );

    let tick =
        Number(currentTick.innerText);

    tick += Math.floor(
        Math.random() * 40 - 20
    );

    currentTick.innerText = tick;

    const lower =
        Number(
            document.getElementById(
                'lowerTick'
            ).innerText
        );

    const upper =
        Number(
            document.getElementById(
                'upperTick'
            ).innerText
        );

    const rangeStatus =
        document.getElementById(
            'rangeStatus'
        );

    if (
        tick < lower ||
        tick > upper
    ) {
        rangeStatus.innerText =
            'OUT OF RANGE';

        rangeStatus.className =
            'status-danger';

        document.getElementById(
            'poolState'
        ).innerText = 'REBALANCING';

        logEvent(
            'Price moved OUT OF RANGE',
            'error'
        );

    } else {
        rangeStatus.innerText =
            'IN RANGE';

        rangeStatus.className =
            'status-active';

        document.getElementById(
            'poolState'
        ).innerText = 'ACTIVE';

        logEvent(
            'Price remains IN RANGE',
            'success'
        );
    }
}

// =======================
// REFRESH STATE
// =======================
export function refreshState() {
    updateMetrics();
    renderTable();
    drawChart();

    logEvent(
        'State refreshed',
        'success'
    );
}

// =======================
// EMERGENCY PAUSE
// =======================
export function emergencyPause() {
    const automation =
        document.getElementById(
            'automationStatus'
        );

    automation.innerText =
        'PAUSED';

    automation.className =
        'status-danger';

    logEvent(
        'Automation paused',
        'error'
    );
}

// =======================
// INIT UI
// =======================
export function initUI() {
    updateMetrics();
    renderTable();
    drawChart();

    // CONNECT
    const connectBtn =
        document.getElementById(
            'connectBtn'
        );

    if (connectBtn) {
        connectBtn.addEventListener(
            'click',
            connectWallet
        );
    }

    // LOAD POOL
    const loadBtn =
        document.getElementById(
            'loadPoolBtn'
        );

    if (loadBtn) {
        loadBtn.addEventListener(
            'click',
            loadPool
        );
    }

    // SIMULATE SWAP
    const simulateBtn =
        document.getElementById(
            'simulateSwapBtn'
        );

    if (simulateBtn) {
        simulateBtn.addEventListener(
            'click',
            simulateSwap
        );
    }

    // REBALANCE
    const rebalanceBtn =
        document.getElementById(
            'rebalanceBtn'
        );

    if (rebalanceBtn) {
        rebalanceBtn.addEventListener(
            'click',
            () => {
                const poolId =
                    document.getElementById(
                        'poolIdInput'
                    ).value;

                rebalance(poolId);
            }
        );
    }

    // HARVEST
    const harvestBtn =
        document.getElementById(
            'harvestBtn'
        );

    if (harvestBtn) {
        harvestBtn.addEventListener(
            'click',
            () => {
                const poolId =
                    document.getElementById(
                        'poolIdInput'
                    ).value;

                harvest(poolId);
            }
        );
    }

    // REFRESH
    const refreshBtn =
        document.getElementById(
            'refreshBtn'
        );

    if (refreshBtn) {
        refreshBtn.addEventListener(
            'click',
            refreshState
        );
    }

    // PAUSE
    const pauseBtn =
        document.getElementById(
            'pauseBtn'
        );

    if (pauseBtn) {
        pauseBtn.addEventListener(
            'click',
            emergencyPause
        );
    }

    logEvent(
        'YieldPilot initialized',
        'success'
    );

    // Initialize stub hook contract for demo mode so owner and mode
    // display without requiring a wallet extension.
    try {
        initHookContract(null);
        updateContractModeUI(isRealHookContract());

        (async () => {
            try {
                const owner = await fetchHookOwner();
                updateHookOwnerUI(owner);
            } catch (e) {
                console.warn('Failed to fetch stub owner', e);
            }
        })();
    } catch (e) {
        console.warn('initHookContract failed on initUI', e);
    }
}