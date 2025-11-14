FROM ubuntu:noble

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

# Generate locale C.UTF-8 for postgres and general locale data
ENV LANG=en_US.UTF-8

# Create odoo user and group
RUN groupadd -r odoo && useradd -r -g odoo odoo

# Retrieve the target architecture to install the correct wkhtmltopdf package
ARG TARGETARCH

# Install dependencies, including build tools for Odoo
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
        build-essential \
        python3-dev \
        libpq-dev \
        libldap2-dev \
        libsasl2-dev \
        libxml2-dev \
        libxslt1-dev \
        libjpeg-dev \
        libpng-dev \
        ca-certificates \
        curl \
        dirmngr \
        fonts-noto-cjk \
        gnupg \
        libssl-dev \
        node-less \
        npm \
        python3-magic \
        python3-num2words \
        python3-odf \
        python3-pdfminer \
        python3-pip \
        python3-phonenumbers \
        python3-pyldap \
        python3-qrcode \
        python3-renderpm \
        python3-setuptools \
        python3-slugify \
        python3-vobject \
        python3-watchdog \
        python3-xlrd \
        python3-xlwt \
        xz-utils \
        python3-venv && \
    if [ -z "${TARGETARCH}" ]; then \
        TARGETARCH="$(dpkg --print-architecture)"; \
    fi; \
    WKHTMLTOPDF_ARCH=${TARGETARCH} && \
    case ${TARGETARCH} in \
    "amd64") WKHTMLTOPDF_ARCH=amd64 && WKHTMLTOPDF_SHA=967390a759707337b46d1c02452e2bb6b2dc6d59  ;; \
    "arm64") WKHTMLTOPDF_ARCH=arm64 && WKHTMLTOPDF_SHA=90f6e69896d51ef77339d3f3a20f8582bdf496cc  ;; \
    "ppc64le" | "ppc64el") WKHTMLTOPDF_ARCH=ppc64el && WKHTMLTOPDF_SHA=5312d7d34a25b321282929df82e3574319aed25c  ;; \
    esac \
    && curl -o wkhtmltox.deb -sSL https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_${WKHTMLTOPDF_ARCH}.deb \
    && echo ${WKHTMLTOPDF_SHA} wkhtmltox.deb | sha1sum -c - \
    && apt-get install -y --no-install-recommends ./wkhtmltox.deb \
    && rm -rf /var/lib/apt/lists/* wkhtmltox.deb

# Install PostgreSQL client
RUN echo 'deb http://apt.postgresql.org/pub/repos/apt/ noble-pgdg main' > /etc/apt/sources.list.d/pgdg.list \
    && GNUPGHOME="$(mktemp -d)" \
    && export GNUPGHOME \
    && repokey='B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8' \
    && gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "${repokey}" \
    && gpg --batch --armor --export "${repokey}" > /etc/apt/trusted.gpg.d/pgdg.gpg.asc \
    && gpgconf --kill all \
    && rm -rf "$GNUPGHOME" \
    && apt-get update  \
    && apt-get install --no-install-recommends -y postgresql-client \
    && rm -f /etc/apt/sources.list.d/pgdg.list \
    && rm -rf /var/lib/apt/lists/*

# Install rtlcss
RUN npm install -g rtlcss

# Copy local Odoo source code
COPY ./src /usr/src/odoo
RUN chown -R odoo:odoo /usr/src/odoo

# Debugging step: List the contents of /usr/src/odoo
RUN ls -la /usr/src/odoo

# Create a virtual environment and install Python dependencies
USER root
RUN python3 -m venv /opt/odoo-venv && \
    /opt/odoo-venv/bin/pip install --upgrade pip && \
    /opt/odoo-venv/bin/pip install -r /usr/src/odoo/requirements.txt && \
    /opt/odoo-venv/bin/pip install -e /usr/src/odoo

# Remove build dependencies to reduce image size
RUN apt-get purge -y --auto-remove build-essential python3-dev libpq-dev libldap2-dev libsasl2-dev libxml2-dev libxslt1-dev libjpeg-dev libpng-dev && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Copy configuration and entrypoint
COPY ./entrypoint.sh /
RUN chmod +x /entrypoint.sh
COPY ./odoo.conf /etc/odoo/
RUN chown odoo /etc/odoo/odoo.conf

# Create /var/lib/odoo and set ownership
RUN mkdir -p /var/lib/odoo && chown -R odoo:odoo /var/lib/odoo
VOLUME ["/var/lib/odoo"]

# Expose ports and set environment
EXPOSE 8069 8071 8072
ENV ODOO_RC=/etc/odoo/odoo.conf

# Copy helper script
COPY wait-for-psql.py /usr/local/bin/wait-for-psql.py

# Switch to odoo user
USER odoo

# Activate virtual environment and start Odoo
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/opt/odoo-venv/bin/python", "-m", "odoo"]