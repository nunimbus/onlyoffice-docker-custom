FROM debian:stable-slim

# Default variables for services:
ENV NODE_ENV=production-linux \
    NODE_CONFIG_DIR=/etc/onlyoffice/documentserver \
    NODE_DISABLE_COLORS=1 \
    APPLICATION_NAME=ONLYOFFICE \
\
# Default variables for entrypoint script:
    DB_TYPE=mysql \
    DB_HOST=mariadb.local \
    DB_PORT=3306 \
    DB_NAME=onlyoffice \
    DB_USER=onlyoffice \
    DB_PWD=onlyoffice \
    JWT_ENABLED=true \
    JWT_HEADER=Authorization \
    JWT_SECRET=onlyoffice \
    RABBITMQ_USER=guest \
    RABBITMQ_PWD=guest \
    RABBITMQ_HOST=localhost

RUN apt-get update && apt-get install -y ca-certificates gnupg2 dos2unix curl

RUN { \
    echo "deb https://deb.debian.org/debian $(env -i bash -c '. /etc/os-release; echo $VERSION_CODENAME') main contrib non-free"; \
    echo "deb-src https://deb.debian.org/debian $(env -i bash -c '. /etc/os-release; echo $VERSION_CODENAME') main contrib non-free"; \
    echo "deb https://deb.debian.org/debian-security/ $(env -i bash -c '. /etc/os-release; echo $VERSION_CODENAME')-security main contrib non-free"; \
    echo "deb-src https://deb.debian.org/debian-security/ $(env -i bash -c '. /etc/os-release; echo $VERSION_CODENAME')-security main contrib non-free"; \
} > /etc/apt/sources.list.d/contrib.list ; \
    echo "deb https://download.onlyoffice.com/repo/debian squeeze main" > /etc/apt/sources.list.d/onlyoffice.list ; \
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys CB2DE8E5 ; \
    curl -fsSL https://deb.nodesource.com/setup_16.x | bash - ;

# Install the OpenOffice prerequisites
RUN apt-get update && apt-get install -y \
    rabbitmq-server \
    git \
    nodejs \
    libasound2 \
    libcairo2 \
    libcurl4 \
    libcurl3-gnutls \
    libgconf-2-4 \
    libgtk-3-0 \
    libxml2 \
    libxss1 \
    libxtst6 \
    logrotate \
    nginx-extras \
    pwgen \
    xvfb \
    ttf-mscorefonts-installer ;

# Install OnlyOffice
RUN echo onlyoffice-documentserver onlyoffice/db-type select mariadb | debconf-set-selections ; \
    echo onlyoffice-documentserver onlyoffice/db-host string localhost | debconf-set-selections ; \
    echo onlyoffice-documentserver onlyoffice/db-port string 3306 | debconf-set-selections ; \
    echo onlyoffice-documentserver onlyoffice/db-name string onlyoffice | debconf-set-selections ; \
    echo onlyoffice-documentserver onlyoffice/db-user string onlyoffice | debconf-set-selections ; \
    echo onlyoffice-documentserver onlyoffice/db-pwd password onlyoffice | debconf-set-selections ; \
    mkdir onlyoffice ; \
    apt-get download onlyoffice-documentserver > /dev/null 2>&1 ; \
    dpkg-deb -R onlyoffice-documentserver*.deb onlyoffice/ ; \
    sed -i 's/install_db$//g' onlyoffice/DEBIAN/postinst  ; \
    sed -i 's/service supervisor.*$//g' onlyoffice/DEBIAN/postinst  ; \
    sed -i 's/\(mysql-client\|mariadb-client\|postgresql-client\|supervisor\)[0-9a-z<>=\. ()]*//g' onlyoffice/DEBIAN/control ; \
    sed -i 's/, [\|, ]*,/,/g' onlyoffice/DEBIAN/control ; \
    dpkg-deb -z0 -Z none -S none -b onlyoffice/ onlyoffice.deb ; \
    dpkg -i onlyoffice.deb  ; \
    rm -r /onlyoffice*

# Pull the raw source of the server
RUN cd /var/www/onlyoffice/documentserver/server; \
    git init ; \
    git remote add origin https://github.com/ONLYOFFICE/server ; \
    git fetch ; \
    git reset --hard v$(dpkg -s onlyoffice-documentserver | grep Version | sed 's/^Version: //g' | sed 's/-/\./g') ; \
    rm -r /var/www/onlyoffice/documentserver/server/.git ;

# Convert the file endings
RUN for file in $(find /var/www/onlyoffice/documentserver/server -type f) ; \
    do \
      dos2unix "$file" ; \
    done

RUN buildVersion=$(dpkg -s onlyoffice-documentserver | grep Version | sed 's/^Version: //g' | sed 's/-.*//g') ; \
    buildNumber=$(dpkg -s onlyoffice-documentserver | grep Version | sed 's/^Version: //g' | sed 's/.*-//g') ; \
    sed -i "s/const buildVersion.*/const buildVersion = '$buildVersion';/g" /var/www/onlyoffice/documentserver/server/Common/sources/commondefines.js ; \
    sed -i "s/const buildNumber.*/const buildNumber = '$buildNumber';/g" /var/www/onlyoffice/documentserver/server/Common/sources/commondefines.js ; \
    rm /var/www/onlyoffice/documentserver/server/DocService/docservice /var/www/onlyoffice/documentserver/server/FileConverter/converter ; 

# Install the custom patches
RUN git clone https://github.com/nunimbus/onlyoffice_encryption_patches
RUN for patch in $(find /onlyoffice_encryption_patches -name *.patch) ; \
    do \
      sourceLib=$(echo "$patch" | sed 's/\.patch$//g') ; \
      sourceLib=$(echo "$sourceLib" | sed 's#^/onlyoffice_encryption_patches#/var/www/#g') ; \
      patch "$sourceLib" "$patch" ; \
    done

RUN cd /var/www/onlyoffice/documentserver/server/DocService ; \
    npm install package.json ; \
    cd /var/www/onlyoffice/documentserver/server/FileConverter ; \
    npm install package.json ; \
    cd /var/www/onlyoffice/documentserver/server/Common ; \
    npm install package.json ; \
    chown -R ds:ds /var/www/onlyoffice/documentserver/server/FileConverter /var/www/onlyoffice/documentserver/server/DocService

RUN sed -i 's%\(user:{\)%\1sessionData:document.cookie,%g' \
    /var/www/onlyoffice/documentserver/sdkjs/cell/sdk-all-min.js \
    /var/www/onlyoffice/documentserver/sdkjs/slide/sdk-all-min.js \
    /var/www/onlyoffice/documentserver/sdkjs/word/sdk-all-min.js

# Cleanup
RUN apt-get autoremove -y gnupg2 git dos2unix && \
    apt-get clean

COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh
CMD ["/entrypoint.sh"]

######## DEBUG ########
ARG VIM=0

RUN if [ $VIM -eq 1 ] ; \
    then \
      apt-get install -y vim ; \
      { \
        echo ':set mouse-=a'; \
        echo ':set t_BE='; \
        echo ':syntax on'; \
        echo ':set ruler'; \
        echo ':set encoding=utf-8'; \
        echo ':set pastetoggle=<F2>'; \
        echo ':retab!'; \
        echo ':set noexpandtab'; \
        echo ':set tabstop=4'; \
      } > /root/.vimrc 2>1; \
    fi ;
