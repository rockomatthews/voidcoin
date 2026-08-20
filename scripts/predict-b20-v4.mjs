import { b20PredictionFromEnvironment } from "./b20-deployment-addresses.mjs";

console.log(JSON.stringify(await b20PredictionFromEnvironment(), null, 2));
