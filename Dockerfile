FROM node:20-alpine

RUN apk add --no-cache git

RUN mkdir -p /var/www/html /tmp/workdir /var/cache/npm
ENV npm_config_cache=/var/cache/npm

WORKDIR /app

COPY package.json .
COPY server.mjs .
COPY index.html .

RUN npm install

EXPOSE 80

CMD ["npm", "start"]