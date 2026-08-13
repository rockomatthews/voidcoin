import { bigint, index, integer, jsonb, pgEnum, pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";

export const requestStatus = pgEnum("request_status", [
  "draft",
  "awaiting_burn",
  "pending_review",
  "changes_requested",
  "ready_for_safe",
  "approved",
  "expired",
]);

export const renameRequests = pgTable(
  "rename_requests",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    burnId: bigint("burn_id", { mode: "bigint" }).notNull(),
    wallet: text("wallet").notNull(),
    contactEmail: text("contact_email"),
    proposedName: text("proposed_name").notNull(),
    proposedSymbol: text("proposed_symbol").notNull(),
    imageBlobUrl: text("image_blob_url").notNull(),
    imageHash: text("image_hash").notNull(),
    imageWidth: integer("image_width").notNull(),
    imageHeight: integer("image_height").notNull(),
    salt: text("salt").notNull(),
    commitment: text("commitment").notNull(),
    transactionHash: text("transaction_hash"),
    status: requestStatus("status").notNull().default("awaiting_burn"),
    moderatorNote: text("moderator_note"),
    safeCalldata: text("safe_calldata"),
    metadataURI: text("metadata_uri"),
    expiresAt: timestamp("expires_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [index("rename_requests_wallet_idx").on(table.wallet), index("rename_requests_status_idx").on(table.status)],
);

export const webhookReceipts = pgTable("webhook_receipts", {
  id: text("id").primaryKey(),
  provider: text("provider").notNull(),
  payload: jsonb("payload").notNull(),
  receivedAt: timestamp("received_at", { withTimezone: true }).notNull().defaultNow(),
});

export const proposalSubmissions = pgTable("proposal_submissions", {
  id: uuid("id").primaryKey().defaultRandom(),
  requestId: uuid("request_id").notNull().references(() => renameRequests.id, { onDelete: "cascade" }),
  proposedName: text("proposed_name").notNull(),
  proposedSymbol: text("proposed_symbol").notNull(),
  imageBlobUrl: text("image_blob_url").notNull(),
  imageHash: text("image_hash").notNull(),
  commitment: text("commitment").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [index("proposal_submissions_request_idx").on(table.requestId)]);

export type RenameRequest = typeof renameRequests.$inferSelect;
