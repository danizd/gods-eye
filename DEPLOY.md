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

| Campo               | Valor                                       |
| ------------------- | ------------------------------------------- |
| Domain Names        | `god.movilab.es`                            |
| Scheme              | `http`                                      |
| Forward Hostname/IP | `gev` (nombre del contenedor, NO 127.0.0.1) |
| Forward Port        | `4173`                                      |

> ⚠️ **NPM corre en contenedor**: su `127.0.0.1` es él mismo, no el host. Por eso el
> compose conecta `gev` a tu red `proxy_network` y el forward se hace por nombre de
> contenedor. Comprueba el nombre real con `docker network inspect proxy_network`;
> si usas otro nombre de red, cámbialo en `docker-compose.yml`.
> | Cache Assets | ❌ (desactivado: la app sirve datos vivos) |
> | Block Common Exploits | ✅ |
> | Websockets Support | ✅ (lo usa la capa de voz) |

Pestaña **SSL**: pide el certificado _Request a new SSL Certificate_ (Let's Encrypt), activa **Force SSL** y, si quieres HTTP/2, actívalo.

> ⚠️ **Errores 504 en `node_modules/.vite/deps/cesium.js` (mapa que no carga)**:
> el bundle dev de Cesium pesa ~10 MB y tarda un rato en servirse la primera vez.
> La imagen ya lo pre-compila en el build, pero si te aparece igualmente:
>
> 1. Espera ~1 min y recarga con Ctrl+Shift+R.
> 2. Sube los timeouts de proxy de NPM (_Custom Locations_ o en el host de NPM:
>    `proxy_read_timeout 300s; proxy_send_timeout 300s;`).
> 3. Mira los logs del contenedor durante la carga: `docker compose logs -f gev`.
>    Si ves `new dependencies optimized... reloading`, recarga el navegador: es la
>    optimización en caliente de Vite y solo pasa la primera vez.
>
> **Si en los logs ves `EACCES: permission denied, mkdir '/app/node_modules/.vite/deps_temp_...'`**
> es que el contenedor lleva un volumen antiguo montado sobre la caché de Vite
> (versiones previas de este compose lo montaban y Docker lo creaba como root).
> Recrea con la versión actual del repo:
>
> ```bash
> git pull
> docker compose down -v          # elimina también el volumen viejo gev_vite_cache
> docker compose up -d --build
> # comprobación: debe listar contenido y ser de node:node
> docker compose exec gev sh -c 'ls -ld /app/node_modules/.vite/deps | head -3'
> ```

DNS: crea un registro **A** de `god.movilab.es` apuntando a la IP pública del servidor (y ábrelo en la lista de seguridad de Oracle si no lo tienes ya en la regla del 80/443).

### Extra recomendado en NPM (pestaña Advanced)

La app es pública; si quieres frenar abusos básicos, añade en _Advanced_:

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

| Clave      | Qué activa                    | Coste                       |
| ---------- | ----------------------------- | --------------------------- |
| Cesium ion | 3D fotorrealista + terreno    | Gratis (uso personal)       |
| OpenAI     | Control por voz + resumen HUD | De pago (por minuto de voz) |
| AISStream  | Barcos en vivo                | Gratis                      |
| NASA FIRMS | Incendios activos             | Gratis                      |
| TomTom     | Velocidades de tráfico reales | Gratis (cuota diaria)       |

⚠️ **Al ser público, cualquiera que llegue a god.movilab.es gasta tus claves.** El compose ya activa los rate-limits por IP del proyecto (`GEV_RATELIMIT_OPENAI_PER_MIN`, `GEV_RATELIMIT_GOOGLE_PER_MIN`), pero ponte presupuestos/alertas en OpenAI y Google Cloud. Si solo vas a ser tú, añade una allowlist de IP o _Basic Auth_ en NPM.

## 4b. Troubleshooting: capa de tráfico en 502 (TomTom/Overpass)

La consola del navegador muestra `502` en `/api/tomtom/...` o `/api/overpass` cuando
los **proxies del contenedor** no consiguen respuesta válida de sus upstreams — no
significa que tu clave TomTom sea inválida (eso sería `403` aguas arriba) ni que el
presupuesto diario se agotó (eso es un `429`).

Diagnóstico rápido desde el servidor:

```bash
# ¿El proxy tiene la clave y presupuesto?
curl -s http://127.0.0.1:4173/api/tomtom/status

# ¿El upstream TomTom responde desde el contenedor? (200 = OK; 403 = clave sin
# el producto "Traffic Flow" activado en developer.tomtom.com)
docker compose exec gev sh -c 'curl -s -o /dev/null -w "%{http_code}\n" \
  "https://api.tomtom.com/traffic/map/4/tile/flow/relative/12/1950/1506.pbf?key=$TOMTOM_API_KEY"'

# ¿Qué mirrors de Overpass alcanza este servidor?
for h in overpass-api.de overpass.kumi.systems lz4.overpass-api.de overpass.private.coffee; do
  curl -4 -sS -o /dev/null -w "$h: %{http_code}\n" --max-time 8 "https://$h/api/status" || echo "$h: FALLO"; done

# El error real, tal y como el contenedor lo registra:
docker compose logs --tail=200 gev | grep -E "tomtom-proxy|Overpass Proxy"
```

**Overpass bloquea la IP del servidor (fallo instantáneo `000`/"Couldn't connect",
típico de Oracle/AWS/GCP):** los tres mirrors clásicos corren en Hetzner y rechazan
con TCP-RST a IPs de datacenter. Si solo queda `overpass.private.coffee` (o quieres
saltarte los que no responden), lista los mirrors vivos en `data/env/.env` y reinicia:

```bash
# data/env/.env — hosts sueltos o URLs completas de /api/interpreter, separados por comas
OVERPASS_MIRRORS=overpass.private.coffee,overpass.kumi.systems

docker compose restart gev
```

Sin la variable, el proxy usa sus cuatro mirrors por defecto y rota entre ellos.

**Si TomTom también da 502 de forma persistente:** comprueba la conectividad general
del contenedor (`docker compose exec gev sh -c 'curl -s -o /dev/null -w "%{http_code}\n" https://example.com'`)
y revisa las reglas de **egress** de la VCN de Oracle; si el host navega pero el
contenedor no, sospecha de Docker/iptables en el host.

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
docker compose down -v           # parar y borrar volúmenes anónimos antiguos (no toca data/env/.env)
```

El puerto 4173 solo está publicado en `127.0.0.1` del host y el tráfico con NPM va por la red interna de Docker, así que no hace falta abrir nada más en la lista de seguridad de Oracle: solo el 80/443 de NPM debe estar expuesto.

Para verificar la conectividad NPM → gev:

```bash
docker exec nginx-proxy-manager-app-1 curl -s -o /dev/null -w "%{http_code}\n" http://gev:4173/
# debe responder 200
```
