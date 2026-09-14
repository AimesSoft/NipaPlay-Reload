CREATE TABLE episode (

  episode_id INTEGER PRIMARY KEY CHECK (episode_id >= 0),
  anime_id   INTEGER NOT NULL,
  merged_into INTEGER REFERENCES episode (episode_id) CHECK (merged_into != episode_id),

  FOREIGN KEY (anime_id) REFERENCES anime (anime_id) ON DELETE CASCADE

) STRICT;
