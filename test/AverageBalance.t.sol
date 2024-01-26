// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../src/test/AxiomTest.sol";

import {AverageBalance} from "./example/AverageBalance.sol";

contract AverageBalanceTest is AxiomTest {
    using Axiom for Query;

    struct Input {
        uint256 blockNumber;
        uint256 _address;
    }

    AverageBalance public averageBalance;
    Input public defaultInput;
    bytes32 public querySchema;

    bytes public callbackExtraData;
    IAxiomV2Query.AxiomV2FeeData public feeData;

    function setUp() public {
        _createSelectForkAndSetupAxiom("sepolia", 5_103_100);

        defaultInput = Input({
            blockNumber: 4205938,
            _address: uint256(
                uint160(0x8018fe32fCFd3d166E8b4c4E37105318A84BA11b)
            )
        });
        querySchema = axiomVm.readCircuit(
            "test/circuit/average.circuit.ts",
            abi.encode(defaultInput)
        );
        averageBalance = new AverageBalance(
            axiomV2QueryAddress,
            uint64(block.chainid),
            querySchema
        );

        feeData = IAxiomV2Query.AxiomV2FeeData({
            maxFeePerGas: 25 gwei,
            callbackGasLimit: 1_000_000,
            overrideAxiomQueryFee: 0
        });
        callbackExtraData = bytes("");
    }

    function test_e2e_example() public {
        Query memory q = query(
            querySchema,
            abi.encode(defaultInput),
            address(averageBalance)
        );
        bytes32[] memory results = q.send();
        assertEq(results.length, 3);
        uint256 blockNumber = uint256(results[0]);
        address addr = address(uint160(uint256(results[1])));
        uint256 avg = uint256(results[2]);
        assertEq(avg, averageBalance.provenAverageBalances(blockNumber, addr));
    }

    function test_SendQuery() public {
        axiomVm.getArgsAndSendQuery(
            querySchema,
            abi.encode(defaultInput),
            address(averageBalance)
        );
    }

    function test_SendQueryWithArgs() public {
        (QueryArgs memory args, ) = axiomVm.sendQueryArgs(
            querySchema,
            abi.encode(defaultInput),
            address(averageBalance),
            callbackExtraData,
            feeData
        );
        axiomV2Query.sendQuery{value: args.value}(
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

    function test_callback() public {
        axiomVm.prankCallback(
            querySchema,
            abi.encode(defaultInput),
            address(averageBalance),
            callbackExtraData,
            feeData,
            msg.sender
        );
    }

    function test_callbackWithArgs() public {
        FulfillCallbackArgs memory args = axiomVm.fulfillCallbackArgs(
            querySchema,
            abi.encode(defaultInput),
            address(averageBalance),
            callbackExtraData,
            feeData,
            msg.sender
        );
        axiomVm.prankCallback(args);
    }

    function test_offchainCallback() public {
        axiomVm.prankOffchainCallback(
            querySchema,
            abi.encode(defaultInput),
            address(averageBalance),
            callbackExtraData,
            feeData,
            msg.sender
        );
    }

    function test_offchainCallbackWithArgs() public {
        FulfillCallbackArgs memory args = axiomVm.fulfillCallbackArgs(
            querySchema,
            abi.encode(defaultInput),
            address(averageBalance),
            callbackExtraData,
            feeData,
            msg.sender
        );
        axiomVm.prankOffchainCallback(args);
    }

    // function test_compileNotMocked() public {
    //     axiomVm.setMock(false);
    //     bytes32 querySchema = axiomVm.readCircuit("test/circuit/average.circuit.ts", inputPath);
    //     require(
    //         querySchema != bytes32(0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef), "compile failed"
    //     );
    // }
}
