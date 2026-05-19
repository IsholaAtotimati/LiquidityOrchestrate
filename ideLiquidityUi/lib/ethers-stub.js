// Minimal ethers stub used as a fallback when the real library can't be loaded.
window.ethers = window.ethers || {};

// Lightweight BrowserProvider implementation that proxies to an EIP-1193 provider.
window.ethers.BrowserProvider = class {
  constructor(ethereumProvider) {
    // Accept a possibly incomplete provider and avoid throwing here.
    // Methods will surface clear errors when used.
    if (!ethereumProvider) {
      this.ethereum = { request: async () => { throw new Error('No provider available'); } };
    } else if (typeof ethereumProvider.request !== 'function') {
      // Normalize older providers exposing `send` instead of `request`.
      if (typeof ethereumProvider.send === 'function') {
        this.ethereum = {
          request: async (opts) => {
            // opts: { method, params }
            return await ethereumProvider.send(opts.method, opts.params || []);
          }
        };
      } else {
        this.ethereum = { request: async () => { throw new Error('Provider missing request/send'); } };
      }
    } else {
      this.ethereum = ethereumProvider;
    }
  }

  // Mirrors ethers' send(method, params) by calling provider.request
  async send(method, params) {
    return await this.ethereum.request({ method, params });
  }

  async getSigner() {
    const accounts = await this.ethereum.request({ method: 'eth_accounts' });
    const address = accounts && accounts[0];
    return {
      getAddress: async () => address,
      // If code expects other signer methods, add them here as needed.
    };
  }

  async getNetwork() {
    const chainIdHex = await this.ethereum.request({ method: 'eth_chainId' });
    return { chainId: parseInt(chainIdHex, 16) };
  }
};

// Keep Contract as a throwing placeholder (we use a stubbed contract in app code).
window.ethers.Contract = class {
  constructor() {
    throw new Error('ethers.Contract not available in fallback stub');
  }
};

// Minimal parseEther: returns a decimal string of wei for simple usages.
window.ethers.parseEther = function(value) {
  const v = typeof value === 'string' ? parseFloat(value) : Number(value);
  if (Number.isNaN(v)) throw new Error('invalid numeric value');
  // Return as string to avoid BigInt issues in environments that don't expect it.
  return String(Math.floor(v * 1e18));
};
