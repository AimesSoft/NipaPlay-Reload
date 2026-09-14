CREATE TABLE anime (

  anime_id INTEGER PRIMARY KEY CHECK (anime_id >= 0),
  merged_into INTEGER REFERENCES anime (anime_id) CHECK (merged_into != anime_id)

) STRICT;
