// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ---------------------------------------------------------------------------
// VOIDCOIN V4 — live Base B20 precompile simulation gate
//
// This file exists to discharge, item by item, the seven confirmations in the
// handoff's "Live-precompile simulation gate" section. It reproduces the
// production constructor transaction with NO BROADCAST and asserts each gate
// item explicitly rather than leaving it implied by the wider suite.
//
// Run under stock forge  -> base-std REFERENCE mode (Solidity mocks).
// Run with FOUNDRY_BASE=true (or `base-forge`) -> LIVE PRECOMPILE mode,
// exercising base/base's real Rust B20 factory and native B20 execution.
//
// Every test asserts `livePrecompiles` where the distinction matters, so a
// reference-mode run cannot be mistaken for a live-precompile confirmation.
// ---------------------------------------------------------------------------

import {BaseTest} from "base-std-test/lib/BaseTest.sol";
import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {B20Constants} from "base-std/lib/B20Constants.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {VOIDB20Bootstrapper} from "../src/VOIDB20Bootstrapper.sol";
import {VOIDB20SkinController} from "../src/VOIDB20SkinController.sol";

contract ProductionSafeDouble {}

contract VOIDCOINV4LiveGateTest is BaseTest {
    // Mirrors DeployB20V4.s.sol exactly.
    string internal constant INITIAL_NAME = "VOIDCOIN";
    string internal constant INITIAL_SYMBOL = "VOID";
    string internal constant GENESIS_URI = "ipfs://bafyGenesisMetadataPlaceholder";
    bytes32 internal constant SALT = keccak256("VOID-B20-V4-LIVE-GATE");
    uint256 internal constant ORIGINAL_SUPPLY = 1_000_000_000 ether;

    ProductionSafeDouble internal safe;

    function setUp() public override {
        super.setUp();
        safe = new ProductionSafeDouble();
        emit log_named_string("world", livePrecompiles ? "LIVE PRECOMPILE" : "REFERENCE (mocks)");
    }

    /// @dev Reproduces the production constructor transaction. No vm.broadcast,
    ///      no vm.startBroadcast, no private key, no RPC.
    function _deploy() internal returns (VOIDB20Bootstrapper b) {
        b = new VOIDB20Bootstrapper(
            address(safe), StdPrecompiles.B20_FACTORY, SALT, INITIAL_NAME, INITIAL_SYMBOL, GENESIS_URI
        );
    }

    /// GATE 0. Record which world this run actually exercised. A failure here
    ///         means the run is a mock test and must not be reported as a
    ///         live-precompile confirmation.
    function testGate0_ThisRunIsExercisingTheLiveBasePrecompiles() public view {
        if (!livePrecompiles) {
            revert(
                "REFERENCE MODE: this run used the Solidity mocks. Re-run with FOUNDRY_BASE=true or base-forge to discharge the gate."
            );
        }
        assertTrue(livePrecompiles, "live precompiles");
    }

    /// GATE 1. getB20Address(ASSET, bootstrapper, salt) matches the address
    ///         returned by createB20.
    function testGate1_PredictedAddressMatchesCreatedAddress() public {
        VOIDB20Bootstrapper b = _deploy();
        address predicted = StdPrecompiles.B20_FACTORY.getB20Address(IB20Factory.B20Variant.ASSET, address(b), SALT);
        assertEq(predicted, b.token(), "getB20Address == createB20 return");

        // The variant byte is recoverable from the address, per the documented
        // derivation [prefix(10)][variant(1)][bytes9(keccak(deployer,salt))].
        assertEq(uint8(uint160(b.token()) >> 72) & 0xFF, 0, "variant byte encodes ASSET");
    }

    /// GATE 2. All five initCalls execute, in order, through the privileged
    ///         factory initialization window. Order is proven by the outcome:
    ///         the mint could not have succeeded unless the cap had already been
    ///         raised, and the role grants could not have succeeded outside the
    ///         window because the token has no admin.
    function testGate2_AllFiveInitCallsExecutedInOrderInsideThePrivilegedWindow() public {
        VOIDB20Bootstrapper b = _deploy();
        IB20 t = IB20(b.token());
        VOIDB20SkinController c = b.controller();

        assertEq(t.supplyCap(), ORIGINAL_SUPPLY, "initCall 0: updateSupplyCap");
        assertEq(t.totalSupply(), ORIGINAL_SUPPLY, "initCall 1: batchMint minted");
        assertEq(t.balanceOf(address(safe)), ORIGINAL_SUPPLY, "initCall 1: batchMint recipient");
        assertEq(t.contractURI(), GENESIS_URI, "initCall 2: updateContractURI");
        assertTrue(t.hasRole(B20Constants.BURN_ROLE, address(c)), "initCall 3: grantRole BURN_ROLE");
        assertTrue(t.hasRole(B20Constants.METADATA_ROLE, address(c)), "initCall 4: grantRole METADATA_ROLE");

        // Ordering proof: cap before mint. If updateSupplyCap had run after
        // batchMint the mint would have hit the default cap, and if the cap had
        // been lowered to 1e27 after minting 1e27 it would still be exactly
        // equal -- so assert the stronger property instead: the cap can no
        // longer be raised by anyone, and no further mint is possible.
        vm.prank(address(safe));
        vm.expectRevert();
        t.updateSupplyCap(type(uint128).max);
        vm.prank(address(safe));
        vm.expectRevert();
        t.mint(address(safe), 1);

        // Window proof: the same grantRole that succeeded inside the window
        // fails from every actor now that the window has closed.
        address[3] memory actors = [address(safe), address(b), attacker];
        for (uint256 i; i < actors.length; ++i) {
            vm.prank(actors[i]);
            vm.expectRevert();
            t.grantRole(B20Constants.BURN_ROLE, actors[i]);
        }
    }

    /// GATE 3. isB20 and isB20Initialized both return true after creation, and
    ///         isB20Initialized is false for an address that was merely
    ///         predicted and never created.
    function testGate3_IsB20AndIsB20InitializedBothTrueAfterCreation() public {
        address neverCreated =
            StdPrecompiles.B20_FACTORY.getB20Address(IB20Factory.B20Variant.ASSET, address(this), keccak256("nope"));
        assertTrue(StdPrecompiles.B20_FACTORY.isB20(neverCreated), "isB20 is a prefix check only");
        assertFalse(StdPrecompiles.B20_FACTORY.isB20Initialized(neverCreated), "not initialized before creation");

        VOIDB20Bootstrapper b = _deploy();
        assertTrue(StdPrecompiles.B20_FACTORY.isB20(b.token()), "isB20 after creation");
        assertTrue(StdPrecompiles.B20_FACTORY.isB20Initialized(b.token()), "isB20Initialized after creation");
    }

    /// GATE 4. The controller's role reads work against the native
    ///         marker-address execution model. This is the specific reason
    ///         controllerReady() reads roles rather than checking bytecode:
    ///         a native B20 reports code that is a marker, not an
    ///         implementation.
    function testGate4_ControllerRoleReadsWorkAgainstNativeMarkerAddressExecution() public {
        VOIDB20Bootstrapper b = _deploy();
        IB20 t = IB20(b.token());
        VOIDB20SkinController c = b.controller();

        assertTrue(c.controllerReady(), "controllerReady() reads roles successfully");
        assertTrue(t.hasRole(B20Constants.BURN_ROLE, address(c)), "direct BURN_ROLE read");
        assertTrue(t.hasRole(B20Constants.METADATA_ROLE, address(c)), "direct METADATA_ROLE read");

        // Record what the marker address actually looks like, so the report can
        // state it rather than assume it.
        emit log_named_uint("B20 address code size", address(t).code.length);
        emit log_named_uint("B20 factory code size", StdPrecompiles.B20_FACTORY_ADDRESS.code.length);

        // A negative control: a role the controller does not hold reads false,
        // so controllerReady() is not trivially true against native execution.
        assertFalse(t.hasRole(B20Constants.MINT_ROLE, address(c)), "negative control");
        assertFalse(t.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, address(c)), "negative control");
    }

    /// GATE 5. Every postcondition the bootstrapper asserts, plus the four it
    ///         does not (decimals, name, symbol, contract URI -- see finding
    ///         L-3), verified against live execution.
    function testGate5_EveryPostconditionHoldsAgainstLiveExecution() public {
        VOIDB20Bootstrapper b = _deploy();
        IB20 t = IB20(b.token());
        VOIDB20SkinController c = b.controller();

        // asserted by the bootstrapper
        assertEq(t.totalSupply(), ORIGINAL_SUPPLY, "supply");
        assertEq(t.supplyCap(), ORIGINAL_SUPPLY, "cap");
        assertEq(t.balanceOf(address(safe)), ORIGINAL_SUPPLY, "safe balance");
        assertTrue(c.controllerReady(), "controller ready");
        assertTrue(c.renamePaused(), "starts paused");
        assertEq(c.owner(), address(safe), "owner is the Safe");
        assertFalse(t.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, address(safe)), "no admin: safe");
        assertFalse(t.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, address(b)), "no admin: bootstrapper");
        assertFalse(t.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, address(c)), "no admin: controller");
        assertFalse(t.hasRole(B20Constants.MINT_ROLE, address(safe)), "no minter: safe");
        assertFalse(t.hasRole(B20Constants.PAUSE_ROLE, address(safe)), "no pauser");
        assertFalse(t.hasRole(B20Constants.UNPAUSE_ROLE, address(safe)), "no unpauser");
        assertFalse(t.hasRole(B20Constants.BURN_BLOCKED_ROLE, address(safe)), "no blocked-burner");
        assertFalse(t.hasRole(B20Constants.SEIZE_ROLE, address(safe)), "no seizer");
        assertFalse(IB20Asset(address(t)).hasRole(B20Constants.OPERATOR_ROLE, address(safe)), "no operator");

        // NOT asserted by the bootstrapper -- verified here (finding L-3)
        assertEq(t.decimals(), 18, "decimals");
        assertEq(t.name(), INITIAL_NAME, "name");
        assertEq(t.symbol(), INITIAL_SYMBOL, "symbol");
        assertEq(t.contractURI(), GENESIS_URI, "contract URI");

        // Nothing is paused at creation, and nothing can ever be paused.
        IB20.PausableFeature[] memory paused = t.pausedFeatures();
        assertEq(paused.length, 0, "no feature paused at creation");

        // The Asset multiplier is the identity, so totalSupply is raw.
        assertEq(IB20Asset(address(t)).multiplier(), IB20Asset(address(t)).WAD_PRECISION(), "identity multiplier");
    }

    /// GATE 6. A simulated transfer, approval, contest burn, and Safe approval
    ///         updates the live metadata and reduces supply EXACTLY ONCE.
    function testGate6_TransferApproveBurnAndApproveUpdatesMetadataAndReducesSupplyOnce() public {
        VOIDB20Bootstrapper b = _deploy();
        IB20 t = IB20(b.token());
        VOIDB20SkinController c = b.controller();

        address burner = makeAddr("gate6-burner");
        uint256 amount = c.INITIAL_BURN();

        // transfer
        vm.prank(address(safe));
        t.transfer(burner, 10_000_000 ether);
        assertEq(t.balanceOf(burner), 10_000_000 ether, "transfer");

        vm.prank(address(safe));
        c.setRenamePaused(false);

        string memory nm = "LIVE GATE";
        string memory sy = "GATE";
        string memory uri = "ipfs://bafyLiveGateMetadata";
        bytes32 img = keccak256("gate-image");
        bytes32 salt = keccak256("gate-salt");
        uint256 id = c.nextBurnId();
        bytes32 commitment = c.proposalCommitment(id, burner, amount, nm, sy, img, keccak256(bytes(uri)), salt);

        uint256 supplyBefore = t.totalSupply();

        // approval
        vm.prank(burner);
        t.approve(address(c), amount);
        assertEq(t.allowance(burner, address(c)), amount, "exact allowance");

        // contest burn
        vm.prank(burner);
        c.burnForRename(id, amount, commitment);

        assertEq(t.totalSupply(), supplyBefore - amount, "supply reduced by exactly the burn, once");
        assertEq(t.balanceOf(address(c)), 0, "controller retains nothing");
        assertEq(t.allowance(burner, address(c)), 0, "allowance fully consumed");
        assertEq(c.destroyedSupply(), amount, "destroyedSupply");

        // Safe approval -> metadata update
        vm.prank(address(safe));
        c.approveRename(id, nm, sy, uri, img, salt);

        assertEq(t.name(), nm, "live name updated");
        assertEq(t.symbol(), sy, "live symbol updated");
        assertEq(t.contractURI(), uri, "live contract URI updated");
        assertEq(c.activeSlot().burner, address(0), "slot consumed");

        // and the metadata update did NOT touch supply again
        assertEq(t.totalSupply(), supplyBefore - amount, "supply unchanged by the metadata update");
        assertEq(t.supplyCap(), ORIGINAL_SUPPLY, "cap unchanged by the burn");

        // The rename rotated the EIP-712 domain separator (finding M-2).
        emit log_named_bytes32("DOMAIN_SEPARATOR after rename", t.DOMAIN_SEPARATOR());
    }

    /// GATE 7. The simulation makes no persistent chain-state change and
    ///         produces no broadcast transaction. Asserted structurally: this
    ///         file contains no vm.broadcast / vm.startBroadcast, no
    ///         vm.rpcUrl / createFork, and no vm.envUint("PRIVATE_KEY").
    ///         Forge's in-process EVM state is discarded at the end of each
    ///         test; nothing here can reach a network.
    function testGate7_NoBroadcastAndNoPersistentChainState() public {
        // Two distinct salts produce two distinct tokens inside one test.
        VOIDB20Bootstrapper b1 = _deploy();
        VOIDB20Bootstrapper b2 = new VOIDB20Bootstrapper(
            address(safe),
            StdPrecompiles.B20_FACTORY,
            keccak256("second-salt"),
            INITIAL_NAME,
            INITIAL_SYMBOL,
            GENESIS_URI
        );
        assertTrue(b1.token() != b2.token(), "distinct salts, distinct tokens");

        // A malformed direct create is rejected by the live factory rather
        // than silently producing a token.
        vm.expectRevert();
        StdPrecompiles.B20_FACTORY.createB20(IB20Factory.B20Variant.ASSET, SALT, bytes(""), new bytes[](0));

        // No fork is active: block.chainid is forge's default local chain, not
        // Base Mainnet. This is stated so the report cannot overclaim.
        emit log_named_uint("chainid of this simulation", block.chainid);
        assertTrue(block.chainid != 8453, "NOT forked against Base Mainnet state");
    }
}
