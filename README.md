## Axiom V2 Periphery

This repo contains client smart contracts and interfaces for applications integrating Axiom V2. To learn more about how to integrate Axiom into your application, see the [developer docs](https://docs.axiom.xyz). For the complete Axiom V2 smart contract code, see the smart contract repo [here](https://github.com/axiom-crypto/axiom-v2-contracts).

## Installation

To use smart contracts or test utilities from this repo in your **external Foundry project**, run:

```bash
forge install axiom-crypto/axiom-v2-periphery
```

Add `@axiom-crypto/v2-periphery/=lib/axiom-v2-periphery/src` in `remappings.txt`.

## Usage

Once installed, you can use the contracts in this library by importing them. All interfaces are available under `@axiom-crypto/v2-periphery/interfaces`. For security, you should use the installed code **as-is**; we do not recommend copy-pasting from other sources or modifying yourself.

See our [quickstart repo](https://github.com/axiom-crypto/axiom-quickstart) for a minimal example.

#### Implementing a client for Axiom V2

To integrate your application with Axiom, you should inherit from `AxiomV2Client` in your contract:

```solidity
pragma solidity ^0.8.0;

import { AxiomV2Client } from "@axiom-crypto/v2-periphery/client/AxiomV2Client.sol";

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

#### Testing with `axiom-std` Foundry tests

To test your code, you can use `axiom-std`, an extension to the standard Foundry test library that provides Axiom-specific cheatcodes accessible to your Foundry tests. See our [axiom-std repo](https://github.com/axiom-crypto/axiom-std) for further documentation and our [quickstart repo](https://github.com/axiom-crypto/axiom-quickstart) for a minimal example using both `AxiomV2Client` and `axiom-std`.

## Running this repo for development

This repo contains both Foundry packages. To install, run:

```bash
forge install
```
