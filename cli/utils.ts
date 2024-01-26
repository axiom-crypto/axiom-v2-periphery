export const getSolidityType = (type: string) => {
    switch (type) {
        case "CircuitValue":
            return "uint256";
        case "CircuitValue256":
            return "uint256";
        case "CircuitValue[]":
            return "uint256[]";
        case "CircuitValue256[]":
            return "uint256[]";
        default:
            throw new Error(`Unknown type ${type}`);
    }
}