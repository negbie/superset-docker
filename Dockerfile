# sudo docker build -t negbie/superset-docker:git .
# sudo docker push negbie/superset-docker:git

FROM node:12-alpine as assets-builder

ENV SUPERSET_REPO_NAME        incubator-superset
ENV SUPERSET_ASSETS_DIST_PATH /superset-assets-dist

WORKDIR /
RUN apk add curl git
RUN git clone --depth 1 -b master https://github.com/apache/incubator-superset \
 && cd ${SUPERSET_REPO_NAME}/superset/assets \
 && npm ci \
 && npm run build \
 && mv dist /superset-assets-dist \
 && cd / \
 && rm -rf ${SUPERSET_REPO_NAME}

FROM python:3.6-stretch

# Never prompts the user for choices on installation/configuration of packages
ENV DEBIAN_FRONTEND noninteractive
ENV TERM linux

ENV SUPERSET_HOME    /usr/app/superset
ENV SUPERSET_USER    superset
ENV SUPERSET_UID     54321
ENV SUPERSET_GROUP   ${SUPERSET_USER}
ENV SUPERSET_GID     ${SUPERSET_UID}
ENV SUPERSET_SHELL   /bin/bash

ENV SUPERSET_APP_PATH         ${SUPERSET_HOME}/superset
ENV SUPERSET_ASSETS_PATH      ${SUPERSET_APP_PATH}/assets
ENV PATH                      ${SUPERSET_APP_PATH}/bin:${PATH}
ENV PYTHONPATH                ${SUPERSET_APP_PATH}:${PYTHONPATH}
ENV SUPERSET_ASSETS_DIST_PATH /superset-assets-dist

# Define en_US.
ENV LANGUAGE    en_US.UTF-8
ENV LANG        en_US.UTF-8
ENV LC_ALL      en_US.UTF-8
ENV LC_CTYPE    en_US.UTF-8
ENV LC_MESSAGES en_US.UTF-8
ENV LC_ALL      en_US.UTF-8


COPY --from=assets-builder ${SUPERSET_ASSETS_DIST_PATH} ${SUPERSET_ASSETS_DIST_PATH}

WORKDIR /workspace
COPY requirements-extras.txt .
RUN set -ex \
 && buildDeps=' \
        build-essential \
        libffi-dev \
        libpq-dev \
        libsasl2-dev \
        libssl-dev \
        python3-dev \
        python3-pip \
        zlib1g-dev \
    ' \
 && apt-get update -yqq \
 && apt-get install -yqq --no-install-recommends \
        $buildDeps \
        apt-utils \
        curl \
        git \
        locales \
        postgresql-client \
        redis-tools \
        gettext-base \
 && sed -i 's/^# en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/g' /etc/locale.gen \
 && locale-gen \
 && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
 && git clone --depth 1 -b master https://github.com/apache/incubator-superset ${SUPERSET_HOME} \
 && groupadd -r -g ${SUPERSET_GID} ${SUPERSET_GROUP} \
 && useradd -r -m -N \
        -d ${SUPERSET_HOME} \
        -g ${SUPERSET_GROUP} \
        -s ${SUPERSET_SHELL} \
        -u ${SUPERSET_UID} \
        ${SUPERSET_USER} \
 && pip install --no-cache-dir -r ${SUPERSET_HOME}/requirements-dev.txt -r ${SUPERSET_HOME}/requirements.txt \
 && pip install --no-cache-dir -r requirements-extras.txt \
 && apt-get remove --purge -yqq $buildDeps \
 && apt-get clean \
 && rm -rf \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /usr/share/man \
        /usr/share/doc \
        /usr/share/doc-base \
 && mv ${SUPERSET_ASSETS_DIST_PATH} ${SUPERSET_ASSETS_PATH}/dist \
 && chown ${SUPERSET_USER}:${SUPERSET_GROUP} -R ${SUPERSET_HOME}

 # Install the latest version of Firefox:
RUN export DEBIAN_FRONTEND=noninteractive \
  && apt-get update \
  && apt-get install --no-install-recommends --no-install-suggests -y \
    # Firefox dependencies:
    libgtk-3-0 \
    libdbus-glib-1-2 \
    libxt6 \
    bzip2 \
  && DL='https://download.mozilla.org/?product=firefox-latest-ssl&os=linux64' \
  && curl -sL "$DL" | tar -xj -C /opt \
  && ln -s /opt/firefox/firefox /usr/local/bin/ \
  # Remove obsolete files:
  && apt-get autoremove --purge -y bzip2 \
  && apt-get clean \
  && rm -rf \
    /tmp/* \
    /usr/share/doc/* \
    /var/cache/* \
    /var/lib/apt/lists/* \
    /var/tmp/*

# Install the latest version of Geckodriver:
RUN BASE_URL=https://github.com/mozilla/geckodriver/releases/download \
  && VERSION=$(curl -sL \
    https://api.github.com/repos/mozilla/geckodriver/releases/latest | \
    grep tag_name | cut -d '"' -f 4) \
  && curl -sL "$BASE_URL/$VERSION/geckodriver-$VERSION-linux64.tar.gz" | \
  tar -xz -C /usr/local/bin

USER       ${SUPERSET_USER}
WORKDIR    ${SUPERSET_HOME}

COPY       superset_config.py ${SUPERSET_APP_PATH}
COPY       entrypoint.sh .
ENTRYPOINT ["./entrypoint.sh"]

HEALTHCHECK CMD ["curl", "-f", "http://localhost:8088/health"]
EXPOSE     8088
