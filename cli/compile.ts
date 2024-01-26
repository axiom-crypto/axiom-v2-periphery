import { AxiomBaseCircuit } from "@axiom-crypto/circuit/js";
import { getFunctionFromTs, getProvider, readInputs, saveJsonToFile } from "@axiom-crypto/circuit/cliHandler/utils";
import { decodeAbiParameters, encodeAbiParameters } from 'viem';
import { getSolidityType } from "./utils";

export const compile = async (
    circuitPath: string,
    inputs: string,
    providerUri: string,
) => {
    let circuitFunction = "circuit";
    const f = await getFunctionFromTs(circuitPath, circuitFunction);
    const provider = getProvider(providerUri);
    const circuit = new AxiomBaseCircuit({
        f: f.circuit,
        mock: true,
        provider,
        shouldTime: false,
        inputSchema: f.inputSchema,
    })

    let abi: { name: string; type: string; }[] = [];
    let inputSchemaJson = JSON.parse(f.inputSchema);
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
    // console.log(circuitInputs);



    try {
        const res = await circuit.mockCompile(circuitInputs);
        const circuitFn = `const ${f.importName} = AXIOM_CLIENT_IMPORT\n${f.circuit.toString()}`;
        const encoder = new TextEncoder();
        const circuitBuild = encoder.encode(circuitFn);
        const build = {
            ...res,
            circuit: Buffer.from(circuitBuild).toString('base64'),
        }

        // const finalBuild = encoder.encode(JSON.stringify(build));
        // console.log(Buffer.from(finalBuild).toString('base64'));
        console.log(JSON.stringify(build));
    }
    catch (e) {
        console.error(e);
    }
}