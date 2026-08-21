CREATE TABLE dandanplay_anime (

  dandanplay_anime_id INTEGER PRIMARY KEY CHECK (dandanplay_anime_id >= 0),
  anime_id INTEGER NOT NULL,

  FOREIGN KEY (anime_id) REFERENCES anime (anime_id) ON DELETE CASCADE

) STRICT;
