FROM node:20-alpine

RUN apk add --no-cache git nginx gettext jq

ENV npm_config_cache=/var/cache/npm
RUN mkdir -p /var/www/html /tmp/workdir /run/nginx /var/cache/npm

COPY nginx.conf.template /etc/nginx/http.d/default.conf.template
COPY sync.sh /sync.sh
COPY sync_project.sh /sync_project.sh
COPY index_gen.sh /index_gen.sh
COPY nginx_conf_gen.sh /nginx_conf_gen.sh
COPY utils.sh /utils.sh
COPY index.html /template.html

RUN chmod +x /sync.sh /sync_project.sh /index_gen.sh /nginx_conf_gen.sh /utils.sh

EXPOSE 80

CMD envsubst < /etc/nginx/http.d/default.conf.template > /etc/nginx/http.d/default.conf && /sync.sh & nginx -g 'daemon off;'