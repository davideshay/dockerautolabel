FROM docker
ENV CONTAINER_NAME="" \
    FORCE_UPDATE="true"

RUN apk add --no-cache jq curl

RUN mkdir /config

COPY monitor.sh /monitor.sh

RUN chmod 744 /monitor.sh

VOLUME "/config"

ENTRYPOINT ["sh","/monitor.sh"]

