// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { MAINNET_CHAIN_ID, SEPOLIA_CHAIN_ID } from "../libraries/configuration/AxiomV2Configuration.sol";

/// @title AxiomV2Addresses
/// @notice AxiomV2Addresses is a library that contains the addresses of deployed Axiom V2 contracts
library AxiomV2Addresses {
    address public constant AXIOM_V2_CORE_ADDRESS = 0x69963768F8407dE501029680dE46945F838Fc98B;
    address public constant AXIOM_V2_QUERY_ADDRESS = 0x83c8c0B395850bA55c830451Cfaca4F2A667a983;

    address public constant SEPOLIA_AXIOM_V2_CORE_MOCK_ADDRESS = 0x69963768F8407dE501029680dE46945F838Fc98B;
    address public constant SEPOLIA_AXIOM_V2_QUERY_MOCK_ADDRESS = 0x83c8c0B395850bA55c830451Cfaca4F2A667a983;

    /// @dev Error returned if the corresponding Axiom V2 contract does not exist for the requested chainId
    error ContractDoesNotExistForChainId();

    /// @dev Error returned if the corresponding Axiom V2 contract has not yet been deployed
    error ContractNotYetDeployed();

    /// @notice Returns the address of the AxiomV2Query contract on the chain corresponding to `chainId`
    /// @param chainId The chainId of the AxiomV2Query contract
    /// @return addr The address of the AxiomV2Query contract
    function axiomV2QueryAddress(uint64 chainId) public pure returns (address addr) {
        if (chainId == MAINNET_CHAIN_ID) {
            addr = AXIOM_V2_QUERY_ADDRESS;
        } else {
            revert ContractDoesNotExistForChainId();
        }
        if (addr == address(0)) {
            revert ContractNotYetDeployed();
        }
    }

    /// @notice Returns the address of the AxiomV2QueryMock contract on the chain corresponding to `chainId`
    /// @param chainId The chainId of the AxiomV2QueryMock contract
    /// @return addr The address of the AxiomV2QueryMock contract
    function axiomV2QueryMockAddress(uint64 chainId) public pure returns (address addr) {
        if (chainId == MAINNET_CHAIN_ID) {
            revert ContractDoesNotExistForChainId();
        } else if (chainId == SEPOLIA_CHAIN_ID) {
            addr = SEPOLIA_AXIOM_V2_QUERY_MOCK_ADDRESS;
        } else {
            revert ContractDoesNotExistForChainId();
        }
        if (addr == address(0)) {
            revert ContractNotYetDeployed();
        }
    }

    /// @notice Returns the address of the AxiomV2Core contract on the chain corresponding to `chainId`
    /// @param chainId The chainId of the AxiomV2Core contract
    /// @return addr The address of the AxiomV2Core contract
    function axiomV2CoreAddress(uint64 chainId) public pure returns (address addr) {
        if (chainId == MAINNET_CHAIN_ID) {
            addr = AXIOM_V2_CORE_ADDRESS;
        } else {
            revert ContractDoesNotExistForChainId();
        }
        if (addr == address(0)) {
            revert ContractNotYetDeployed();
        }
    }

    /// @notice Returns the address of the AxiomV2CoreMock contract on the chain corresponding to `chainId`
    /// @param chainId The chainId of the AxiomV2CoreMock contract
    /// @return addr The address of the AxiomV2CoreMock contract
    function axiomV2CoreMockAddress(uint64 chainId) public pure returns (address addr) {
        if (chainId == MAINNET_CHAIN_ID) {
            revert ContractDoesNotExistForChainId();
        } else if (chainId == SEPOLIA_CHAIN_ID) {
            addr = SEPOLIA_AXIOM_V2_CORE_MOCK_ADDRESS;
        } else {
            revert ContractDoesNotExistForChainId();
        }
        if (addr == address(0)) {
            revert ContractNotYetDeployed();
        }
    }
}
