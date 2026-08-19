export async function GET() {
  return Response.json(
    { error: "The V1 bonding curve is retired. Trade the active token through Zora." },
    { status: 410, headers: { "Cache-Control": "no-store" } },
  );
}
