function byte(char) {
  return char.charCodeAt(0);
}

// Byte-for-byte mirror of VOIDHoodSkinController._validSocials. Keep this
// intentionally stricter than a general JSON parser: the controller accepts
// only compact ASCII JSON objects containing HTTPS string links.
export function validHoodSocials(value) {
  if (typeof value !== "string") return false;
  const input = Buffer.from(value, "utf8");
  const length = input.length;
  if (length < 2 || length > 1_024 || input[0] !== byte("{") || input[length - 1] !== byte("}")) return false;
  if (length === 2) return true;

  let index = 1;
  while (index < length - 1) {
    if (input[index++] !== byte('"')) return false;
    const keyStart = index;
    while (index < length - 1 && input[index] !== byte('"')) {
      const char = input[index++];
      const validKey = (char >= byte("0") && char <= byte("9"))
        || (char >= byte("A") && char <= byte("Z"))
        || (char >= byte("a") && char <= byte("z"))
        || char === byte("_")
        || char === byte("-");
      if (!validKey) return false;
    }
    if (
      index === keyStart
      || index >= length - 1
      || input[index++] !== byte('"')
      || input[index++] !== byte(":")
      || input[index++] !== byte('"')
    ) return false;

    const prefix = "https://";
    if (index + prefix.length > length - 1) return false;
    for (let offset = 0; offset < prefix.length; offset += 1) {
      if (input[index + offset] !== byte(prefix[offset])) return false;
    }
    index += prefix.length;

    const linkStart = index;
    while (index < length - 1 && input[index] !== byte('"')) {
      const char = input[index++];
      if (char < 0x21 || char > 0x7e || char === byte("\\")) return false;
    }
    if (index === linkStart || index >= length - 1 || input[index++] !== byte('"')) return false;
    if (index === length - 1) return true;
    if (input[index++] !== byte(",")) return false;
  }
  return false;
}

export function assertHoodSocials(value) {
  if (!validHoodSocials(value)) {
    throw new Error("VOID_HOOD_SOCIALS must exactly match the controller's compact ASCII HTTPS-links grammar");
  }
}
