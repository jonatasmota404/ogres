# Self-contained web image for Coolify: static site + compiled app + /ws proxy.

FROM node:22-alpine AS node
WORKDIR /node
COPY package.json package-lock.json ./
RUN npm ci
COPY src ./src
RUN npx esbuild \
  --bundle \
  --minify \
  --loader:.svg=dataurl \
  --outfile=./out/ogres.app.css \
  ./src/main/ogres/app/resource/root.css

FROM clojure:temurin-21-tools-deps-bookworm AS build
ARG SERVER_SOCKET_URL="wss://rpg.jonatas.pro/ws"
ARG VERSION="latest"
ENV OUTPUT_DIR="web/release/${VERSION}" \
  ASSET_PATH="release/${VERSION}"
WORKDIR /build
COPY deps.edn ./
RUN clojure -P
COPY . .
COPY --from=node /node/node_modules ./node_modules/
RUN clojure -M -m shadow.cljs.devtools.cli release app \
  --config-merge "{:closure-defines {ogres.app.const/VERSION \"${VERSION}\" ogres.app.const/PATH \"/release/${VERSION}\" ogres.app.const/SOCKET-URL \"${SERVER_SOCKET_URL}\"}}"
COPY --from=node /node/out/ogres.app.css ./web/release/${VERSION}/
RUN cp web/release/icons.svg web/release/${VERSION}/ \
  && rm -rf web/release/${VERSION}/cljs-runtime web/release/${VERSION}/manifest.edn \
  && echo "${VERSION}" > web/releases.txt

FROM nginx:1.27-alpine
ENV BACKEND_URL="http://backend:8090/ws"
COPY site/web /usr/share/nginx/site
COPY --from=build /build/web /usr/share/nginx/app
COPY deploy/coolify-nginx.template /etc/nginx/templates/default.conf.template
EXPOSE 80
