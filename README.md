## Axiom V2 Client

This repo contains client smart contracts, interfaces, and testing utilities for applications integrating Axiom V2. To learn more about how to integrate Axiom into your application, see the [developer docs](https://docs.axiom.xyz). For the complete Axiom V2 smart contract code, see the smart contract repo [here](https://github.com/axiom-crypto/axiom-v2-contracts).

## Installation

To use smart contracts or test utilities from this repo in your **external Foundry project**, run:

```bash
forge install axiom-crypto/axiom-v2-client
```

Add `@axiom-v2-client/=lib/axiom-v2-client/src` in `remappings.txt`.

## Usage

Once installed, you can use the contracts in this library by importing them. All interfaces are available under `@axiom-v2-client/interfaces`. For security, you should use the installed code **as-is**; we do not recommend copy-pasting from other sources or modifying yourself.

See our [quickstart repo](https://github.com/axiom-crypto/axiom-quickstart) for a minimal example using both `AxiomV2Client` and `AxiomTest`.

#### Implementing a client for Axiom V2

To integrate your application with Axiom, you should inherit from `AxiomV2Client` in your contract:

```solidity
pragma solidity ^0.8.0;

import { AxiomV2Client } from "@axiom-v2-client/client/AxiomV2Client.sol";

contract AverageBalance is AxiomV2Client {
    bytes32 immutable QUERY_SCHEMA;
    uint64 immutable SOURCE_CHAIN_ID;

    constructor(address _axiomV2QueryAddress, uint64 _callbackSourceChainId, bytes32 _querySchema)
        AxiomV2Client(_axiomV2QueryAddress)
    {
        QUERY_SCHEMA = _querySchema;
        SOURCE_CHAIN_ID = _callbackSourceChainId;
    }

    function _validateAxiomV2Call(
        AxiomCallbackType, // callbackType,
        uint64 sourceChainId,
        address, // caller,
        bytes32 querySchema,
        uint256, // queryId,
        bytes calldata // extraData
    ) internal view override {
        require(sourceChainId == SOURCE_CHAIN_ID, "Source chain ID does not match");
        require(querySchema == QUERY_SCHEMA, "Invalid query schema");
    }

    function _axiomV2Callback(
        uint64, // sourceChainId,
        address, // caller,
        bytes32, // querySchema,
        uint256, // queryId,
        bytes32[] calldata axiomResults,
        bytes calldata // extraData
    ) internal override {
        // <Implement your application logic with axiomResults>
    }
}
```

#### Testing with `AxiomTest` Foundry tests

To test your code, you can use `AxiomTest.sol` in place of `forge-std/Test.sol`. This extension to the standard Foundry test library provides Axiom-specific cheatcodes accessible to your Foundry tests. Using these cheatcodes requires the Axiom Client SDK, which is provided via the npm package `@axiom-crypto/client@0.2.2-rc2.2-alpha.1`; you can install this in your Foundry project using

```bash
npm install @axiom-crypto/client@0.2.2-rc2.2-alpha.1
yarn add @axiom-crypto/client@0.2.2-rc2.2-alpha.1
pnpm add @axiom-crypto/client@0.2.2-rc2.2-alpha.1
```

Once you have written an Axiom circuit, you can test it against your client smart contract using the `AxiomVm` cheatcodes `sendQueryArgs`, `fulfillCallbackArgs`,  `prankCallback`, and `prankOffchainCallback`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { AxiomTest, AxiomVm } from "../src/test/AxiomTest.sol";
import { IAxiomV2Query } from "../src/interfaces/query/IAxiomV2Query.sol";

import { AverageBalance } from "./example/AverageBalance.sol";

contract AverageBalanceTest is AxiomTest {
    AverageBalance public averageBalance;

    function setUp() public {
        _createSelectForkAndSetupAxiom("sepolia", 5_057_320);

        inputPath = "test/circuit/input.json";
        querySchema = axiomVm.compile("test/circuit/average.circuit.ts", inputPath);
        averageBalance = new AverageBalance(axiomV2QueryAddress, uint64(block.chainid), querySchema);
    }

    function test_axiomSendQuery() public {
        axiomVm.getArgsAndSendQuery(
            inputPath,
            address(averageBalance),
            callbackExtraData,
            feeData,
            msg.sender
        );
    }

    function test_axiomSendQueryWithArgs() public {
        AxiomVm.AxiomSendQueryArgs memory args = axiomVm.sendQueryArgs(
            inputPath, address(averageBalance), callbackExtraData, feeData
        );
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
        axiomVm.prankCallback(
            inputPath,
            address(averageBalance),
            callbackExtraData,
            feeData,
            msg.sender
        );
    }

    function test_AxiomCallbackWithArgs() public {
        AxiomVm.AxiomFulfillCallbackArgs memory args = axiomVm.fulfillCallbackArgs(
            inputPath,
            address(averageBalance),
            callbackExtraData,
            feeData,
            msg.sender
        );
        axiomVm.prankCallback(args);
    }

    function test_axiomOffchainCallback() public {
        axiomVm.prankOffchainCallback(
            inputPath,
            address(averageBalance),
            callbackExtraData,
            feeData,
            msg.sender
        );
    }

    function test_AxiomOffchainCallbackWithArgs() public {
        AxiomVm.AxiomFulfillCallbackArgs memory args = axiomVm.fulfillCallbackArgs(
            inputPath,
            address(averageBalance),
            callbackExtraData,
            feeData,
            msg.sender
        );
        axiomVm.prankOffchainCallback(args);
    }
}

```

## Running this repo for development

This repo contains both Foundry and Javascript packages. To install, run:

```bash
forge install
pnpm install     # or `npm install` or `yarn install`
```
