#!/usr/bin/env bash

# function to initialize apache-superset
initialize_superset () {
    USER_COUNT=$(fabmanager list-users --app superset | awk '/email/ {print}' | wc -l)
    if [ "$?" ==  0 ] && [ $USER_COUNT == 0 ]; then
        # Create an admin user (you will be prompted to set username, first and last name before setting a password)

        fabmanager create-admin --username superset \
          --firstname superset \
          --lastname apache \
          --email superset@gunosy.com \
          --password superset \
          --app superset

        # Initialize the database
        superset db upgrade

        # Load some data to play with
        #superset load_examples

        # Create default roles and permissions
        superset init

        echo Initialized Apache-Superset. Happy Superset Exploration!
    else
        echo Apache-Superset Already Initialized.
    fi
}

if [ "$#" -ne 0 ]; then
    exec "$@"
else
    num_retries=0
    until psql -c "select 1" postgres://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB > /dev/null 2>&1; do
        echo "Waiting for postgres server...($((num_retries++))s)"
        sleep 1
    done

    set -ex
   
    initialize_superset

    celery worker --app=superset.sql_lab:celery_app --pool=gevent -Ofair &
    celery beat --app=superset.tasks.celery_app:app &

    gunicorn --bind  0.0.0.0:8088 \
        --workers $((2 * $(getconf _NPROCESSORS_ONLN) + 1)) \
        --timeout 60 \
        --limit-request-line 0 \
        --limit-request-field_size 0 \
        superset:app
fi

