import { neon } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-http";
import * as schema from "./schema";

let database: ReturnType<typeof createDatabase> | null = null;

function createDatabase() {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is not configured");
  return drizzle(neon(url), { schema });
}

export function getDb() {
  if (!database) database = createDatabase();
  return database;
}

export function hasDatabase() {
  return Boolean(process.env.DATABASE_URL);
}
