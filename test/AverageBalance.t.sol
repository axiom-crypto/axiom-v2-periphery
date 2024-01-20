// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { AxiomTest, AxiomVm } from "../src/test/AxiomTest.sol";
import { IAxiomV2Query } from "../src/interfaces/query/IAxiomV2Query.sol";

import { AverageBalance } from "./example/AverageBalance.sol";

contract AverageBalanceTest is AxiomTest {
    AverageBalance public averageBalance;

    function setUp() public {
        _createSelectForkAndSetupAxiom("sepolia", 5_103_100);

        inputPath = "test/circuit/data/inputs.json";
        querySchema = axiomVm.compile("test/circuit/average.circuit.ts", inputPath);
        averageBalance = new AverageBalance(axiomV2QueryAddress, uint64(block.chainid), querySchema);
    }

    function test_axiomSendQuery() public {
        axiomVm.getArgsAndSendQuery(inputPath, address(averageBalance), callbackExtraData, feeData, msg.sender);
    }

    function test_axiomSendQueryWithArgs() public {
        AxiomVm.AxiomSendQueryArgs memory args =
            axiomVm.sendQueryArgs(inputPath, address(averageBalance), callbackExtraData, feeData);
        axiomV2Query.sendQuery{ value: args.value }(
            args.sourceChainId,
            args.dataQueryHash,
            args.computeQuery,
            args.callback,
            args.feeData,
            args.userSalt,
            args.refundee,
            args.dataQuery
        );
    }

    function test_axiomCallback() public {
        axiomVm.prankCallback(inputPath, address(averageBalance), callbackExtraData, feeData, msg.sender);
    }

    function test_AxiomCallbackWithArgs() public {
        AxiomVm.AxiomFulfillCallbackArgs memory args =
            axiomVm.fulfillCallbackArgs(inputPath, address(averageBalance), callbackExtraData, feeData, msg.sender);
        axiomVm.prankCallback(args);
    }

    function test_axiomOffchainCallback() public {
        axiomVm.prankOffchainCallback(inputPath, address(averageBalance), callbackExtraData, feeData, msg.sender);
    }

    function test_AxiomOffchainCallbackWithArgs() public {
        AxiomVm.AxiomFulfillCallbackArgs memory args =
            axiomVm.fulfillCallbackArgs(inputPath, address(averageBalance), callbackExtraData, feeData, msg.sender);
        axiomVm.prankOffchainCallback(args);
    }

    function test_compileNotMocked() public {
        axiomVm.setMock(false);
        bytes32 querySchema = axiomVm.compile("test/circuit/average.circuit.ts", inputPath);
        require(
            querySchema != bytes32(0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef), "compile failed"
        );
    }
}
