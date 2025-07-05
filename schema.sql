-- SQLite Child Database Schema for Memory System

-- Enable foreign key constraints
PRAGMA foreign_keys = ON;

-- Entities table (for structured references in facts)
CREATE TABLE entities (
    entity_id BLOB PRIMARY KEY -- UUID
) WITHOUT ROWID;

-- Relations table (defines types of relations that can exist in facts)
CREATE TABLE relations (
    name TEXT NOT NULL,
    argument1_type TEXT NOT NULL, -- FIXME: Align values with Swift Generable types
    argument2_type TEXT, -- NULL for unary relations
    arity INTEGER NOT NULL GENERATED ALWAYS AS (CASE WHEN argument2_type IS NULL THEN 1 ELSE 2 END) VIRTUAL,
    description TEXT
);
CREATE UNIQUE INDEX idx_relations_name_arity ON relations(name, arity);

-- Facts table (stores relational knowledge)
CREATE TABLE facts (
    fact_id BLOB PRIMARY KEY, -- UUIDv7
    relation_name TEXT NOT NULL,
    argument1_value NOT NULL,
    argument2_value, -- NULL for unary relations
	relation_arity INTEGER NOT NULL GENERATED ALWAYS AS (CASE WHEN argument2_value IS NULL THEN 1 ELSE 2 END) VIRTUAL,
	FOREIGN KEY (relation_name, relation_arity) REFERENCES relations(name, arity)
) WITHOUT ROWID;
CREATE INDEX idx_facts_relation_arg1_arg2 ON facts(relation_name, argument1_value, argument2_value);
CREATE INDEX idx_facts_relation_arg2_arg1 ON facts(relation_name, argument2_value, argument1_value);

-- Trigger to update conversation modified_at when messages are added
CREATE TRIGGER update_conversation_modified 
AFTER INSERT ON messages
BEGIN
    UPDATE conversations 
    SET modified_at = CURRENT_TIMESTAMP 
    WHERE conversation_id = NEW.conversation_id;
END;
