CREATE TABLE bangumi_episode (

  bangumi_episode_id INTEGER PRIMARY KEY CHECK (bangumi_episode_id >= 0),
  bangumi_anime_id   INTEGER NOT NULL,
  episode_id         INTEGER NOT NULL UNIQUE,

  FOREIGN KEY (bangumi_anime_id) REFERENCES bangumi_anime (bangumi_anime_id) ON DELETE CASCADE,
  FOREIGN KEY (episode_id      ) REFERENCES episode       (episode_id      ) ON DELETE CASCADE

) STRICT;
