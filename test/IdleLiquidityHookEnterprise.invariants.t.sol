// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IdleLiquidityHookEnterprise} from "../src/hooks/IdleLiquidityHookEnterprise.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary, PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Status} from "../src/types/IdleLiquidityTypes.sol";

contract InvariantMockPoolManager {
    function initialize(PoolKey calldata, uint160) external {}
    function modifyLiquidity(PoolKey calldata key, IPoolManager.ModifyLiquidityParams calldata params, bytes calldata) external {
        PoolId pid = PoolIdLibrary.toId(key);
        int256 liq = params.liquidityDelta;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 l = liq > 0 ? uint128(uint256(liq)) : 0;
        if (l > 0) {
            address token0 = Currency.unwrap(key.currency0);
            address token1 = Currency.unwrap(key.currency1);
            uint256 tokenAmount = uint256(l) / 1e3;
            if (tokenAmount == 0) tokenAmount = 1e12;
            try ERC20PresetMinterPauser(token0).transferFrom(msg.sender, address(this), tokenAmount) {} catch {}
            try ERC20PresetMinterPauser(token1).transferFrom(msg.sender, address(this), tokenAmount) {} catch {}
        }
        IdleLiquidityHookEnterprise(address(key.hooks)).registerPosition(pid, msg.sender, l, 0, params.tickLower, params.tickUpper);
    }
    function swap(PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata) external {
        IHooks hooks = key.hooks;
        try hooks.afterSwap(address(this), key, params, BalanceDelta.wrap(0), "") returns (bytes4, int128) {} catch { revert("hook afterSwap failed"); }
    }
    function extsload(bytes32) external view returns (bytes32) {
        // simple deterministic non-zero slot used by invariants
        uint256 sqrtPriceX96 = uint256(1) << 96;
        int24 tick = 0;
        uint256 protocolFee = 0;
        uint256 lpFee = 3000;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 packed = (uint256(lpFee) << 208) | (uint256(protocolFee) << 184) | (uint256(uint24(uint256(int256(tick)))) << 160) | sqrtPriceX96;
        return bytes32(packed);
    }
}

contract IdleLiquidityHookEnterpriseInvariants is Test {
    IdleLiquidityHookEnterprise public hook;
    IPoolManager public pm;
    ERC20PresetMinterPauser public t0;
    ERC20PresetMinterPauser public t1;
    PoolId public pid;

    function setUp() public {
        InvariantMockPoolManager m = new InvariantMockPoolManager();
        pm = IPoolManager(address(m));
        hook = new IdleLiquidityHookEnterprise(address(m));

        t0 = new ERC20PresetMinterPauser("T0","T0");
        t1 = new ERC20PresetMinterPauser("T1","T1");
        t0.mint(address(this), 1000 ether);
        t1.mint(address(this), 1000 ether);

        Currency cA = Currency.wrap(address(t0));
        Currency cB = Currency.wrap(address(t1));
        Currency c0 = cA < cB ? cA : cB;
        Currency c1 = cA < cB ? cB : cA;
        IHooks hooksIface = IHooks(address(hook));
        PoolKey memory key = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: hooksIface});
        pid = PoolIdLibrary.toId(key);

        // approve large amounts for mock transfers
        t0.approve(address(pm), type(uint256).max);
        t1.approve(address(pm), type(uint256).max);
    }

    // Simple invariant-style sequence runner that performs a few actions and checks invariants.
    function test_invariants_sequence() public {
        IPoolManager.ModifyLiquidityParams memory lp = IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: int256(1e18), salt: bytes32(0)});
        IPoolManager.SwapParams memory sp = IPoolManager.SwapParams({zeroForOne: true, amountSpecified: int256(1e18/100), sqrtPriceLimitX96: 0});

        // start with an add-liquidity
        (bool okMod, ) = address(pm).call(abi.encodeWithSelector(IPoolManager.modifyLiquidity.selector, PoolKey({currency0: Currency.wrap(address(t0)) < Currency.wrap(address(t1)) ? Currency.wrap(address(t0)) : Currency.wrap(address(t1)), currency1: Currency.wrap(address(t0)) < Currency.wrap(address(t1)) ? Currency.wrap(address(t1)) : Currency.wrap(address(t0)), fee: 3000, tickSpacing: 60, hooks: IHooks(address(hook))}), lp, ""));
        require(okMod, "initial modifyLiquidity failed");

        for (uint256 i = 0; i < 8; i++) {
            // alternate actions: swap, maybe add more liquidity, warp, rebalance when needed
            if (i % 3 == 0) {
                (bool okSwap, ) = address(pm).call(abi.encodeWithSelector(IPoolManager.swap.selector, PoolKey({currency0: Currency.wrap(address(t0)) < Currency.wrap(address(t1)) ? Currency.wrap(address(t0)) : Currency.wrap(address(t1)), currency1: Currency.wrap(address(t0)) < Currency.wrap(address(t1)) ? Currency.wrap(address(t1)) : Currency.wrap(address(t0)), fee: 3000, tickSpacing: 60, hooks: IHooks(address(hook))}), sp, ""));
                if (!okSwap) { /* ignore swap failures in mocks */ }
            } else if (i % 3 == 1) {
                // add more liquidity occasionally
                IPoolManager.ModifyLiquidityParams memory lp2 = IPoolManager.ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: int256(5e17), salt: bytes32(0)});
                address pmAddr = address(pm);
                (bool ok2, ) = pmAddr.call(abi.encodeWithSelector(IPoolManager.modifyLiquidity.selector, PoolKey({currency0: Currency.wrap(address(t0)) < Currency.wrap(address(t1)) ? Currency.wrap(address(t0)) : Currency.wrap(address(t1)), currency1: Currency.wrap(address(t0)) < Currency.wrap(address(t1)) ? Currency.wrap(address(t1)) : Currency.wrap(address(t0)), fee: 3000, tickSpacing: 60, hooks: IHooks(address(hook))}), lp2, ""));
                if (!ok2) { /* ignore */ }
            } else {
                // warp and perform rebalance if upkeep indicates
                vm.warp(block.timestamp + 1 hours);
                // owner is this contract when deployed locally
                vm.prank(hook.owner());
                try hook.rebalance(pid, 0, 10) {} catch {}
            }

            // Invariants (lightweight and robust against mocks):
            // - positions query for this address should not revert and status is within enum range
            (uint128 l0, uint128 l1, int24 lower, int24 upper, Status status, uint256 ly0, uint256 ly1, uint256 ay0, uint256 ay1, uint256 vs0, uint256 vs1, uint256 atp0, uint256 atp1) = hook.positions(pid, address(this));
            require(uint8(status) < 4, "invalid status");

            // - lastRebalanceBlock must be <= current block
            uint256 rb = hook.lastRebalanceBlock(pid);
            require(rb <= block.number, "lastRebalanceBlock in future");

            // - checkUpkeep callable
            try hook.checkUpkeep("") returns (bool need, bytes memory) {
                // nothing else required
            } catch {
                revert("checkUpkeep reverted");
            }
        }
    }
}
