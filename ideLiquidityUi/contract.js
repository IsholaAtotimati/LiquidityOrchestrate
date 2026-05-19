// =======================
// HOOK CONFIG
// =======================
export let HOOK_ADDRESS = "0xf8e813e475c38bff4d5863b8d7abdb84aa72c080";

// Minimal ABI for IdleLiquidityHookEnterprise
export const HOOK_ABI = [
    "function rebalance(bytes32 pid,uint256 start,uint256 maxBatch)",
    "function harvest(bytes32 pid,uint8 side) returns (uint256)",
    "function prepareReenterBatch(bytes32 pid,uint256 start,uint256 maxBatch)",
    // `needUpdate` modifies state in the hook (debounce), so expose as non-view
    "function needUpdate(bytes32 pid) returns (bool)",
    // debug toggle and helpers
    "function setDebugEmitUpdateRequested(bool v)",
    "function getTrackedLPs(bytes32 pid) view returns (address[])",
    "function owner() view returns (address)",
    "function allPools(uint256) view returns (bytes32)",
    "function approvedPools(bytes32) view returns (bool)",
    "function poolExists(bytes32) view returns (bool)",
    "function strategyManager() view returns (address)",
    "function aaveStrategy() view returns (address)",
    "function erc4626Strategy() view returns (address)",
    "function trustedAavePools(address) view returns (bool)",
    "function trustedERC4626Vaults(address) view returns (bool)",
    "function poolCursor() view returns (uint256)"
];

// =======================
// CONTRACT INSTANCE
// =======================
export let hookContract = null;
export let hookContractIsReal = false;

export function isRealHookContract() {
    return hookContractIsReal;
}

// Initialize the hook contract. Use `ethers.Contract` if available,
// otherwise provide a lightweight stub that simulates tx objects.
const DEMO_OWNER_ADDRESS = '0x7b9398c448edaf2d9948cee1bad3748b27e5bb34';

export function initHookContract(signer) {
    hookContractIsReal = false;

    if (typeof window !== 'undefined' && window.ethers && window.ethers.Contract) {
        try {
            hookContract = new window.ethers.Contract(HOOK_ADDRESS, HOOK_ABI, signer);
            hookContractIsReal = true;
            console.log("Hook contract initialized with ethers:", HOOK_ADDRESS);
            return;
        } catch (err) {
            console.warn('window.ethers.Contract threw, falling back to stub:', err.message || err);
        }
    }

    // Fallback stub for environments without ethers available.
    hookContract = {
        rebalance: async (poolId, start, maxBatch) => {
            console.log('Stub rebalance called', poolId, start, maxBatch);
            return { hash: '0xstub_rebalance', wait: async () => ({}) };
        },
        harvest: async (poolId, side) => {
            console.log('Stub harvest called', poolId, side);
            return { hash: '0xstub_harvest', wait: async () => ({}) };
        },
        prepareReenterBatch: async (poolId, start, maxBatch) => {
            console.log('Stub reenter called', poolId, start, maxBatch);
            return { hash: '0xstub_reenter', wait: async () => ({}) };
        },
        needUpdate: async (poolId) => {
            console.log('Stub needUpdate called', poolId);
            return false;
        }
        ,
        // Minimal read helper for UI: return a list of tracked LP addresses
        getTrackedLPs: async (poolId) => {
            console.log('Stub getTrackedLPs called', poolId);
            // Return some fake addresses for UI demonstration
            return [
                '0x1111111111111111111111111111111111111111',
                '0x2222222222222222222222222222222222222222',
                '0x3333333333333333333333333333333333333333'
            ];
        }
        ,
        // Minimal read helpers to satisfy UI calls
        owner: async () => {
            console.log('Stub owner called');
            // Return a fake owner address for demonstration
            return '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
        },
        approvedPools: async (poolId) => {
            console.log('Stub approvedPools called', poolId);
            return false;
        },
        poolExists: async (poolId) => {
            console.log('Stub poolExists called', poolId);
            return false;
        },
        strategyManager: async () => {
            console.log('Stub strategyManager called');
            return '0x0000000000000000000000000000000000000000';
        },
        aaveStrategy: async () => {
            console.log('Stub aaveStrategy called');
            return '0x0000000000000000000000000000000000000000';
        },
        erc4626Strategy: async () => {
            console.log('Stub erc4626Strategy called');
            return '0x0000000000000000000000000000000000000000';
        },
        trustedAavePools: async (addr) => {
            console.log('Stub trustedAavePools called', addr);
            return false;
        },
        trustedERC4626Vaults: async (addr) => {
            console.log('Stub trustedERC4626Vaults called', addr);
            return false;
        },
        poolCursor: async () => {
            console.log('Stub poolCursor called');
            return 0;
        }
    };

    console.log("Hook contract initialized with stub:", HOOK_ADDRESS);
}

// Allow UI to set hook address at runtime
export function setHookAddress(addr) {
    HOOK_ADDRESS = addr;
    try {
        // Re-initialize contract with existing signer if present so the new address is used
        const signer = (hookContract && hookContract.signer) ? hookContract.signer : null;
        initHookContract(signer);
    } catch (e) {
        console.warn('setHookAddress: failed to re-init contract', e.message || e);
    }
}

// Helper to toggle debug emission (owner-only)
export async function setDebugEmit(enabled, signer) {
    if (!hookContract) initHookContract(signer || (window.ethereum && window.ethers ? new window.ethers.providers.Web3Provider(window.ethereum).getSigner() : null));
    const c = hookContract.connect ? hookContract.connect(signer) : hookContract;
    return await c.setDebugEmitUpdateRequested(enabled);
}

// Helper to fetch tracked LPs for a pool id
export async function fetchTrackedLPs(poolId) {
    if (!hookContract) {
        console.warn('hookContract not initialized');
        return [];
    }
    return await hookContract.getTrackedLPs(poolId);
}

export async function fetchHookOwner() {
    if (!hookContract) {
        console.warn('hookContract not initialized');
        return null;
    }
    return await hookContract.owner();
}

export async function fetchPoolStatus(poolId) {
    if (!hookContract) {
        console.warn('hookContract not initialized');
        return { approved: false, exists: false };
    }
    const approved = await hookContract.approvedPools(poolId);
    const exists = await hookContract.poolExists(poolId);
    return { approved, exists };
}

export async function fetchStrategyConfig() {
    if (!hookContract) {
        console.warn('hookContract not initialized');
        return { strategyManager: null, aaveStrategy: null, erc4626Strategy: null };
    }
    const strategyManager = await hookContract.strategyManager();
    const aaveStrategy = await hookContract.aaveStrategy();
    const erc4626Strategy = await hookContract.erc4626Strategy();
    return { strategyManager, aaveStrategy, erc4626Strategy };
}

export async function fetchPoolTrustStatus(aavePool, vault) {
    if (!hookContract) {
        console.warn('hookContract not initialized');
        return { trustedAavePool: false, trustedERC4626Vault: false };
    }
    const trustedAavePool = await hookContract.trustedAavePools(aavePool);
    const trustedERC4626Vault = await hookContract.trustedERC4626Vaults(vault);
    return { trustedAavePool, trustedERC4626Vault };
}