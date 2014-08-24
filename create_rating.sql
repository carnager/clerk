create table if not exists tracks(
    date varchar(12) not null,
    artist varchar(255) not null,
    album varchar(255) not null,
    directory varchar(500) not null,
    rating smallint not null
);
create index if not exists track_ratings_idx ON tracks (rating);

create table if not exists albums(
    date varchar(12) not null,
    artist varchar(255) not null,
    album varchar(255) not null,
    directory varchar(500) not null,
    rating smallint not null
);
create index if not exists album_ratings_idx ON albums (rating);
