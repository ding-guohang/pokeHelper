CREATE TABLE IF NOT EXISTS auth_throttle_attempts (
    identity_signal_hash BINARY(32) NOT NULL,
    network_signal_hash BINARY(32) NOT NULL,
    attempted_at DATETIME(3) NOT NULL,
    attempt_count INT UNSIGNED NOT NULL,
    PRIMARY KEY (identity_signal_hash, network_signal_hash, attempted_at),
    CONSTRAINT fk_auth_throttle_attempts_bucket
        FOREIGN KEY (identity_signal_hash, network_signal_hash)
        REFERENCES auth_throttles (identity_signal_hash, network_signal_hash)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARACTER SET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO auth_throttle_attempts (
    identity_signal_hash,
    network_signal_hash,
    attempted_at,
    attempt_count
)
SELECT
    identity_signal_hash,
    network_signal_hash,
    window_started_at,
    failure_count
FROM auth_throttles
WHERE failure_count > 0
ON DUPLICATE KEY UPDATE
    attempt_count = GREATEST(auth_throttle_attempts.attempt_count, VALUES(attempt_count));
