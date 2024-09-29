-- Clean up previous instance

DROP TRIGGER IF EXISTS on_tree_node_delete ON tree_node;
DROP TRIGGER IF EXISTS on_tree_node_content_delete ON tree_node_content;
DROP TRIGGER IF EXISTS on_user_account_insert ON user_account;
DROP TRIGGER IF EXISTS tree_node_content_tsvector_update ON tree_node_content;

DROP FUNCTION IF EXISTS delete_tree_node;
DROP FUNCTION IF EXISTS delete_tree_node_content;
DROP FUNCTION IF EXISTS delete_user_content;
DROP FUNCTION IF EXISTS set_first_user_to_admin;
DROP FUNCTION IF EXISTS init_db_content;

DROP INDEX IF EXISTS tag_vote_idx;
DROP INDEX IF EXISTS tag_vote_user_idx;
DROP INDEX IF EXISTS tree_node_content_vote_idx;
DROP INDEX IF EXISTS tree_node_content_vote_user_idx;
DROP INDEX IF EXISTS tree_node_content_idx;
DROP INDEX IF EXISTS tree_node_vote_idx;
DROP INDEX IF EXISTS tree_node_vote_user_idx;
DROP INDEX IF EXISTS tree_node_parent_idx;
DROP INDEX IF EXISTS tree_node_lang_code_node_idx;
DROP INDEX IF EXISTS tree_node_lang_code_idx;
DROP INDEX IF EXISTS tree_node_internal_key_node_idx;
DROP INDEX IF EXISTS tree_node_internal_key_idx;
DROP INDEX IF EXISTS tree_node_merge_vote_idx;
DROP INDEX IF EXISTS tree_node_merge_vote_user_idx;
DROP INDEX IF EXISTS tree_node_move_vote_idx;
DROP INDEX IF EXISTS tree_node_move_vote_user_idx;
DROP INDEX IF EXISTS tree_node_content_search_idx;
DROP INDEX IF EXISTS tree_node_content_search_composite_idx;

DROP TABLE IF EXISTS tag_vote;
DROP TABLE IF EXISTS tree_node_content_vote;
DROP TABLE IF EXISTS tree_node_content;
DROP TABLE IF EXISTS tree_node_vote;
DROP TABLE IF EXISTS tree_node_lang_code;
DROP TABLE IF EXISTS tree_node_internal_key;
DROP TABLE IF EXISTS tree_node_merge_vote;
DROP TABLE IF EXISTS tree_node_move_vote;
DROP TABLE IF EXISTS tree_node;

DROP TABLE IF EXISTS user_signup_request;
DROP TABLE IF EXISTS password_reset_request;
DROP TABLE IF EXISTS user_session;
DROP TABLE IF EXISTS user_account;

DROP TYPE IF EXISTS user_role_type;
DROP TYPE IF EXISTS tree_node_class;
DROP TYPE IF EXISTS vote_type;
DROP TYPE IF EXISTS tree_node_content_type;
DROP TYPE IF EXISTS tag_target_type;
DROP TYPE IF EXISTS tree_node_body_type;

DROP COLLATION IF EXISTS case_insensitive;

--------------------------------------------------
-- Create user management and session tables

CREATE TYPE user_role_type AS ENUM (
	'admin', -- can do anything
	'moderator', -- can delete and edit stuff
	'contributor', -- can create categories, posts, comments, and votes
	'banned' -- can't do anything
);

CREATE TABLE user_account (
	id SERIAL PRIMARY KEY,
	email VARCHAR(50) UNIQUE NOT NULL,
	user_role user_role_type NOT NULL DEFAULT 'contributor',
	handle VARCHAR(25) UNIQUE, -- optional handle
	display_name VARCHAR(50) NOT NULL, -- required
	auth_hash VARCHAR(60) NOT NULL,
	user_settings JSON,
	created_at TIMESTAMPTZ NOT NULL
);

CREATE UNIQUE INDEX user_account_handle_idx ON user_account (handle);
CREATE UNIQUE INDEX user_account_email_idx ON user_account (email);

CREATE TABLE user_session (
	token VARCHAR(30) PRIMARY KEY,
	user_id INTEGER NOT NULL REFERENCES user_account (id) ON DELETE CASCADE,
	expires TIMESTAMPTZ NOT NULL
);

CREATE TABLE user_signup_request (
	id SERIAL PRIMARY KEY,
	email VARCHAR(50) UNIQUE NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	token VARCHAR(15) UNIQUE,
	user_id INTEGER -- set after email verification
);

CREATE TABLE password_reset_request (
	id SERIAL PRIMARY KEY,
	user_id INTEGER NOT NULL REFERENCES user_account (id) ON DELETE CASCADE,
	sent_to_address VARCHAR(50) NOT NULL,
	token VARCHAR(15) UNIQUE,
	created_at TIMESTAMPTZ
);

--------------------------------------------------
-- Create metadata objects

CREATE COLLATION case_insensitive (
	provider = icu, -- "International Components for Unicode"
	-- und stands for undefined (ICU root collation - language agnostic)
	-- colStrength=primary ignores case and accents
	-- colNumeric=yes sorts strings with numeric parts by numeric value
	-- colAlternate=shifted would recognize equality of equivalent punctuation sequences
	locale = 'und@colStrength=primary;colNumeric=yes',
	deterministic = false
);

--------------------------------------------------
-- Create content tables

CREATE TYPE tree_node_class AS ENUM (
	'lang',
	'tag',
	'type',
	'field',
	'category',
	'post',
	'link',
	'comment'
);

CREATE TYPE vote_type AS ENUM (
	'agree',
	'disagree'
);

CREATE TABLE tree_node (
	id SERIAL PRIMARY KEY,
	parent_id INTEGER REFERENCES tree_node (id) ON DELETE CASCADE, -- allow null for root
	node_class tree_node_class NOT NULL,
	link_node_id INTEGER REFERENCES tree_node (id) ON DELETE CASCADE, -- only for link nodes
	is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
	created_at TIMESTAMPTZ NOT NULL,
	created_by INTEGER REFERENCES user_account (id) ON DELETE SET NULL
);

CREATE INDEX tree_node_parent_idx ON tree_node (parent_id, is_deleted);

CREATE TABLE tree_node_internal_key (
	-- table for associating internal keys with specific system nodes
	id SERIAL PRIMARY KEY,
	node_id INTEGER REFERENCES tree_node (id) ON DELETE CASCADE,
	internal_key VARCHAR(10) NOT NULL
);

CREATE UNIQUE INDEX tree_node_internal_key_node_idx ON tree_node_internal_key (node_id);
CREATE UNIQUE INDEX tree_node_internal_key_idx ON tree_node_internal_key (internal_key);

CREATE TABLE tree_node_lang_code (
	-- table for associating lang codes with specific system nodes
	id SERIAL PRIMARY KEY,
	node_id INTEGER REFERENCES tree_node (id) ON DELETE CASCADE,
	lang_code VARCHAR(10) NOT NULL
);

CREATE INDEX tree_node_lang_code_node_idx ON tree_node_lang_code (node_id);
CREATE INDEX tree_node_lang_code_idx ON tree_node_lang_code (lang_code);

CREATE TABLE tree_node_vote (
	id SERIAL PRIMARY KEY,
	node_id INTEGER REFERENCES tree_node (id) ON DELETE CASCADE,
	vote vote_type NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	created_by INTEGER REFERENCES user_account (id) ON DELETE CASCADE
);

CREATE INDEX tree_node_vote_idx ON tree_node_vote (node_id, vote);
CREATE UNIQUE INDEX tree_node_vote_user_idx ON tree_node_vote (created_by, node_id);

CREATE TYPE tree_node_content_type AS ENUM (
	'title',
	'body'
);

CREATE TYPE tree_node_body_type AS ENUM (
	'plaintext',
	'markdown'
);

CREATE TABLE tree_node_content (
	id SERIAL PRIMARY KEY,
	tree_node_id INTEGER REFERENCES tree_node (id) ON DELETE CASCADE,
	content_type tree_node_content_type NOT NULL,
	body_type tree_node_body_type, -- only for body content
	text_content VARCHAR(2048) NOT NULL COLLATE case_insensitive,
	html_content TEXT, -- only for body content
	text_search TSVECTOR, -- for searching text_content
	created_at TIMESTAMPTZ NOT NULL,
	created_by INTEGER REFERENCES user_account (id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX tree_node_content_idx ON tree_node_content (tree_node_id, content_type, text_content);
CREATE INDEX tree_node_content_search_idx ON tree_node_content USING GIN (text_search);
CREATE INDEX tree_node_content_search_composite_idx ON tree_node_content (content_type, text_search);

-- automatically keep text_search up to date
CREATE TRIGGER tree_node_content_tsvector_update BEFORE INSERT OR UPDATE
ON tree_node_content FOR EACH ROW EXECUTE FUNCTION
tsvector_update_trigger(text_search, text_content);

CREATE TABLE tree_node_content_vote (
	id SERIAL PRIMARY KEY,
	tree_node_id INTEGER REFERENCES tree_node (id) ON DELETE CASCADE,
	content_type tree_node_content_type NOT NULL,
	content_id INTEGER REFERENCES tree_node_content (id) ON DELETE CASCADE,
	vote vote_type NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	created_by INTEGER REFERENCES user_account (id) ON DELETE CASCADE
);

CREATE INDEX tree_node_content_vote_idx ON tree_node_content_vote (tree_node_id, content_type, vote);
CREATE UNIQUE INDEX tree_node_content_vote_user_idx ON tree_node_content_vote (created_by, tree_node_id, content_id);

CREATE TYPE tag_target_type AS ENUM (
	'tree_node',
	'tree_node_content'
);

CREATE TABLE tag_vote (
	id SERIAL PRIMARY KEY,
	tag_node_id INTEGER REFERENCES tree_node (id) ON DELETE CASCADE,
	target_type tag_target_type NOT NULL,
	target_id INTEGER,
	vote vote_type NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	created_by INTEGER REFERENCES user_account (id) ON DELETE CASCADE
);

CREATE INDEX tag_vote_idx ON tag_vote (target_type, target_id, vote, tag_node_id);
CREATE UNIQUE INDEX tag_vote_user_idx ON tag_vote (created_by, target_type, target_id, tag_node_id);

CREATE TABLE tree_node_merge_vote (
	id SERIAL PRIMARY KEY,
	source_node_id INTEGER REFERENCES tree_node (id) ON DELETE CASCADE,
	target_node_id INTEGER REFERENCES tree_node (id) ON DELETE CASCADE,
	vote vote_type NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	created_by INTEGER REFERENCES user_account (id) ON DELETE CASCADE
);

CREATE INDEX tree_node_merge_vote_idx ON tree_node_merge_vote (source_node_id, target_node_id, vote);
CREATE UNIQUE INDEX tree_node_merge_vote_user_idx ON tree_node_merge_vote (created_by, source_node_id, target_node_id);

CREATE TABLE tree_node_move_vote (
	id SERIAL PRIMARY KEY,
	source_node_id INTEGER REFERENCES tree_node (id) ON DELETE CASCADE,
	target_node_id INTEGER REFERENCES tree_node (id) ON DELETE CASCADE,
	vote vote_type NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	created_by INTEGER REFERENCES user_account (id) ON DELETE CASCADE
);

CREATE INDEX tree_node_move_vote_idx ON tree_node_move_vote (source_node_id, target_node_id, vote);
CREATE UNIQUE INDEX tree_node_move_vote_user_idx ON tree_node_move_vote (created_by, source_node_id, target_node_id);

--------------------------------------------------
-- create triggers

CREATE FUNCTION delete_tree_node ()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
BEGIN
	DELETE FROM tag_vote WHERE target_type = 'tree_node' AND target_id = OLD.id;
	RETURN NULL;
END;
$$;

CREATE TRIGGER on_tree_node_delete AFTER DELETE ON tree_node
	FOR EACH ROW EXECUTE PROCEDURE delete_tree_node();

CREATE FUNCTION delete_tree_node_content ()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
BEGIN
	DELETE FROM tag_vote WHERE target_type = 'tree_node_content' AND target_id = OLD.id;
	RETURN NULL;
END;
$$;

CREATE TRIGGER on_tree_node_content_delete AFTER DELETE ON tree_node_content
	FOR EACH ROW EXECUTE PROCEDURE delete_tree_node_content();

--------------------------------------------------
-- create functions

-- delete everything assocaited with the user, except categories and tags
CREATE FUNCTION delete_user_content (
	user_id_param INTEGER
)
RETURNS VOID
LANGUAGE PLPGSQL
AS $$
BEGIN
	DELETE FROM user_session WHERE user_id = user_id_param;
	DELETE FROM user_account WHERE id = user_id;
	DELETE FROM user_signup_request WHERE user_id = user_id_param;
	DELETE FROM password_reset_request WHERE user_id = user_id_param;
	DELETE FROM tag_vote WHERE created_by = user_id_param;
	-- delete content across tree
END;
$$;

--------------------------------------------------
-- create db init function

CREATE FUNCTION init_db_content (
	user_id INTEGER
)
RETURNS VOID
LANGUAGE PLPGSQL
AS $$
DECLARE
	root_node_id INTEGER;
	langs_node_id INTEGER;
	lang_en_node_id INTEGER;
	tag_node_id INTEGER;
	types_node_id INTEGER;
BEGIN
	-- exit if any tree node exists
	PERFORM 1 FROM tree_node LIMIT 1;
	IF FOUND THEN
		RETURN;
	END IF;

	-- create root node
	INSERT INTO tree_node (node_class, created_at, created_by)
	VALUES ('category', NOW(), user_id)
	RETURNING id INTO root_node_id;

	INSERT INTO tree_node_content (tree_node_id, content_type, text_content, created_at, created_by)
	VALUES (root_node_id, 'title', 'TreeTime', NOW(), user_id);

	INSERT INTO tree_node_internal_key (node_id, internal_key)
	VALUES (root_node_id, 'treetime');

	-- create languages category
	INSERT INTO tree_node (node_class, created_at, created_by)
	VALUES ('category', NOW(), user_id)
	RETURNING id INTO langs_node_id;

	INSERT INTO tree_node_content (tree_node_id, content_type, text_content, created_at, created_by)
	VALUES (langs_node_id, 'title', 'Languages', NOW(), user_id);

	INSERT INTO tree_node_internal_key (node_id, internal_key)
	VALUES (langs_node_id, 'langs');

	-- create English lang
	INSERT INTO tree_node (node_class, parent_id, created_at, created_by)
	VALUES ('lang', langs_node_id, NOW(), user_id)
	RETURNING id INTO lang_en_node_id;

	INSERT INTO tree_node_content (tree_node_id, content_type, text_content, created_at, created_by)
	VALUES (lang_en_node_id, 'title', 'English', NOW(), user_id);

	INSERT INTO tree_node_lang_code (node_id, lang_code)
	VALUES (lang_en_node_id, 'en');

	-- create tags category
	INSERT INTO tree_node (node_class, created_at, created_by)
	VALUES ('category', NOW(), user_id)
	RETURNING id INTO tag_node_id;

	INSERT INTO tree_node_content (tree_node_id, content_type, text_content, created_at, created_by)
	VALUES (tag_node_id, 'title', 'Tags', NOW(), user_id);

	INSERT INTO tree_node_internal_key (node_id, internal_key)
	VALUES (tag_node_id, 'tags');

	-- create types category
	INSERT INTO tree_node (node_class, created_at, created_by)
	VALUES ('category', NOW(), user_id)
	RETURNING id INTO types_node_id;

	INSERT INTO tree_node_content (tree_node_id, content_type, text_content, created_at, created_by)
	VALUES (types_node_id, 'title', 'Types', NOW(), user_id);

	INSERT INTO tree_node_internal_key (node_id, internal_key)
	VALUES (types_node_id, 'types');
END;
$$;

--------------------------------------------------
-- set first user to admin

CREATE FUNCTION set_first_user_to_admin ()
RETURNS TRIGGER
LANGUAGE PLPGSQL
AS $$
BEGIN
	PERFORM 1 FROM user_account WHERE user_role = 'admin' LIMIT 1;
	IF FOUND THEN
		RETURN NULL;
	END IF;

	NEW.user_role := 'admin';

	PERFORM init_db_content(user_id);

	-- delete trigger and function
	DROP TRIGGER on_user_account_insert ON user_account;
	DROP FUNCTION set_first_user_to_admin;
	DROP FUNCTION init_db_content;

	RETURN NULL;
END;
$$;

CREATE TRIGGER on_user_account_insert AFTER INSERT ON user_account
	FOR EACH ROW EXECUTE PROCEDURE set_first_user_to_admin();
