CREATE TABLE task_error (
    id SERIAL PRIMARY KEY,
    message TEXT NOT NULL,
    metadata jsonb,
    type character varying(64) NOT NULL,
    created timestamp with time zone DEFAULT now() NOT NULL
);
