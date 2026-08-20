ALTER TABLE "rename_requests"
ADD COLUMN "submission_mode" text DEFAULT 'burn' NOT NULL;

ALTER TABLE "rename_requests"
ALTER COLUMN "commitment" DROP NOT NULL;

ALTER TABLE "proposal_submissions"
ALTER COLUMN "commitment" DROP NOT NULL;
