ALTER TABLE auth_identities
    MODIFY COLUMN subject VARCHAR(255)
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_bin
    NOT NULL;
