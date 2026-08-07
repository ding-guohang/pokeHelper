ALTER TABLE training_events
    DROP FOREIGN KEY fk_training_events_device;

ALTER TABLE training_events
    ADD CONSTRAINT fk_training_events_device
        FOREIGN KEY (user_id, device_id)
        REFERENCES devices (user_id, id)
        ON DELETE CASCADE;

ALTER TABLE sessions
    ADD UNIQUE KEY uq_sessions_user_session_id (user_id, id);

ALTER TABLE refresh_tokens
    DROP FOREIGN KEY fk_refresh_tokens_session;

ALTER TABLE refresh_tokens
    ADD KEY idx_refresh_tokens_user_session (user_id, session_id);

ALTER TABLE refresh_tokens
    ADD CONSTRAINT fk_refresh_tokens_session
        FOREIGN KEY (user_id, session_id)
        REFERENCES sessions (user_id, id)
        ON DELETE CASCADE;

ALTER TABLE user_sync_sequences
    ALTER COLUMN next_sequence SET DEFAULT 0;
