import { Body, Button, Container, Head, Heading, Html, Preview, Section, Text } from "@react-email/components";

export function ModeratorAlertEmail({ name, symbol, burner, burnId, reviewUrl }: { name: string; symbol: string; burner: string; burnId: string; reviewUrl: string }) {
  return (
    <Html>
      <Head />
      <Preview>A new VOIDCOIN burner is waiting for review.</Preview>
      <Body style={{ background: "#050609", color: "#eefcff", fontFamily: "Arial, sans-serif", padding: "32px" }}>
        <Container style={{ border: "1px solid #1fd6ff", borderRadius: "18px", padding: "28px", maxWidth: "560px" }}>
          <Text style={{ color: "#1fd6ff", letterSpacing: "0.18em", fontSize: "12px" }}>IDENTITY EVENT / {burnId}</Text>
          <Heading style={{ margin: "8px 0" }}>{name}</Heading>
          <Text style={{ fontSize: "18px", color: "#b89cff" }}>${symbol}</Text>
          <Section style={{ background: "#0d1018", borderRadius: "12px", padding: "16px", margin: "20px 0" }}>
            <Text style={{ margin: 0 }}>Burner: {burner}</Text>
          </Section>
          <Button href={reviewUrl} style={{ background: "#1fd6ff", color: "#050609", borderRadius: "999px", padding: "12px 20px", fontWeight: 700 }}>
            Review private request
          </Button>
        </Container>
      </Body>
    </Html>
  );
}
