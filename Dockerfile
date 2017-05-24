FROM amazonlinux

ENV MIRTH_CONNECT_VERSION 3.5.0.8232.b2153

RUN yum install -y findutils wget java-1.8.0-openjdk mysql56 http://downloads.mirthcorp.com/connect/$MIRTH_CONNECT_VERSION/mirthconnect-$MIRTH_CONNECT_VERSION-linux.rpm jq aws-cli

RUN wget -q -O /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.2.0/dumb-init_1.2.0_amd64 \
 && chmod +x /usr/local/bin/dumb-init

EXPOSE 8080 8443

COPY init.sh /opt/mirthconnect/ 
RUN chmod +x /opt/mirthconnect/init.sh

ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
CMD ["bash", "-c", "exec opt/mirthconnect/init.sh"]
