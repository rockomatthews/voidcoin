import assert from "node:assert/strict";
import { validHoodSocials } from "../tools/hood-launch/validate-socials.mjs";

const cases = [
  [true, '{"website":"https://voidcoin.fun"}'],
  [true, "{}"],
  [true, '{"a":"https://x","a":"https://y"}'],
  [false, '{ "website" : "https://voidcoin.fun" }'],
  [false, '{"website": "https://voidcoin.fun"}'],
  [false, '{\n  "website": "https://voidcoin.fun"\n}'],
  [false, '{"website":"https://\\u0076oidcoin.fun"}'],
  [false, '{"website":"https:\\/\\/voidcoin.fun"}'],
  [false, '{"website":"https://voidcoin.fun\\u0000evil"}'],
  [false, '{"website":"https://voidcoin.fun\\nevil"}'],
  [false, '{"website":"https://vöidcoin.fun"}'],
  [false, '{"website":"https://void coin.fun"}'],
  [false, `{"website":"https://${"a".repeat(3_000)}"}`],
  [false, '{"website":"http://voidcoin.fun"}'],
  [false, '{"a":"javascript:alert(1)"}'],
  [false, '{"a":{"b":"https://x"}}'],
  [false, '{"a":"https://"}'],
];

for (const [expected, value] of cases) assert.equal(validHoodSocials(value), expected, value);
console.log(JSON.stringify({ ok: true, cases: cases.length, divergences: 0 }));
