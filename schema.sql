-- SQLite Database Schema for RBDB

 PRAGMA foreign_keys = ON;

-- Maps shorter int entity IDs that are internal to this DB to UUIDs
--  that are used externally.
CREATE TABLE IF NOT EXISTS entity (
    internal_id INTEGER PRIMARY KEY,
    entity_id BLOB DEFAULT (uuidv7())
);

-- Internal table
CREATE TABLE IF NOT EXISTS _rule (
    internal_entity_id INTEGER PRIMARY KEY REFERENCES entity,
    formula BLOB, -- JSONB
    output_type TEXT GENERATED ALWAYS AS (formula->>0) VIRTUAL COLLATE NOCASE
) WITHOUT ROWID;

-- We must ensure that the LIKE optimization can be applied for output_type
-- https://www.sqlite.org/optoverview.html#the_like_optimization
CREATE INDEX IF NOT EXISTS idx_rule_output_type_arg_1_arg_2 ON _rule(output_type COLLATE NOCASE, formula->>1, formula->>2);