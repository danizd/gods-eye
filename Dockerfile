# God's Eye View — imagen para ARM64 (Oracle Ampere) y x86_64
# El modo soportado por el proyecto es su dev server de Vite (brokera claves API
# y sirve las fuentes en vivo), así que ejecutamos `vite` en el contenedor.
FROM node:24-slim

# OpenSSL para que Vite genere una secret genuina; curl para el healthcheck
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssl curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Puppeteer es solo para scripts QA del repo, no para runtime: evita descargar
# Chromium (~400 MB) y problemas de descarga en arm64 durante el build.
ENV PUPPETEER_SKIP_DOWNLOAD=true \
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true

# Capa de dependencias (cacheable), con el package-lock del repo
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

# Resto del código
COPY . .

ENV NODE_ENV=development \
    HOST=0.0.0.0 \
    PORT=4173

# HOST=0.0.0.0 activa allowedHosts:true en build/vite.js, necesario para que
# Vite acepte el header Host: god.movilab.es que llega desde Nginx Proxy Manager.
# El panel POWER UP bloquea por su cuenta las peticiones proxied (no depende de esto).

# Archivo de claves VACÍO por defecto; docker-compose montará encima el .env
# del host para que puedas editar las claves sin reconstruir la imagen (DEPLOY.md).
RUN touch .env && chmod 600 .env

# Ejecutar como usuario sin privilegios (uid 1000 = usuario `node` de la imagen,
# coincide con el uid típico del usuario en el host para el bind mount de .env)
RUN chown -R node:node /app
USER node

# Pre-compila la caché de dependencias de Vite en tiempo de build. Sin esto, el
# PRIMER arranque genera en caliente node_modules/.vite/deps/cesium.js (~10 MB)
# y las peticiones de esa URL pueden responder 504 tras el proxy hasta que acaba.
RUN npx vite optimize || true

EXPOSE 4173

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:4173/" -o /dev/null || exit 1

# Directo (sin npm run): mejor manejo de señales para `docker stop`.
CMD ["npx", "vite", "--host", "0.0.0.0", "--port", "4173"]
