-- SQLite Database Schema for RBDB

CREATE TABLE IF NOT EXISTS rule (
    entity_id BLOB PRIMARY KEY, -- UUIDv7
    formula BLOB, -- JSONB
    output_type TEXT GENERATED ALWAYS AS (formula->>0) VIRTUAL COLLATE NOCASE
) WITHOUT ROWID;

-- We must ensure that the LIKE optimization can be applied to this
-- https://www.sqlite.org/optoverview.html#the_like_optimization
CREATE INDEX IF NOT EXISTS idx_rule_output_type ON rule(output_type COLLATE NOCASE);