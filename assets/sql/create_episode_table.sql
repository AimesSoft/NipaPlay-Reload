CREATE TABLE episode (

  episode_id INTEGER PRIMARY KEY CHECK (episode_id >= 0),
  anime_id   INTEGER NOT NULL,

  FOREIGN KEY (anime_id) REFERENCES anime (anime_id) ON DELETE CASCADE

) STRICT;
