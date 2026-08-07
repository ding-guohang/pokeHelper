ALTER TABLE auth_identities
    ADD COLUMN display_email VARCHAR(320) NULL AFTER canonical_email;

UPDATE auth_identities
SET canonical_email = subject,
    display_email = subject
WHERE provider = 'email';

ALTER TABLE email_challenges
    ADD COLUMN attempt_count INT UNSIGNED NOT NULL DEFAULT 0 AFTER purpose;

ALTER TABLE auth_identities
    ADD CONSTRAINT chk_auth_identities_email_fields
        CHECK (
            provider <> 'email'
            OR (canonical_email IS NOT NULL AND display_email IS NOT NULL)
        ) ENFORCED;
