-- Clean up previous instance

DROP TABLE IF EXISTS user_signup_request CASCADE;
DROP TABLE IF EXISTS password_reset_request CASCADE;
DROP TABLE IF EXISTS user_session CASCADE;
DROP TABLE IF EXISTS user_account CASCADE;
DROP TYPE IF EXISTS user_role_type;

DROP COLLATION IF EXISTS case_insensitive;

--------------------------------------------------
-- Create user management and session tables

CREATE TYPE user_role_type AS ENUM (
	'admin', -- can do anything
	'moderator', -- can delete and edit stuff
	'user', -- can create categories, posts, comments, and votes
	'inactive', -- can't do anything
	'banned' -- can't do anything
);

CREATE TABLE user_account (
	id SERIAL PRIMARY KEY,
	email VARCHAR(50) UNIQUE NOT NULL,
	user_role user_role_type NOT NULL DEFAULT 'user',
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
	email VARCHAR(50) NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	token VARCHAR(15) UNIQUE NOT NULL
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

CREATE TABLE unique_text (
	id SERIAL PRIMARY KEY,
	text_value TEXT UNIQUE NOT NULL
);

CREATE TYPE space_type ENUM (
	'space', -- (nameless; contains titles and other spaces)
	'checkin', -- user checking in a space to another space
	'title', -- plain text (no newlines), special handling to give a space an active title
	'tag', -- plain text (no newlines), special handling to give a space a set of active tags
	'text', -- plain text entered by a user
	'naked-text', -- text with realtime replay data
	'picture',
	'audio',
	'video',
	'stream-of-consciousness', -- contains a stream of text checkins
	'json-attribute', -- URL and json path and refresh rate

	-- monetization -- fee is 1¢. per second
	'rental-space',
	'rental-payment',
	'rental-donor',
	'rental-payee',
	'rental-payout'
);

CREATE TABLE space ( -- a domain that contains subspaces
	id SERIAL PRIMARY KEY,
	parent_id INTEGER REFERENCES space (id) ON DELETE CASCADE,
	space_type space_type NOT NULL,
	created_at TIMESTAMPTZ NOT NULL,
	created_by INTEGER NOT NULL REFERENCES user_account (id) ON DELETE CASCADE,
);

CREATE TYPE checkin_time (
	'past',
	'now',
	'future'
);

CREATE TABLE checkin_space ( -- a link to another space somewhere else
	checkin_space_id INTEGER REFERENCES space (id) ON DELETE CASCADE,
	checkin_time checkin_time NOT NULL
);

CREATE TABLE title_space (
	space_id INTEGER PRIMARY KEY REFERENCES space (id) ON DELETE CASCADE,
	unique_text_id TEXT NOT NULL
);

CREATE TABLE tag_space (
	space_id INTEGER PRIMARY KEY REFERENCES space (id) ON DELETE CASCADE,
	unique_text_id TEXT NOT NULL
);

CREATE TABLE text_space (
	space_id INTEGER PRIMARY KEY REFERENCES space (id) ON DELETE CASCADE,
	unique_text_id TEXT COLLATE case_insensitive NOT NULL
);

CREATE TABLE naked_text_space (
	space_id INTEGER PRIMARY KEY REFERENCES space (id) ON DELETE CASCADE,
	final_unique_text_id INTEGER NOT NULL,
	replay_data JSON NOT NULL
);

CREATE TABLE json_attribute_space (
	space_id INTEGER PRIMARY KEY REFERENCES space (id) ON DELETE CASCADE,
	url TEXT NOT NULL,
	json_path TEXT NOT NULL,
	refresh_rate INTERVAL
);

CREATE TYPE rental_space_payout_type (
	'creators',
	'public',
	'platform', -- basically a donation to my company
	'none'
);

CREATE TABLE rental_space (
	space_id INTEGER PRIMARY KEY REFERENCES space (id) ON DELETE CASCADE,
	creator_ids INTEGER[] NOT NULL,
	payout_type rental_space_payout_type NOT NULL,
	private BOOLEAN NOT NULL DEFAULT FALSE, -- platform payouts cannot be private
	approved BOOLEAN NOT NULL, -- private spaces must be approved before publishing
	release_payment BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE rental_space_payee (
	space_id INTEGER PRIMARY KEY REFERENCES space (id) ON DELETE CASCADE,
	payee_id INTEGER NOT NULL
);

CREATE TABLE space_activity (
	space_id INTEGER NOT NULL REFERENCES space (id) ON DELETE CASCADE,
	overall_total INTEGER NOT NULL,
	remaining_count INTEGER NOT NULL, -- decrements by 1 per second
	last_update TIMESTAMPTZ NOT NULL
);

CREATE TABLE space_title_activity (
	space_id INTEGER NOT NULL REFERENCES space (id) ON DELETE CASCADE,
	unique_text_id TEXT NOT NULL,
	overall_total INTEGER NOT NULL,
	remaining_count INTEGER NOT NULL, -- decrements by 1 per second
	last_update TIMESTAMPTZ NOT NULL
);

CREATE TABLE space_tag_activity (
	space_id INTEGER NOT NULL REFERENCES space (id) ON DELETE CASCADE,
	unique_text_id TEXT NOT NULL,
	overall_total INTEGER NOT NULL,
	remaining_count INTEGER NOT NULL, -- decrements by 1 per second
	last_update TIMESTAMPTZ NOT NULL
);
