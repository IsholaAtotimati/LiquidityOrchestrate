// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary, PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

contract MockPoolManagerLocal {
    function initialize(PoolKey calldata, uint160) external {}
    function extsload(bytes32) external view returns (bytes32) {
        bytes32 slot = bytes32(0);
        int24 tick = int24(int256(uint256(keccak256(abi.encode(slot))) % 1_000_000) - 500_000);
        uint256 absTick = uint256(uint32(uint24(uint256(int256(tick >= 0 ? tick : -tick)))));
        uint256 base = uint256(1) << 96;
        uint256 sqrtPriceX96 = base + (absTick * (uint256(1) << 76) / 1000);
        uint256 protocolFee = 0;
        uint256 lpFee = 3000;
        uint256 packed = (uint256(lpFee) << 208) | (uint256(protocolFee) << 184) | (uint256(uint24(uint256(int256(tick)))) << 160) | sqrtPriceX96;
        return bytes32(packed);
    }
}

contract IdleLiquidityHookEnterpriseOfflineMinimal is Test {
    function test_minimal_init() public {
        MockPoolManagerLocal m = new MockPoolManagerLocal();
        IPoolManager pm = IPoolManager(address(m));

        ERC20PresetMinterPauser t0 = new ERC20PresetMinterPauser("T0","T0");
        ERC20PresetMinterPauser t1 = new ERC20PresetMinterPauser("T1","T1");
        t0.mint(address(this), 1000 ether);
        t1.mint(address(this), 1000 ether);

        Currency cA = Currency.wrap(address(t0));
        Currency cB = Currency.wrap(address(t1));
        Currency c0 = cA < cB ? cA : cB;
        Currency c1 = cA < cB ? cB : cA;
        IHooks hooksIface = IHooks(address(0));
        PoolKey memory key = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: hooksIface});

        emit log("about to init low-level");
        (bool okInit, bytes memory initRes) = address(pm).call(abi.encodeWithSelector(MockPoolManagerLocal.initialize.selector, key, uint160(1) << 96));
        emit log_named_uint("okInit", okInit ? 1 : 0);
        emit log_named_bytes("initRes", initRes);
        emit log("after low-level init");
    }
}
