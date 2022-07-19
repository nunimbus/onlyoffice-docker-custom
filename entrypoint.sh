#!/bin/bash

# I considered doing this via a script (perhaps Python - it's installed), but
# it just seemed like overkill even though this is a little dirty.

{
    echo '{'; \
    echo '  "services"': {; \
    echo '    "CoAuthoring"': {; \
    echo '      "sql"': {; \
    echo '        "type"': '"'${DB_TYPE}'"',; \
    echo '        "dbHost"': '"'${DB_HOST}'"',; \
    echo '        "dbPort"': '"'${DB_PORT}'"',; \
    echo '        "dbName"': '"'${DB_NAME}'"',; \
    echo '        "dbUser"': '"'${DB_USER}'"',; \
    echo '        "dbPass"': '"'${DB_PWD}'"'; \
    echo '      },'; \
    echo '      "token"': {; \
    echo '        "enable"': {; \
    echo '          "request"': {; \
    echo '            "inbox"': ${JWT_ENABLED},; \
    echo '            "outbox"': ${JWT_ENABLED}; \
    echo '          },'; \
    echo '          "browser"': ${JWT_ENABLED}; \
    echo '        },'; \
    echo '        "inbox"': {; \
    echo '          "header"': '"'${JWT_HEADER}'"'; \
    echo '        },'; \
    echo '        "outbox"': {; \
    echo '          "header"': '"'${JWT_HEADER}'"'; \
    echo '        }'; \
    echo '      },'; \
    echo '      "secret"': {; \
    echo '        "inbox"': {; \
    echo '          "string"': '"'${JWT_SECRET}'"'; \
    echo '        },'; \
    echo '        "outbox"': {; \
    echo '          "string"': '"'${JWT_SECRET}'"'; \
    echo '        },'; \
    echo '        "session"': {; \
    echo '          "string"': '"'${JWT_SECRET}'"'; \
    echo '        }'; \
    echo '      },'; \
    echo '      "expire"': {; \
    echo '        "filesCron"': '"*/1 * * * *"',; \
    echo '        "files"': '60'; \
    echo '      }'; \
    echo '    }'; \
    echo '  },'; \
    echo '  "rabbitmq"': {; \
    echo '    "url"': '"amqp://'${RABBITMQ_USER}:${RABBITMQ_PWD}@${RABBITMQ_HOST}'"'; \
    echo '  }'; \
    echo '}'; \
} > /etc/onlyoffice/documentserver/local.json;

# Start the services (not using supervisord)
pkill rabbitmq
pkill docservice
pkill converter
pkill nginx
rabbitmq-server & sleep 5 

export NODE_CONFIG_DIR=/etc/onlyoffice/documentserver
export LD_LIBRARY_PATH=/var/www/onlyoffice/documentserver/server/FileConverter/bin

if [[ ${DEBUG} ]]
then
    export NODE_ENV=development-linux
    cd /var/www/onlyoffice/documentserver/server/DocService && node --inspect=9228 --max-http-header-size=16384 sources/server.js &
    cd /var/www/onlyoffice/documentserver/server/FileConverter && node --inspect=9230 --max-http-header-size=16384 sources/convertermaster.js &
else
    export NODE_ENV=production-linux
    cd /var/www/onlyoffice/documentserver/server/DocService && node --max-http-header-size=16384 sources/server.js &
    cd /var/www/onlyoffice/documentserver/server/FileConverter && node --max-http-header-size=16384 sources/convertermaster.js &
fi

nginx -g 'daemon off;'
