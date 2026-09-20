# Despliegue de God's Eye View en Oracle ARM + Nginx Proxy Manager

Objetivo: `https://god.movilab.es` → contenedor `gev` en el puerto 4173, alcanzado por Nginx Proxy Manager a través de la red Docker compartida `proxy_network`.

## 0. Requisitos en el servidor Oracle ARM (Ubuntu aarch64)

```bash
# Docker + plugin compose
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER    # cierra sesión y vuelve a entrar
docker version                   # debe indicar arm64
```

> El free tier de Oracle ARM (Ampere A1) va sobrado: la app consume principalmente RAM del navegador del visitante; el servidor solo sirve assets y brokera peticiones.

## 1. Subir el proyecto

```bash
git clone https://github.com/bilawalsidhu/gods-eye-view.git
cd gods-eye-view
# (opcional pero recomendado) copia aquí los ficheros Dockerfile, .dockerignore,
# docker-compose.yml y DEPLOY.md de esta carpeta si clonaste el repo limpio
mkdir -p data/env
cp data/env/.env.example data/env/.env   # claves vacías para empezar
```

## 2. Arrancar

```bash
docker compose up -d --build
docker compose logs -f gev       # espera "VITE ready" en el puerto 4173
curl -I http://127.0.0.1:4173/   # debe responder 200
```

## 3. Nginx Proxy Manager

En el panel de NPM, añade un **Proxy Host**:

| Campo               | Valor                                    |
| ------------------- | ---------------------------------------- |
| Domain Names        | `god.movilab.es`                         |
| Scheme              | `http`                                   |
| Forward Hostname/IP | `gev` (nombre del contenedor, NO 127.0.0.1) |
| Forward Port        | `4173`                                   |

> ⚠️ **NPM corre en contenedor**: su `127.0.0.1` es él mismo, no el host. Por eso el
> compose conecta `gev` a tu red `proxy_network` y el forward se hace por nombre de
> contenedor. Comprueba el nombre real con `docker network inspect proxy_network`;
> si usas otro nombre de red, cámbialo en `docker-compose.yml`.
| Cache Assets        | ❌ (desactivado: la app sirve datos vivos) |
| Block Common Exploits | ✅                                     |
| Websockets Support  | ✅ (lo usa la capa de voz)               |

Pestaña **SSL**: pide el certificado *Request a new SSL Certificate* (Let's Encrypt), activa **Force SSL** y, si quieres HTTP/2, actívalo.

DNS: crea un registro **A** de `god.movilab.es` apuntando a la IP pública del servidor (y ábrelo en la lista de seguridad de Oracle si no lo tienes ya en la regla del 80/443).

### Extra recomendado en NPM (pestaña Advanced)

La app es pública; si quieres frenar abusos básicos, añade en *Advanced*:

```nginx
# Limita peticiones grandes (la app apenas las usa)
client_max_body_size 2m;
```

## 4. Claves API (opcional, después)

El panel **POWER UP** de la app se desactiva solo cuando detecta que llega por un proxy (es una protección del propio proyecto). Para añadir claves:

```bash
nano data/env/.env        # pega tus claves (CESIUM_ION_TOKEN, OPENAI_API_KEY, ...)
docker compose restart gev
```

Sin ninguna clave la app ya funciona: Esri/OSM, vuelos (OpenSky anon), satélites, terremotos, CCTV, radio, lanzamientos.

| Clave         | Qué activa                          | Coste                        |
| ------------- | ----------------------------------- | ---------------------------- |
| Cesium ion    | 3D fotorrealista + terreno          | Gratis (uso personal)        |
| OpenAI        | Control por voz + resumen HUD       | De pago (por minuto de voz)  |
| AISStream     | Barcos en vivo                      | Gratis                       |
| NASA FIRMS    | Incendios activos                   | Gratis                       |
| TomTom        | Velocidades de tráfico reales       | Gratis (cuota diaria)        |

⚠️ **Al ser público, cualquiera que llegue a god.movilab.es gasta tus claves.** El compose ya activa los rate-limits por IP del proyecto (`GEV_RATELIMIT_OPENAI_PER_MIN`, `GEV_RATELIMIT_GOOGLE_PER_MIN`), pero ponte presupuestos/alertas en OpenAI y Google Cloud. Si solo vas a ser tú, añade una allowlist de IP o *Basic Auth* en NPM.

## 5. Actualizar

```bash
git pull
docker compose up -d --build
```

## 6. Operación

```bash
docker compose ps                # estado + healthcheck
docker compose logs -f gev       # logs
docker compose down              # parar
docker compose down -v           # parar y borrar cachés (no borra data/env/.env)
```

El puerto 4173 solo está publicado en `127.0.0.1` del host y el tráfico con NPM va por la red interna de Docker, así que no hace falta abrir nada más en la lista de seguridad de Oracle: solo el 80/443 de NPM debe estar expuesto.

Para verificar la conectividad NPM → gev:

```bash
docker exec nginx-proxy-manager-app-1 curl -s -o /dev/null -w "%{http_code}\n" http://gev:4173/
# debe responder 200
```
