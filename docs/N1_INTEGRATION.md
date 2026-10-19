# Integración SmartHydro N1 (Flutter)

Contrato fuente: [`smarthydro-n1/docs/INTEGRATION_FLUTTER.md`](https://github.com/felipebarraza6/smarthydro-n1/blob/main/docs/INTEGRATION_FLUTTER.md) (implementación viva: `AppApi.gs`).

## Auth (opción B)

La app **no** tiene BFF. Cada `doPost` usa el token SmartHydro del usuario logueado:

```http
POST <N1_WEB_APP_URL>
Authorization: Token <access_token>
Content-Type: application/json

{ "op": "ask", "requester": "user@correo", "text": "…" }
```

`requester` / `email` van en el body (la API N1 los exige en opción B).

## Ops usadas

| op | Uso en la app |
|----|----------------|
| `ask` | Chat principal |
| `report` | Pedido de Excel / reporte; links en el texto |
| `list_files` | Bitácora de archivos; chips para abrir `url` |
| `create_ticket` | Formulario; se muestra solo `ticket_id` |

La app **no** envía acuse ni asignación: eso lo hace `core_api_sh` al crear el ticket.

## Jobs async (⏳)

Si la respuesta trae `pending` / `async` o el texto empieza con `⏳`, la UI marca el mensaje en curso y reconsulta (timer + botón). Tras un `report` pendiente también puede refrescar `list_files` por si ya hay link.

## Config

La URL `/exec` de la Web App es **pública** (no es un secreto). Por defecto la app usa el despliegue prod:

`N1Config.defaultProdWebAppUrl` → verificado con `GET ?op=health` → `ok` / `version: 2026-10-12-flutter-app`.

Override opcional:

```bash
flutter run --dart-define=N1_WEB_APP_URL=https://script.google.com/macros/s/<OTRO_DEPLOYMENT>/exec
flutter build web --dart-define=N1_WEB_APP_URL=…
```

## Apps Script redirects

`doPost` responde `302` a `script.googleusercontent.com/macros/echo`. En nativo el cliente hace POST sin seguir redirects y luego **GET** del `Location`. Re-POSTear el echo suele devolver HTML (405 sin CORS).

En web (GitHub Pages) el POST es una petición CORS *simple*: `text/plain`, token en el JSON, sin `Authorization` y sin `connectTimeout` (Dio registraría `xhr.upload` y el navegador mandaría OPTIONS, que Apps Script no responde con CORS). El navegador sigue el 302 como GET al echo.

Smoke (health + capabilities GET + ping unauthorized):

```bash
dart run tool/n1_smoke.dart
```
