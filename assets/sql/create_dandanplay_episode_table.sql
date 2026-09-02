CREATE TABLE dandanplay_episode (

  dandanplay_episode_id INTEGER PRIMARY KEY CHECK (dandanplay_episode_id >= 0),
  dandanplay_anime_id   INTEGER NOT NULL,
  episode_id            INTEGER NOT NULL UNIQUE,

  FOREIGN KEY (dandanplay_anime_id) REFERENCES dandanplay_anime (dandanplay_anime_id) ON DELETE CASCADE,
  FOREIGN KEY (episode_id         ) REFERENCES episode          (episode_id         ) ON DELETE CASCADE

) STRICT;
