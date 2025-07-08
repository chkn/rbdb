-- SQLite Database Schema for RBDB

-- Maps shorter int entity IDs that are internal to this DB to UUIDs
--  that are used externally.
CREATE TABLE IF NOT EXISTS _entity (
    internal_id INTEGER PRIMARY KEY,
    external_id BLOB -- UUIDv7
);

CREATE TABLE IF NOT EXISTS rule (
    entity_id BLOB PRIMARY KEY, -- UUIDv7
    formula BLOB, -- JSONB
    output_type TEXT GENERATED ALWAYS AS (formula->>0) VIRTUAL COLLATE NOCASE
) WITHOUT ROWID;

-- We must ensure that the LIKE optimization can be applied for output_type
-- https://www.sqlite.org/optoverview.html#the_like_optimization
CREATE INDEX IF NOT EXISTS idx_rule_output_type_arg_1_arg_2 ON rule(output_type COLLATE NOCASE, formula->>1, formula->>2);