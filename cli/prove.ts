import path from 'path';
import { AxiomBaseCircuit } from "@axiom-crypto/circuit/js";
import { getFunctionFromTs, getProvider, readInputs, saveJsonToFile } from "@axiom-crypto/circuit/cliHandler/utils";
import { getSolidityType } from './utils';
import { decodeAbiParameters } from 'viem';
import { AxiomSdkCore } from "@axiom-crypto/core";
import { buildSendQuery } from "@axiom-crypto/client";
import { argsArrToObj } from '@axiom-crypto/client/axiom/utils';



export const prove = async (
    compiledJson: string,
    inputs: string,
    providerUri: string,
    sourceChainId: string,
    callbackTarget: string,
    callbackExtraData: string,
    refundAddress: string,
    maxFeePerGas: string,
    callbackGasLimit: string,
    caller: string,
) => {

    const decoder = new TextDecoder();

    const provider = getProvider(providerUri);
    // const decodedCompile = Buffer.from(compiledJson, 'base64');
    // const decodedStr = decoder.decode(decodedCompile);
    // console.log(decodedStr);
    let compiled = JSON.parse(compiledJson);
    // let compiled = JSON.parse(str);

    const decodedArray = Buffer.from(compiled.circuit, 'base64');
    const raw = decoder.decode(decodedArray);
    const AXIOM_CLIENT_IMPORT = require("@axiom-crypto/client");


    const circuit = new AxiomBaseCircuit({
        f: eval(raw),
        mock: true,
        // chainId: options.sourceChainId,
        provider,
        shouldTime: false,
        inputSchema: compiled.inputSchema,
    })

    let abi: { name: string; type: string; }[] = [];
    let decodedInputSchema = Buffer.from(compiled.inputSchema, 'base64');
    let inputSchemaJson = JSON.parse(decoder.decode(decodedInputSchema));
    let keys = Object.keys(inputSchemaJson);
    for (let i = 0; i < keys.length; i++) {
        abi.push({ "name": keys[i], "type": getSolidityType(inputSchemaJson[keys[i]]) });
    }
    // console.log(abi);
    // console.log(encodeAbiParameters(abi, [4205938, "0x8018fe32fCFd3d166E8b4c4E37105318A84BA11b"]))
    const rawInputs = decodeAbiParameters(abi, inputs as `0x${string}`);
    const circuitInputs: any = {};
    for (let i = 0; i < keys.length; i++) {
        circuitInputs[keys[i]] = rawInputs[i].toString();
    }

    const axiom = new AxiomSdkCore({
        providerUri: provider,
        chainId: sourceChainId,
        version: "v2",
    });

    try {
        let computeQuery;
        // if (options.mock === true) {
        circuit.loadSavedMock(compiled);
        computeQuery = await circuit.mockProve(circuitInputs);
        // } else {
        //     circuit.loadSaved(compiled);
        //     computeQuery = await circuit.run(circuitInputs);
        // }
        const computeResults = circuit.getComputeResults();
        const dataQuery = circuit.getDataQuery();
        const res = {
            sourceChainId: circuit.getChainId(),
            computeQuery,
            computeResults,
            dataQuery,
        }

        let build = await buildSendQuery({
            axiom,
            dataQuery: res.dataQuery,
            computeQuery: res.computeQuery,
            callback: {
                target: callbackTarget,
                extraData: callbackExtraData,
            },
            options: {
                refundee: refundAddress,
                maxFeePerGas: maxFeePerGas,
                callbackGasLimit: Number(callbackGasLimit),
            },
            caller: caller,
        });
        build.value = build.value.toString() as any;
        const query = {
            value: build.value,
            mock: build.mock,
            queryId: build.queryId,
            args: argsArrToObj(build.args),
            calldata: build.calldata,
            computeResults,
        };

        console.log(JSON.stringify(query));
    }
    catch (e) {
        console.error(e);
    }
}