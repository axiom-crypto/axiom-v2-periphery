// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { IAxiomV2Query } from "../interfaces/query/IAxiomV2Query.sol";
import { IAxiomV2Client } from "../interfaces/client/IAxiomV2Client.sol";
import { AxiomV2Addresses } from "../client/AxiomV2Addresses.sol";

contract AxiomVm is Test {
    /// @dev Paths used to store temporary files used for CLI IO
    string constant COMPILED_PATH = ".axiom/compiled.json";
    string constant QUERY_PATH = ".axiom/query.json";
    string constant OUTPUT_PATH = ".axiom/output.json";

    /// @dev Used to store inputs and outputs from FFI
    string public compiledString;
    string public queryString;
    string public outputString;

    address public axiomV2QueryAddress;

    constructor(address _axiomV2QueryAddress) {
        axiomV2QueryAddress = _axiomV2QueryAddress;
    }

    struct AxiomSendQueryArgs {
        uint64 sourceChainId;
        bytes32 dataQueryHash;
        IAxiomV2Query.AxiomV2ComputeQuery computeQuery;
        IAxiomV2Query.AxiomV2Callback callback;
        IAxiomV2Query.AxiomV2FeeData feeData;
        bytes32 userSalt;
        address refundee;
        bytes dataQuery;
        uint256 value;
    }

    struct AxiomFulfillCallbackArgs {
        uint64 sourceChainId;
        address caller;
        bytes32 querySchema;
        uint256 queryId;
        bytes32[] axiomResults;
        bytes extraData;
        uint256 gasLimit;
        address callbackAddress;
    }

    /**
     * @dev Compiles a circuit using the Axiom CLI via FFI
     * @param circuitPath path to the circuit file
     * @param inputPath path to the input file
     * @param urlOrAlias URL or alias of the provider
     * @return querySchema
     */
    function compile(string memory circuitPath, string memory inputPath, string memory urlOrAlias)
        public
        returns (bytes32 querySchema)
    {
        _validateAxiomSetup();
        string[] memory cli = new string[](13);
        cli[0] = "npx";
        cli[1] = "axiom";
        cli[2] = "circuit";
        cli[3] = "compile";
        cli[4] = circuitPath;
        cli[5] = "--provider";
        cli[6] = vm.rpcUrl(urlOrAlias);
        cli[7] = "--inputs";
        cli[8] = inputPath;
        cli[9] = "--outputs";
        cli[10] = COMPILED_PATH;
        cli[11] = "--function";
        cli[12] = "circuit";
        vm.ffi(cli);

        string memory artifact = vm.readFile(COMPILED_PATH);
        compiledString = artifact;
        querySchema = bytes32(vm.parseJson(artifact, ".querySchema"));
    }

    /**
     * @dev Generates args for the sendQuery function
     * @param circuitPath path to the circuit file
     * @param inputPath path to the input file
     * @param urlOrAlias the URL or alias of the RPC provider
     * @param callback the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param sourceChainId the source chain ID
     * @param feeData the fee data
     * @return args the sendQuery args
     */
    function sendQueryArgs(
        string memory circuitPath,
        string memory inputPath,
        string memory urlOrAlias,
        address callback,
        bytes memory callbackExtraData,
        uint64 sourceChainId,
        IAxiomV2Query.AxiomV2FeeData memory feeData
    ) public returns (AxiomSendQueryArgs memory args) {
        _prove(circuitPath, inputPath, urlOrAlias, sourceChainId);
        string memory _queryString = _queryParams(urlOrAlias, callback, callbackExtraData, sourceChainId, feeData);
        bytes memory calldataBytes = abi.decode(vm.parseJson(_queryString, ".calldata"), (bytes));

        // use of `this` is necessary to convert memory to calldata and allow slicing
        args = this._parseSendQueryArgs(calldataBytes);
        args.value = vm.parseJsonUint(queryString, ".value");
    }

    /**
     * @dev Generates arguments for the fulfillCallback function
     * @param circuitPath path to the circuit file
     * @param inputPath path to the input file
     * @param urlOrAlias the URL or alias of the RPC provider
     * @param callback the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param sourceChainId the source chain ID
     * @param feeData the fee data
     * @param caller the address of the caller
     * @return args the fulfillCallback args
     */
    function fulfillCallbackArgs(
        string memory circuitPath,
        string memory inputPath,
        string memory urlOrAlias,
        address callback,
        bytes memory callbackExtraData,
        uint64 sourceChainId,
        IAxiomV2Query.AxiomV2FeeData memory feeData,
        address caller
    ) public returns (AxiomFulfillCallbackArgs memory args) {
        string memory _outputString = _prove(circuitPath, inputPath, urlOrAlias, sourceChainId);
        string memory _queryString = _queryParams(urlOrAlias, callback, callbackExtraData, sourceChainId, feeData);

        AxiomSendQueryArgs memory _sendQueryArgs =
            this._parseSendQueryArgs(abi.decode(vm.parseJson(_queryString, ".calldata"), (bytes)));
        args = AxiomFulfillCallbackArgs({
            sourceChainId: sourceChainId,
            caller: caller,
            querySchema: abi.decode(vm.parseJson(compiledString, ".querySchema"), (bytes32)),
            queryId: vm.parseJsonUint(_queryString, ".queryId"),
            axiomResults: abi.decode(vm.parseJson(_outputString, ".computeResults"), (bytes32[])),
            extraData: _sendQueryArgs.callback.extraData,
            gasLimit: feeData.callbackGasLimit,
            callbackAddress: callback
        });
    }

    /**
     * @dev Fulfills the callback for an onchain query
     * @param args the arguments for the callback
     */
    function prankCallback(AxiomFulfillCallbackArgs memory args) public {
        vm.prank(axiomV2QueryAddress);
        IAxiomV2Client(args.callbackAddress).axiomV2Callback{ gas: args.gasLimit }(
            args.sourceChainId, args.caller, args.querySchema, args.queryId, args.axiomResults, args.extraData
        );
    }

    /**
     * @dev Generates the fulfill callback args and and fulfills the onchain query
     * @param circuitPath path to the circuit file
     * @param inputPath path to the input file
     * @param urlOrAlias the URL or alias of the RPC provider
     * @param callback the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param sourceChainId the source chain ID
     * @param feeData the fee data
     * @param caller the address of the caller
     */
    function prankCallback(
        string memory circuitPath,
        string memory inputPath,
        string memory urlOrAlias,
        address callback,
        bytes memory callbackExtraData,
        uint64 sourceChainId,
        IAxiomV2Query.AxiomV2FeeData memory feeData,
        address caller
    ) public {
        AxiomFulfillCallbackArgs memory args = fulfillCallbackArgs(
            circuitPath, inputPath, urlOrAlias, callback, callbackExtraData, sourceChainId, feeData, caller
        );
        prankCallback(args);
    }

    /**
     * @dev Fulfills the callback for an offchain query
     * @param args the arguments for the callback
     */
    function prankOffchainCallback(AxiomFulfillCallbackArgs memory args) public {
        vm.prank(axiomV2QueryAddress);
        IAxiomV2Client(args.callbackAddress).axiomV2OffchainCallback{ gas: args.gasLimit }(
            args.sourceChainId, args.caller, args.querySchema, args.queryId, args.axiomResults, args.extraData
        );
    }

    /**
     * @dev Generates the fulfill callback args and fulfills the offchain query
     * @param circuitPath path to the circuit file
     * @param inputPath path to the input file
     * @param urlOrAlias the URL or alias of the RPC provider
     * @param callback the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param sourceChainId the source chain ID
     * @param feeData the fee data
     * @param caller the address of the caller
     */
    function prankOffchainCallback(
        string memory circuitPath,
        string memory inputPath,
        string memory urlOrAlias,
        address callback,
        bytes memory callbackExtraData,
        uint64 sourceChainId,
        IAxiomV2Query.AxiomV2FeeData memory feeData,
        address caller
    ) public {
        AxiomFulfillCallbackArgs memory args = fulfillCallbackArgs(
            circuitPath, inputPath, urlOrAlias, callback, callbackExtraData, sourceChainId, feeData, caller
        );
        prankOffchainCallback(args);
    }

    /**
     * @dev Generates sendQueryArgs and sends a query to the AxiomV2Query contract.
     * @param circuitPath path to the circuit file
     * @param inputPath path to the input file
     * @param urlOrAlias the URL or alias of the RPC provider
     * @param callback the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param sourceChainId the source chain ID
     * @param feeData the fee data
     * @param caller the address of the caller
     */
    function getArgsAndSendQuery(
        string memory circuitPath,
        string memory inputPath,
        string memory urlOrAlias,
        address callback,
        bytes memory callbackExtraData,
        uint64 sourceChainId,
        IAxiomV2Query.AxiomV2FeeData memory feeData,
        address caller
    ) public {
        AxiomVm.AxiomSendQueryArgs memory args =
            sendQueryArgs(circuitPath, inputPath, urlOrAlias, callback, callbackExtraData, sourceChainId, feeData);
        vm.prank(caller);
        IAxiomV2Query(axiomV2QueryAddress).sendQuery{ value: args.value }(
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

    function _parseBoolean(string memory value) internal pure returns (bool) {
        return vm.parseUint(value) == 1;
    }

    function _validateAxiomSetup() internal {
        string[] memory npxCheck = new string[](3);
        npxCheck[0] = "sh";
        npxCheck[1] = "-c";
        npxCheck[2] = "command -v npx >/dev/null 2>&1 && echo 1 || echo 0";
        bytes memory npxOutput = vm.ffi(npxCheck);
        require(_parseBoolean(string(npxOutput)), "NPX is not installed.");

        string[] memory axiomCheck = new string[](3);
        axiomCheck[0] = "sh";
        axiomCheck[1] = "-c";
        axiomCheck[2] = "npm list @axiom-crypto/client@0.2.0-rc2.0 >/dev/null 2>&1 && echo 1 || echo 0";
        bytes memory axiomOutput = vm.ffi(axiomCheck);
        require(_parseBoolean(string(axiomOutput)), "Axiom client not installed");
    }

    function _prove(string memory circuitPath, string memory inputPath, string memory urlOrAlias, uint64 sourceChainId)
        internal
        returns (string memory output)
    {
        _validateAxiomSetup();
        vm.writeFile(COMPILED_PATH, compiledString);
        string[] memory cli = new string[](18);
        cli[0] = "npx";
        cli[1] = "axiom";
        cli[2] = "circuit";
        cli[3] = "prove";
        cli[4] = circuitPath;
        cli[5] = "--mock";
        cli[6] = "--sourceChainId";
        cli[7] = vm.toString(sourceChainId);
        cli[8] = "--compiled";
        cli[9] = COMPILED_PATH;
        cli[10] = "--provider";
        cli[11] = vm.rpcUrl(urlOrAlias);
        cli[12] = "--inputs";
        cli[13] = inputPath;
        cli[14] = "--outputs";
        cli[15] = OUTPUT_PATH;
        cli[16] = "--function";
        cli[17] = "circuit";
        vm.ffi(cli);
        output = vm.readFile(OUTPUT_PATH);
        outputString = output;
    }

    function _queryParams(
        string memory urlOrAlias,
        address callback,
        bytes memory callbackExtraData,
        uint64 sourceChainId,
        IAxiomV2Query.AxiomV2FeeData memory feeData
    ) internal returns (string memory output) {
        _validateAxiomSetup();
        vm.writeFile(OUTPUT_PATH, outputString);
        string[] memory cli = new string[](22);
        cli[0] = "npx";
        cli[1] = "axiom";
        cli[2] = "circuit";
        cli[3] = "query-params";
        cli[4] = vm.toString(callback); // the callback target address
        cli[5] = "--sourceChainId";
        cli[6] = vm.toString(sourceChainId);
        cli[7] = "--refundAddress";
        cli[8] = vm.toString(msg.sender);
        cli[9] = "--callbackExtraData";
        cli[10] = vm.toString(callbackExtraData);
        cli[11] = "--maxFeePerGas";
        cli[12] = vm.toString(feeData.maxFeePerGas);
        cli[13] = "--callbackGasLimit";
        cli[14] = vm.toString(feeData.callbackGasLimit);
        cli[15] = "--provider";
        cli[16] = vm.rpcUrl(urlOrAlias);
        cli[17] = "--proven";
        cli[18] = OUTPUT_PATH;
        cli[19] = "--outputs";
        cli[20] = QUERY_PATH;
        cli[21] = "--calldata";
        vm.ffi(cli);
        output = vm.readFile(QUERY_PATH);
        queryString = output;
    }

    /**
     * @dev Parses AxiomSendQueryArgs from the CLI calldata bytes output
     * @param calldataBytes the calldata bytes output from the CLI
     * @return args the AxiomSendQueryArgs
     */
    function _parseSendQueryArgs(bytes calldata calldataBytes) public pure returns (AxiomSendQueryArgs memory args) {
        (
            uint64 sourceChainId,
            bytes32 dataQueryHash,
            IAxiomV2Query.AxiomV2ComputeQuery memory computeQuery,
            IAxiomV2Query.AxiomV2Callback memory callback,
            IAxiomV2Query.AxiomV2FeeData memory feeData,
            bytes32 userSalt,
            address refundee,
            bytes memory dataQuery
        ) = abi.decode(
            calldataBytes[4:],
            (
                uint64,
                bytes32,
                IAxiomV2Query.AxiomV2ComputeQuery,
                IAxiomV2Query.AxiomV2Callback,
                IAxiomV2Query.AxiomV2FeeData,
                bytes32,
                address,
                bytes
            )
        );
        args = AxiomSendQueryArgs({
            sourceChainId: sourceChainId,
            dataQueryHash: dataQueryHash,
            computeQuery: computeQuery,
            callback: callback,
            feeData: feeData,
            userSalt: userSalt,
            refundee: refundee,
            dataQuery: dataQuery,
            value: 0
        });
    }
}
