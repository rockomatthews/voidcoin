import { predictionFromEnvironment } from "./deployment-addresses.mjs";

console.log(JSON.stringify(await predictionFromEnvironment(), null, 2));
