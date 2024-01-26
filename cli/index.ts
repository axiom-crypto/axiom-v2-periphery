import { Command } from "commander";
import { compile } from "./compile";
import { prove } from "./prove";


const program = new Command("axiom-std");

program.name("axiom-std").usage("axiom-std CLI");

program.command("readCircuit")
    .description("Read and compile a circuit")
    .argument("<circuitPath>", "path to the typescript circuit file")
    .argument("<inputs>", "inputs to the circuit")
    .argument("<providerUri>", "provider to use")
    .action(compile);

program.command("prove")
    .description("Prove a circuit")
    .argument("<compiledJson>", "compiled json string")
    .argument("<inputs>", "inputs to the circuit")
    .argument("<providerUri>", "provider to use")
    .argument("<sourceChainId>", "source chain id")
    .argument("<callbackTarget>", "callback target")
    .argument("<callbackExtraData>", "callback extra data")
    .argument("<refundAddress>", "refund address")
    .argument("<maxFeePerGas>", "max fee per gas")
    .argument("<callbackGasLimit>", "callback gas limit")
    .argument("<caller>", "caller")
    .action(prove);

program.parseAsync(process.argv);