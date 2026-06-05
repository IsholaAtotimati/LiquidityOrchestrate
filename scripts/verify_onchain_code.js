const fs = require('fs');
const https = require('https');
const { URL } = require('url');
const crypto = require('crypto');

function sha256Hex(buf) {
  return crypto.createHash('sha256').update(buf).digest('hex');
}

function hexToBuffer(hex) {
  if (hex.startsWith('0x')) hex = hex.slice(2);
  return Buffer.from(hex, 'hex');
}

async function rpcCall(rpcUrl, method, params) {
  const u = new URL(rpcUrl);
  const data = JSON.stringify({ jsonrpc: '2.0', id: 1, method, params });
  const options = {
    hostname: u.hostname,
    path: u.pathname + (u.search || ''),
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(data),
    },
    port: u.port || (u.protocol === 'https:' ? 443 : 80),
  };

  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      let body = '';
      res.on('data', (d) => (body += d));
      res.on('end', () => {
        try {
          const parsed = JSON.parse(body);
          if (parsed.error) return reject(parsed.error);
          resolve(parsed.result);
        } catch (e) {
          reject(e);
        }
      });
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function main() {
  const rpcUrl = process.env.UNICHAIN_RPC_URL || process.env.RPC_URL;
  if (!rpcUrl) {
    console.error('Set UNICHAIN_RPC_URL environment variable (or RPC_URL) to your JSON-RPC endpoint.');
    process.exit(1);
  }

  const artifactPath = process.argv[2] || 'idleLiquityUi/artifacts/IdleLiquidityHookEnterprise.sol/IdleLiquidityHookEnterprise.json';
  const address = (process.argv[3] || '0x8b266637885e1adb318bda4df9c0af2c9543c658').toLowerCase();

  if (!fs.existsSync(artifactPath)) {
    console.error('Artifact not found at', artifactPath);
    process.exit(1);
  }

  const art = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
  const deployedHex = art.deployedBytecode && art.deployedBytecode.object ? art.deployedBytecode.object : (art.runtimeBytecode || art.bytecode && art.bytecode.object);
  if (!deployedHex) {
    console.error('No deployed/runtime bytecode found in artifact.');
    process.exit(1);
  }

  const deployedBuf = hexToBuffer(deployedHex.startsWith('0x') ? deployedHex : ('0x' + deployedHex));
  const deployedSize = deployedBuf.length;
  const deployedHash = sha256Hex(deployedBuf);

  console.log('Artifact deployed/runtime bytecode:');
  console.log(' - bytes:', deployedSize);
  console.log(' - sha256:', deployedHash);

  // Fetch on-chain code
  console.log('\nFetching on-chain code for', address, 'via', rpcUrl);
  let codeHex;
  try {
    codeHex = await rpcCall(rpcUrl, 'eth_getCode', [address, 'latest']);
  } catch (e) {
    console.error('RPC call failed:', e);
    process.exit(1);
  }

  if (!codeHex || codeHex === '0x') {
    console.log('No code found at address or it returned empty (0x).');
    process.exit(1);
  }

  const onchainBuf = hexToBuffer(codeHex);
  const onchainSize = onchainBuf.length;
  const onchainHash = sha256Hex(onchainBuf);

  console.log('On-chain deployed bytecode:');
  console.log(' - bytes:', onchainSize);
  console.log(' - sha256:', onchainHash);

  console.log('\nComparison:');
  console.log(' - sizes match:', deployedSize === onchainSize);
  console.log(' - sha256 match:', deployedHash === onchainHash);
  if (deployedHash !== onchainHash) {
    console.log('\nNote: If the bytecode differs, the deployed contract may be a different build, optimized with different settings, a minimal proxy, or a different contract altogether.');
  }
}

main();
