create table if not exists albums(
    date varchar(12) not null,
    artist varchar(255) not null,
    album varchar(255) not null,
    rating smallint not null
);
create index if not exists album_ratings_idx ON albums (rating);
CREATE UNIQUE INDEX albums_dir_idx ON albums (album);
