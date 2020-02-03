FROM ubuntu:18.04

ARG PG_VERSION=11
ARG DEBIAN_FRONTEND=noninteractive
ARG PG_VERSION=$PG_VERSION
ARG MAPFILE="http://download.geofabrik.de/europe/italy-latest.osm.pbf"

ARG PGUSER=pgis_user
ARG PGPASS=pgis_pwd
ARG PGDB=pgis

ENV POSTGRES_USER=$PGUSER
ENV POSTGRES_PASSWORD=$PGPASS
ENV DBNAME=$PGDB

ENV PGMAJOR=$PG_VERSION
ENV POSTGIS_MAJOR=3

RUN apt-get update && apt-get install -y gnupg2 wget lsb-release

RUN wget --no-check-certificate --quiet -O - http://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
RUN RELEASE=$(lsb_release -cs) && echo "deb http://apt.postgresql.org/pub/repos/apt/ ${RELEASE}"-pgdg main | tee /etc/apt/sources.list.d/pgdg.list

# https://wiki.openstreetmap.org/wiki/PostGIS/Installation
RUN apt-get update &&\
    apt-get install -y --no-install-recommends \
    software-properties-common \
    postgresql-client-${PGMAJOR} \
    postgresql-contrib-${PGMAJOR} \
    postgresql-${PGMAJOR} \
    postgresql-client-${PGMAJOR} \
    postgresql-contrib-${PGMAJOR} \
    postgis \
    postgresql-${PGMAJOR}-postgis-${POSTGIS_MAJOR} \
    postgresql-${PGMAJOR}-postgis-${POSTGIS_MAJOR}-scripts \
    postgresql-${PGMAJOR}-pgrouting \
    osm2pgsql \
    && rm -rf /var/lib/apt/lists/*

RUN wget $MAPFILE -O mapfile.pbf

# Run the rest of the commands as the ``postgres`` user created by the ``postgres-11`` package when it was ``apt-get installed``
USER postgres

COPY prepare_db.sql /app/
RUN /etc/init.d/postgresql start &&\
    psql -U postgres --command "CREATE USER $POSTGRES_USER WITH SUPERUSER PASSWORD '$POSTGRES_PASSWORD';" &&\
    # https://www.postgresql.org/docs/current/libpq-envars.html
    createdb -U postgres -O $POSTGRES_USER $DBNAME &&\
    # https://www.postgresql.org/docs/current/libpq-envars.html
    export PGPASSWORD=$POSTGRES_PASSWORD &&\
    psql -h localhost -p 5432 --dbname $DBNAME --username $POSTGRES_USER --file /app/prepare_db.sql --password &&\
    # specify passsword in PGPASS environment variable or use -W
    export PGPASS=$POSTGRES_PASSWORD &&\
    #wget $MAPFILE -O /var/lib/postgres/mapfile.pbf &&\
    osm2pgsql --slim -C 18000 --number-processes 8 --host localhost --port 5432 --database $DBNAME --username $POSTGRES_USER mapfile.pbf

RUN echo "host    all             all             0.0.0.0/0           md5" >> /etc/postgresql/$PGMAJOR/main/pg_hba.conf &&\
    # And add ``listen_addresses`` to ``/etc/postgresql/11/main/postgresql.conf``
    echo "listen_addresses='*'" >> /etc/postgresql/$PGMAJOR/main/postgresql.conf


USER root
RUN rm mapfile.pbf

USER postgres

# Expose the PostgreSQL port
EXPOSE 5432

# Set the default command to run when starting the container
CMD /usr/lib/postgresql/$PGMAJOR/bin/postgres -D /var/lib/postgresql/$PGMAJOR/main -c config_file=/etc/postgresql/$PGMAJOR/main/postgresql.conf
