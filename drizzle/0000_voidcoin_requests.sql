CREATE TYPE "request_status" AS ENUM ('draft', 'awaiting_burn', 'pending_review', 'changes_requested', 'ready_for_safe', 'approved', 'superseded');

CREATE TABLE "rename_requests" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"burn_id" bigint NOT NULL,
	"burn_amount" bigint NOT NULL,
  "wallet" text NOT NULL,
  "contact_email" text,
  "proposed_name" text NOT NULL,
  "proposed_symbol" text NOT NULL,
  "image_blob_url" text NOT NULL,
  "image_hash" text NOT NULL,
  "image_width" integer NOT NULL,
  "image_height" integer NOT NULL,
  "salt" text NOT NULL,
  "commitment" text NOT NULL,
  "transaction_hash" text,
  "status" "request_status" DEFAULT 'awaiting_burn' NOT NULL,
  "moderator_note" text,
  "safe_calldata" text,
  "metadata_uri" text,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE "webhook_receipts" (
  "id" text PRIMARY KEY NOT NULL,
  "provider" text NOT NULL,
  "payload" jsonb NOT NULL,
  "received_at" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE "proposal_submissions" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "request_id" uuid NOT NULL REFERENCES "rename_requests"("id") ON DELETE CASCADE,
  "proposed_name" text NOT NULL,
  "proposed_symbol" text NOT NULL,
  "image_blob_url" text NOT NULL,
  "image_hash" text NOT NULL,
  "commitment" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);

CREATE INDEX "rename_requests_wallet_idx" ON "rename_requests" USING btree ("wallet");
CREATE INDEX "rename_requests_status_idx" ON "rename_requests" USING btree ("status");
CREATE INDEX "proposal_submissions_request_idx" ON "proposal_submissions" USING btree ("request_id");
