-- SQLite Root Database Schema for Memory System

-- The root database also contains everything in the child schema,
--  but the child schema does not contain any of the root schema.



INSERT INTO relations (name, arity, description) VALUES
-- is-a
('conversation', 1, 'X is a conversation'),
('fact', 1, 'X is a fact'),
('message', 1, 'X is a message'),
('rule', 1, 'X is a rule');

-- attributes
('content', 2, 'X is the content of Y'),
('conversation', 2, 'X is the conversation of Y'),
('title', 2, 'X is the title of Y'),
('speaker', 2, 'X is the speaker of Y'),

-- events
('create', 1, 'The event X is an instance of creating'),
('modify', 1, 'The event X is an instance of modifying');
