DROP TABLE IF EXISTS collection;
DROP TABLE IF EXISTS item;

CREATE TABLE collection (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE NOT NULL,
  description TEXT NOT NULL
);

CREATE TABLE item (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE NOT NULL,
  description TEXT NOT NULL,
  FOREIGN KEY (collection_id) REFERENCES collection (id)
);