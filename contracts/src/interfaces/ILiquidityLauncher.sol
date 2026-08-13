// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

struct Distribution {
    address strategy;
    uint128 amount;
    bytes configData;
}

interface ILiquidityLauncher {
    function depositToken(address token, uint160 amount) external payable;
    function distributeToken(address token, Distribution memory distribution, bytes32 salt) external payable;
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);
}

interface IPermit2AllowanceTransfer {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}
