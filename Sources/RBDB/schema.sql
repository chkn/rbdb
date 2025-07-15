-- SQLite Database Schema for RBDB

 PRAGMA foreign_keys = ON;

-- Maps shorter int entity IDs that are internal to this DB to UUIDs
--  that are used externally. This is a "public" table in the sense that
--  it conveys `entity_id` is some thing (an entity). The indirection
--  might also be handy in the future when we discover that different
--  entities are actually the same thing and we want to merge them.
CREATE TABLE IF NOT EXISTS entity (
    internal_entity_id INTEGER PRIMARY KEY,
    entity_id BLOB UNIQUE NOT NULL DEFAULT (uuidv7())
) STRICT;

CREATE TABLE IF NOT EXISTS predicate (
    internal_entity_id INTEGER PRIMARY KEY REFERENCES entity,
    name TEXT UNIQUE NOT NULL,
    column_names BLOB -- JSONB
) STRICT;

-- Internal table
CREATE TABLE IF NOT EXISTS _rule (
    internal_entity_id INTEGER PRIMARY KEY REFERENCES entity,
    formula BLOB UNIQUE NOT NULL, -- JSONB
    output_type TEXT GENERATED ALWAYS AS (formula->>0) VIRTUAL COLLATE NOCASE
) STRICT;
-- FIXME: Expose a "rule" view that has entity uuid and formula as a string?

-- We must ensure that the LIKE optimization can be applied for output_type
-- https://www.sqlite.org/optoverview.html#the_like_optimization
CREATE INDEX IF NOT EXISTS idx_rule_output_type_arg_1_arg_2 ON _rule(output_type COLLATE NOCASE, formula->>1, formula->>2);
