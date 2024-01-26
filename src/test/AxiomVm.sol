// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IAxiomV2Query} from "../interfaces/query/IAxiomV2Query.sol";
import {IAxiomV2Client} from "../interfaces/client/IAxiomV2Client.sol";
import {AxiomV2Addresses} from "../client/AxiomV2Addresses.sol";

struct QueryArgs {
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

struct FulfillCallbackArgs {
    uint64 sourceChainId;
    address caller;
    bytes32 querySchema;
    uint256 queryId;
    bytes32[] axiomResults;
    bytes callbackExtraData;
    uint256 gasLimit;
    address callbackTarget;
}

struct Query {
    bytes32 querySchema;
    bytes input;
    address callbackTarget;
    string outputString;
    AxiomVm axiomVm;
}

library Axiom {
    function send(Query memory self) internal returns (bytes32[] memory) {
        self.outputString = self.axiomVm.getArgsAndSendQuery(
            self.querySchema,
            self.input,
            self.callbackTarget
        );
        return fulfill(self);
    }

    function fulfill(Query memory self) internal returns (bytes32[] memory) {
        return
            fulfill(
                self,
                bytes(""),
                IAxiomV2Query.AxiomV2FeeData({
                    maxFeePerGas: 25 gwei,
                    callbackGasLimit: 1_000_000,
                    overrideAxiomQueryFee: 0
                }),
                msg.sender
            );
    }

    function fulfill(
        Query memory self,
        bytes memory callbackExtraData,
        IAxiomV2Query.AxiomV2FeeData memory feeData,
        address caller
    ) internal returns (bytes32[] memory) {
        FulfillCallbackArgs memory args = self.axiomVm.fulfillCallbackArgs(
            self.querySchema,
            self.input,
            self.callbackTarget,
            callbackExtraData,
            feeData,
            caller
        );
        self.axiomVm.prankCallback(args);
        return args.axiomResults;
    }
}

contract AxiomVm is Test {
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

    address public axiomV2QueryAddress;
    mapping(bytes32 => string) compiledStrings;

    constructor(address _axiomV2QueryAddress, string memory _urlOrAlias) {
        axiomV2QueryAddress = _axiomV2QueryAddress;
        urlOrAlias = _urlOrAlias;
    }

    /**
     * @dev Compiles a circuit using the Axiom CLI via FFI
     * @param _circuitPath path to the circuit file
     * @param input path to the input file
     * @return querySchema
     */
    function readCircuit(
        string memory _circuitPath,
        bytes memory input
    ) public returns (bytes32 querySchema) {
        _validateAxiomSetup();
        string[] memory cli = new string[](6);
        cli[0] = "node";
        cli[1] = "dist/index.js";
        cli[2] = "readCircuit";
        cli[3] = _circuitPath;
        cli[4] = vm.toString(input);
        cli[5] = vm.rpcUrl(urlOrAlias);
        bytes memory axiomOutput = vm.ffi(cli);

        string memory artifact = string(axiomOutput);
        querySchema = bytes32(vm.parseJson(artifact, ".querySchema"));
        compiledStrings[querySchema] = artifact;
    }

    /**
     * @dev Generates args for the sendQuery function
     * @param input path to the input file
     * @param callbackTarget the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param feeData the fee data
     * @return args the sendQuery args
     */
    function sendQueryArgs(
        bytes32 querySchema,
        bytes memory input,
        address callbackTarget,
        bytes memory callbackExtraData,
        IAxiomV2Query.AxiomV2FeeData memory feeData
    ) public returns (QueryArgs memory args, string memory queryString) {
        queryString = _run(
            querySchema,
            input,
            callbackTarget,
            callbackExtraData,
            feeData
        );
        args = parseQueryArgs(queryString);
    }

    function sendQueryArgs(
        bytes32 querySchema,
        bytes memory input,
        address callbackTarget
    ) public returns (QueryArgs memory args, string memory queryString) {
        IAxiomV2Query.AxiomV2FeeData memory feeData = IAxiomV2Query
            .AxiomV2FeeData({
                maxFeePerGas: 25 gwei,
                callbackGasLimit: 1_000_000,
                overrideAxiomQueryFee: 0
            });
        bytes memory callbackExtraData = bytes("");
        return
            sendQueryArgs(
                querySchema,
                input,
                callbackTarget,
                callbackExtraData,
                feeData
            );
    }

    /**
     * @dev Generates arguments for the fulfillCallback function
     * @param callbackTarget the callback contract address
     * @param feeData the fee data
     * @param caller the address of the caller
     * @return args the fulfillCallback args
     */
    function fulfillCallbackArgs(
        bytes32 querySchema,
        string memory _queryString,
        address callbackTarget,
        IAxiomV2Query.AxiomV2FeeData memory feeData,
        address caller
    ) public view returns (FulfillCallbackArgs memory args) {
        uint64 sourceChainId = uint64(block.chainid);

        QueryArgs memory _query = parseQueryArgs(_queryString);
        args = FulfillCallbackArgs({
            sourceChainId: sourceChainId,
            caller: caller,
            querySchema: abi.decode(
                vm.parseJson(compiledStrings[querySchema], ".querySchema"),
                (bytes32)
            ),
            queryId: vm.parseJsonUint(_queryString, ".queryId"),
            axiomResults: abi.decode(
                vm.parseJson(_queryString, ".computeResults"),
                (bytes32[])
            ),
            callbackExtraData: _query.callback.extraData,
            gasLimit: feeData.callbackGasLimit,
            callbackTarget: callbackTarget
        });
    }

    /**
     * @dev Generates arguments for the fulfillCallback function
     * @param input path to the input file
     * @param callbackTarget the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param feeData the fee data
     * @param caller the address of the caller
     * @return args the fulfillCallback args
     */
    function fulfillCallbackArgs(
        bytes32 querySchema,
        bytes memory input,
        address callbackTarget,
        bytes memory callbackExtraData,
        IAxiomV2Query.AxiomV2FeeData memory feeData,
        address caller
    ) public returns (FulfillCallbackArgs memory args) {
        string memory queryString = _run(
            querySchema,
            input,
            callbackTarget,
            callbackExtraData,
            feeData
        );
        return
            fulfillCallbackArgs(
                querySchema,
                queryString,
                callbackTarget,
                feeData,
                caller
            );
    }

    /**
     * @dev Fulfills the callback for an onchain query
     * @param args the arguments for the callback
     */
    function prankCallback(FulfillCallbackArgs memory args) public {
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
     * @param input path to the input file
     * @param callbackTarget the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param feeData the fee data
     * @param caller the address of the caller
     */
    function prankCallback(
        bytes32 querySchema,
        bytes memory input,
        address callbackTarget,
        bytes memory callbackExtraData,
        IAxiomV2Query.AxiomV2FeeData memory feeData,
        address caller
    ) public {
        FulfillCallbackArgs memory args = fulfillCallbackArgs(
            querySchema,
            input,
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
    function prankOffchainCallback(FulfillCallbackArgs memory args) public {
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
     * @param input path to the input file
     * @param callbackTarget the callback contract address
     * @param callbackExtraData extra data to be passed to the callback contract
     * @param feeData the fee data
     * @param caller the address of the caller
     */
    function prankOffchainCallback(
        bytes32 querySchema,
        bytes memory input,
        address callbackTarget,
        bytes memory callbackExtraData,
        IAxiomV2Query.AxiomV2FeeData memory feeData,
        address caller
    ) public {
        FulfillCallbackArgs memory args = fulfillCallbackArgs(
            querySchema,
            input,
            callbackTarget,
            callbackExtraData,
            feeData,
            caller
        );
        prankOffchainCallback(args);
    }

    /**
     * @dev Generates Query and sends a query to the AxiomV2Query contract.
     * @param input path to the input file
     * @param callbackTarget the callback contract address
     */
    function getArgsAndSendQuery(
        bytes32 querySchema,
        bytes memory input,
        address callbackTarget
    ) public returns (string memory queryString) {
        (QueryArgs memory args, string memory _queryString) = sendQueryArgs(
            querySchema,
            input,
            callbackTarget
        );
        queryString = _queryString;
        vm.prank(msg.sender);
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

    function _run(
        bytes32 querySchema,
        bytes memory input,
        address callbackTarget,
        bytes memory callbackExtraData,
        IAxiomV2Query.AxiomV2FeeData memory feeData
    ) internal returns (string memory output) {
        _validateAxiomSetup();
        require(
            bytes(compiledStrings[querySchema]).length > 0,
            "Circuit has not been compiled. Run `compile` first."
        );
        string[] memory cli = new string[](13);
        cli[0] = "node";
        cli[1] = "dist/index.js";
        cli[2] = "prove";
        cli[3] = compiledStrings[querySchema];
        cli[4] = vm.toString(input);
        cli[5] = vm.rpcUrl(urlOrAlias);
        cli[6] = vm.toString(block.chainid);
        cli[7] = vm.toString(callbackTarget);
        cli[8] = vm.toString(callbackExtraData);
        cli[9] = vm.toString(msg.sender);
        cli[10] = vm.toString(feeData.maxFeePerGas);
        cli[11] = vm.toString(feeData.callbackGasLimit);
        cli[12] = vm.toString(msg.sender);

        bytes memory axiomOutput = vm.ffi(cli);
        output = string(axiomOutput);
    }

    /**
     * @dev Parses AxiomQuery from the CLI calldata bytes output
     * @param _queryString the string output from the CLI
     * @return args the AxiomQuery
     */
    function parseQueryArgs(
        string memory _queryString
    ) public pure returns (QueryArgs memory args) {
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
