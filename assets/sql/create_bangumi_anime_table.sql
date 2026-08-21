CREATE TABLE bangumi_anime (

  bangumi_anime_id INTEGER PRIMARY KEY CHECK (bangumi_anime_id >= 0),
  anime_id INTEGER NOT NULL UNIQUE,
  FOREIGN KEY (anime_id) REFERENCES anime (anime_id) ON DELETE CASCADE

) STRICT;
