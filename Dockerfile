FROM node:20-alpine

RUN apk add --no-cache git nginx gettext jq

RUN mkdir -p /var/www/html /tmp/workdir /run/nginx

COPY nginx.conf.template /etc/nginx/http.d/default.conf.template
COPY sync.sh /sync.sh
COPY index.html /template.html
RUN chmod +x /sync.sh

EXPOSE 80

CMD envsubst < /etc/nginx/http.d/default.conf.template > /etc/nginx/http.d/default.conf && /sync.sh & nginx -g 'daemon off;'