// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IAxiomV2Query} from "../interfaces/query/IAxiomV2Query.sol";
import {IAxiomV2Client} from "../interfaces/client/IAxiomV2Client.sol";
import {AxiomV2Addresses} from "../client/AxiomV2Addresses.sol";

contract AxiomVm is Test {
    /// @dev Paths used to store temporary files used for CLI IO
    string constant COMPILED_PATH = ".axiom/compiled.json";
    string constant QUERY_PATH = ".axiom/query.json";
    string constant OUTPUT_PATH = ".axiom/output.json";
    string constant CIRCUIT_HASH_PATH = ".axiom/circuitHash.json";

    /// @dev Used to store inputs and outputs from FFI
    string public compiledString;
    string public queryString;
    string public outputString;

    /// @dev Axiom CLI version to use
    string constant CLI_VERSION = "2.0";
    string private constant CLI_VERSION_CHECK_CMD =
        string(
            abi.encodePacked(
                "npm list @axiom-crypto/client | grep -q '@axiom-crypto/client@",
                CLI_VERSION,
                "' && echo 1 || echo 0"
            )
        );
    string private constant CLI_VERSION_ERROR =
        string(
            abi.encodePacked("Axiom client v", CLI_VERSION, ".x not installed")
        );

    string urlOrAlias;
    bool compiled;
    string circuitPath;
    bool isMock;

    address public axiomV2QueryAddress;

    constructor(
        address _axiomV2QueryAddress,
        string memory _urlOrAlias,
        bool _isMock
    ) {
        axiomV2QueryAddress = _axiomV2QueryAddress;
        urlOrAlias = _urlOrAlias;
        isMock = _isMock;
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
        bytes callbackExtraData;
        uint256 gasLimit;
        address callbackTarget;
    }

    /**
     * @dev Compiles a circuit using the Axiom CLI via FFI
     * @param _circuitPath path to the circuit file
     * @param inputPath path to the input file
     * @return querySchema
     */
    function compile(
        string memory _circuitPath,
        string memory inputPath
    ) public returns (bytes32 querySchema) {
        circuitPath = _circuitPath;       
        compiled = true;
        _validateAxiomSetup();
        bytes32 circuitHash = bytes32(0);
        // The following throws: [FAIL. Reason: Setup failed: Invalid data] but I'm not sure why
        // if(vm.isFile(CIRCUIT_HASH_PATH)) {
            string memory circuitHashFile = vm.readFile(CIRCUIT_HASH_PATH);
            circuitHash = bytes32(vm.parseJson(circuitHashFile, ".hash"));
        // }

        bytes32 _circuitHash = keccak256(abi.encodePacked(vm.readFile(_circuitPath), isMock));
        
        if(_circuitHash != circuitHash) {
            string[] memory cli = new string[](14);
            cli[0] = "npx";
            cli[1] = "axiom";
            cli[2] = "circuit";
            cli[3] = "compile";
            cli[4] = _circuitPath;
            cli[5] = "--provider";
            cli[6] = vm.rpcUrl(urlOrAlias);
            cli[7] = "--inputs";
            cli[8] = inputPath;
            cli[9] = "--outputs";
            cli[10] = COMPILED_PATH;
            cli[11] = "--function";
            cli[12] = "circuit";
            if (isMock) cli[13] = "--mock";
            vm.ffi(cli); 
            // Write hash of compiled circuit to avoid re-compile
            string memory jsonHash = vm.serializeBytes32("circuitHash", "hash", _circuitHash);
            vm.writeJson(jsonHash, CIRCUIT_HASH_PATH);
        }

        string memory artifact = vm.readFile(COMPILED_PATH);
        compiledString = artifact;
        querySchema = bytes32(vm.parseJson(artifact, ".querySchema"));
    }

    /**
     * @dev Generates args for the sendQuery function
     * @param inputPath path to the input file
     * @param callbackTarget the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param feeData the fee data
     * @return args the sendQuery args
     */
    function sendQueryArgs(
        string memory inputPath,
        address callbackTarget,
        bytes memory callbackExtraData,
        IAxiomV2Query.AxiomV2FeeData memory feeData
    ) public returns (AxiomSendQueryArgs memory args) {
        _prove(inputPath);
        string memory _queryString = _queryParams(
            callbackTarget,
            callbackExtraData,
            feeData
        );
        args = _parseSendQueryArgs(_queryString);
    }

    /**
     * @dev Sets the mock flag
     * @param _isMock the mock flag
     */
    function setMock(bool _isMock) public {
        isMock = _isMock;
    }

    /**
     * @dev Generates arguments for the fulfillCallback function
     * @param inputPath path to the input file
     * @param callbackTarget the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param feeData the fee data
     * @param caller the address of the caller
     * @return args the fulfillCallback args
     */
    function fulfillCallbackArgs(
        string memory inputPath,
        address callbackTarget,
        bytes memory callbackExtraData,
        IAxiomV2Query.AxiomV2FeeData memory feeData,
        address caller
    ) public returns (AxiomFulfillCallbackArgs memory args) {
        uint64 sourceChainId = uint64(block.chainid);
        string memory _outputString = _prove(inputPath);
        string memory _queryString = _queryParams(
            callbackTarget,
            callbackExtraData,
            feeData
        );

        AxiomSendQueryArgs memory _sendQueryArgs = _parseSendQueryArgs(
            _queryString
        );
        args = AxiomFulfillCallbackArgs({
            sourceChainId: sourceChainId,
            caller: caller,
            querySchema: abi.decode(
                vm.parseJson(compiledString, ".querySchema"),
                (bytes32)
            ),
            queryId: vm.parseJsonUint(_queryString, ".queryId"),
            axiomResults: abi.decode(
                vm.parseJson(_outputString, ".computeResults"),
                (bytes32[])
            ),
            callbackExtraData: _sendQueryArgs.callback.extraData,
            gasLimit: feeData.callbackGasLimit,
            callbackTarget: callbackTarget
        });
    }

    /**
     * @dev Fulfills the callback for an onchain query
     * @param args the arguments for the callback
     */
    function prankCallback(AxiomFulfillCallbackArgs memory args) public {
        vm.prank(axiomV2QueryAddress);
        IAxiomV2Client(args.callbackTarget).axiomV2Callback{gas: args.gasLimit}(
            args.sourceChainId,
            args.caller,
            args.querySchema,
            args.queryId,
            args.axiomResults,
            args.callbackExtraData
        );
    }

    /**
     * @dev Generates the fulfill callback args and and fulfills the onchain query
     * @param inputPath path to the input file
     * @param callbackTarget the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param feeData the fee data
     * @param caller the address of the caller
     */
    function prankCallback(
        string memory inputPath,
        address callbackTarget,
        bytes memory callbackExtraData,
        IAxiomV2Query.AxiomV2FeeData memory feeData,
        address caller
    ) public {
        AxiomFulfillCallbackArgs memory args = fulfillCallbackArgs(
            inputPath,
            callbackTarget,
            callbackExtraData,
            feeData,
            caller
        );
        prankCallback(args);
    }

    /**
     * @dev Fulfills the callback for an offchain query
     * @param args the arguments for the callback
     */
    function prankOffchainCallback(
        AxiomFulfillCallbackArgs memory args
    ) public {
        vm.prank(axiomV2QueryAddress);
        IAxiomV2Client(args.callbackTarget).axiomV2OffchainCallback{
            gas: args.gasLimit
        }(
            args.sourceChainId,
            args.caller,
            args.querySchema,
            args.queryId,
            args.axiomResults,
            args.callbackExtraData
        );
    }

    /**
     * @dev Generates the fulfill callback args and fulfills the offchain query
     * @param inputPath path to the input file
     * @param callbackTarget the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param feeData the fee data
     * @param caller the address of the caller
     */
    function prankOffchainCallback(
        string memory inputPath,
        address callbackTarget,
        bytes memory callbackExtraData,
        IAxiomV2Query.AxiomV2FeeData memory feeData,
        address caller
    ) public {
        AxiomFulfillCallbackArgs memory args = fulfillCallbackArgs(
            inputPath,
            callbackTarget,
            callbackExtraData,
            feeData,
            caller
        );
        prankOffchainCallback(args);
    }

    /**
     * @dev Generates sendQueryArgs and sends a query to the AxiomV2Query contract.
     * @param inputPath path to the input file
     * @param callbackTarget the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param feeData the fee data
     * @param caller the address of the caller
     */
    function getArgsAndSendQuery(
        string memory inputPath,
        address callbackTarget,
        bytes memory callbackExtraData,
        IAxiomV2Query.AxiomV2FeeData memory feeData,
        address caller
    ) public {
        AxiomVm.AxiomSendQueryArgs memory args = sendQueryArgs(
            inputPath,
            callbackTarget,
            callbackExtraData,
            feeData
        );
        vm.prank(caller);
        IAxiomV2Query(axiomV2QueryAddress).sendQuery{value: args.value}(
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
        axiomCheck[2] = CLI_VERSION_CHECK_CMD;
        bytes memory axiomOutput = vm.ffi(axiomCheck);
        require(_parseBoolean(string(axiomOutput)), CLI_VERSION_ERROR);
    }

    function _prove(
        string memory inputPath
    ) internal returns (string memory output) {
        _validateAxiomSetup();
        require(
            compiled,
            "Circuit has not been compiled. Run `compile` first."
        );
        vm.writeFile(COMPILED_PATH, compiledString);
        string[] memory cli = new string[](18);
        cli[0] = "npx";
        cli[1] = "axiom";
        cli[2] = "circuit";
        cli[3] = "prove";
        cli[4] = circuitPath;
        if (isMock) cli[5] = "--mock";
        cli[6] = "--sourceChainId";
        cli[7] = vm.toString(block.chainid);
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
        address callbackTarget,
        bytes memory callbackExtraData,
        IAxiomV2Query.AxiomV2FeeData memory feeData
    ) internal returns (string memory output) {
        _validateAxiomSetup();
        vm.writeFile(OUTPUT_PATH, outputString);
        string[] memory cli = new string[](22);
        cli[0] = "npx";
        cli[1] = "axiom";
        cli[2] = "circuit";
        cli[3] = "query-params";
        cli[4] = vm.toString(callbackTarget);
        cli[5] = "--sourceChainId";
        cli[6] = vm.toString(block.chainid);
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
        cli[21] = "--args-map";
        vm.ffi(cli);
        output = vm.readFile(QUERY_PATH);
        queryString = output;
    }

    /**
     * @dev Parses AxiomSendQueryArgs from the CLI calldata bytes output
     * @param _queryString the string output from the CLI
     * @return args the AxiomSendQueryArgs
     */
    function _parseSendQueryArgs(
        string memory _queryString
    ) internal pure returns (AxiomSendQueryArgs memory args) {
        args.sourceChainId = uint64(
            vm.parseJsonUint(_queryString, ".args.sourceChainId")
        );
        args.dataQueryHash = vm.parseJsonBytes32(
            _queryString,
            ".args.dataQueryHash"
        );

        args.computeQuery.k = uint8(
            vm.parseJsonUint(_queryString, ".args.computeQuery.k")
        );
        args.computeQuery.resultLen = uint16(
            vm.parseJsonUint(_queryString, ".args.computeQuery.resultLen")
        );
        args.computeQuery.vkey = vm.parseJsonBytes32Array(
            _queryString,
            ".args.computeQuery.vkey"
        );
        args.computeQuery.computeProof = vm.parseJsonBytes(
            _queryString,
            ".args.computeQuery.computeProof"
        );

        args.callback.target = vm.parseJsonAddress(
            _queryString,
            ".args.callback.target"
        );
        args.callback.extraData = vm.parseJsonBytes(
            _queryString,
            ".args.callback.extraData"
        );

        args.feeData.maxFeePerGas = uint64(
            vm.parseJsonUint(_queryString, ".args.feeData.maxFeePerGas")
        );
        args.feeData.callbackGasLimit = uint32(
            vm.parseJsonUint(_queryString, ".args.feeData.callbackGasLimit")
        );
        args.feeData.overrideAxiomQueryFee = vm.parseJsonUint(
            _queryString,
            ".args.feeData.overrideAxiomQueryFee"
        );

        args.userSalt = vm.parseJsonBytes32(_queryString, ".args.userSalt");
        args.refundee = vm.parseJsonAddress(_queryString, ".args.refundee");
        args.dataQuery = vm.parseJsonBytes(_queryString, ".args.dataQuery");
        args.value = vm.parseJsonUint(_queryString, ".value");
    }
}
