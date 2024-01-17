// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { AxiomVm } from "./AxiomVm.sol";

import { IAxiomV2Core } from "../interfaces/core/IAxiomV2Core.sol";
import { IAxiomV2Query } from "../interfaces/query/IAxiomV2Query.sol";
import { IAxiomV2Client } from "../interfaces/client/IAxiomV2Client.sol";
import { AxiomV2Addresses } from "../client/AxiomV2Addresses.sol";

abstract contract AxiomTest is Test {
    address public axiomV2CoreAddress;
    address public axiomV2QueryAddress;

    IAxiomV2Core public axiomV2Core;
    IAxiomV2Query public axiomV2Query;

    string public inputPath;

    bytes32 public querySchema;
    bytes public callbackExtraData;

    IAxiomV2Query.AxiomV2FeeData public feeData;

    AxiomVm axiomVm;

    constructor() {
        feeData = IAxiomV2Query.AxiomV2FeeData({
            maxFeePerGas: 25 gwei,
            callbackGasLimit: 1_000_000,
            overrideAxiomQueryFee: 0
        });
        callbackExtraData = bytes("");
    }

    function _createSelectForkAndSetupAxiom(string memory urlOrAlias, uint256 forkBlock) internal {
        vm.createSelectFork(urlOrAlias, forkBlock);
        uint64 chainId = uint64(block.chainid);

        axiomV2CoreAddress = AxiomV2Addresses.axiomV2CoreAddress(chainId);
        axiomV2Core = IAxiomV2Core(axiomV2CoreAddress);

        axiomV2QueryAddress = AxiomV2Addresses.axiomV2QueryAddress(chainId);
        axiomV2Query = IAxiomV2Query(axiomV2QueryAddress);

        vm.makePersistent(axiomV2CoreAddress);
        vm.makePersistent(axiomV2QueryAddress);

        axiomVm = new AxiomVm(axiomV2QueryAddress, urlOrAlias, true);
    }
}
