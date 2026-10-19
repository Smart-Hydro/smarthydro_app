# Reescritura sobre la API nativa de Yggdra — notas de contrato

Estado: WIP. Se eliminó el código legado (`lib/`, `test/`, `tool/`, vistas 3D web).
Falta escribir la app nueva. Estas notas resumen el contrato verificado contra
`yggdra_infra/api/schema/openapi.yaml` y el código Django.

## Generales
- Base: `https://api.yggdra.cl/api` (`--dart-define=YGGDRA_API_BASE`).
- `Authorization: Token <token>`; negocio exige `X-Branch-ID: <branch_id>`.
- Paginación DRF `{count,next,previous,results}`, `page_size` máx. **200**.
- Decimales pueden venir como string: parsear num o string.
- 403 sin acceso a sucursal: `{"error": "No tienes acceso a esta sucursal"}`.

## Auth
- `POST /accounts/users/login_complete/` `{email,password}` →
  `{token, user{id,username,email,first_name,last_name,full_name,type_user,is_superuser,...},
  branches[{id (BranchUser!), branch_id (usar este), branch_name, business_name, role_code, role_name}], permissions{...}}`.
- `POST /accounts/users/forgot_password/` `{email, branch_id?, login_slug?}`.
- `POST /accounts/users/logout/`; `GET|PATCH /accounts/users/my-profile/` (first_name,last_name,email,username,dni).
- `GET /branches/public-login-theme/by-host/` → `{scope, branding{app_name,logo_url,primary_color,secondary_color,login_welcome_message,login_subtitle,tagline,...}, branch_id?, organization_id?, stores?}`.

## IoT telemetry (`/iot-telemetry/`)
- `devices/` (lista): id, name, device_type, project, project_name, provider_name, is_active,
  is_online, last_reading_at, minutes_offline, variables_count, lat, lon. Filtros: project, device_type, is_online, search, ordering.
- `devices/{id}/` (detalle): + reading_frequency, address, config (DeviceConfig), compliance_config,
  variables[] (TelemetryVariable), latest_readings[] (solo 5 últimas, todas las variables), metadata.
- `devices/disconnected/` → lista plana `{id,name,minutes_offline,last_reading_at}`.
- DeviceConfig: depth, pump_position, level_position, level_offset, flow_initial, max_flow_ls, ... (`water_table = depth - nivel` si depth > 0).
- ComplianceConfig: send_dga, standard (SIN_ESTANDAR|MAYOR|MEDIO|MENOR|CAUDALES_MUY_PEQUENOS), type_dga, code_dga, flow_granted_ls, total_granted_m3, shac, region_dga, date_start_compliance, send_sma.
- `variables/`: id, device, name, variable_type (FLOW|LEVEL|TOTAL|FLOW_AVG|...), unit, is_counter, display_order, chart_color. Filtros: device, variable_type.
- `readings/`: EAV, una fila por variable y timestamp: id, device, variable, variable_name, reading_at, raw_value,
  processed_value, unit, is_error, send_dga, dga_sent_at, dga_response, dga_voucher.
  Filtros SOLO exactos: device, variable, is_error, is_online, send_dga, is_validated; `ordering=-reading_at`.
  **No hay filtro por fecha**: paginar hacia atrás hasta pasar el corte (por variable) y limitar páginas.
- `readings/stats/?device=&variable=` → count/avg/min/max: **hoy falla en el backend** (`models.Q` sin importar) → tratar como opcional.
- `events/` (lista): id, event_type, event_type_display, device_name, title, severity (INFO|WARNING|CRITICAL), created. Filtros: device, severity, event_type, created__gte/lte.
- `alert-triggers/`: id, alert_rule, alert_rule_name, device, device_name, variable_name, triggered_at,
  value_at_trigger, threshold_breached, ai_diagnosis, is_acknowledged, acknowledged_by_name, acknowledged_at.
  Filtros: device, is_acknowledged, triggered_at__gte/lte.
  `POST alert-triggers/{id}/acknowledge/ {notes?}`; `POST alert-triggers/acknowledge_bulk/ {ids:[...]}`.

## Soporte
- `GET /support/tickets/` (TicketList), `GET /support/tickets/{id}/` (TicketDetail con comments[]).
- `POST /support/tickets/` requiere `subject, description, category (uuid)`; prioridad LOW|MEDIUM|HIGH|CRITICAL.
- Categorías: `GET /support/categories/` (id uuid, name, color).
- Responder: `POST /support/comments/ {ticket, content, visibility: PUBLIC}`.

## Asistente
- Flujo preferido: `GET /ai-agents/agents/default/` → `id`; `POST /ai-agents/conversations/ {agent, title}` → `id`;
  `POST /ai-agents/conversations/{id}/chat/ {message}` → `{id, message, conversation_id, sources, tokens_used, ...}`.
- Respaldo: `GET /ai-agents/llm-models/?is_active=true` y `POST /ai-agents/llm-chat/chat/
  {message, conversation_history, provider_id, model_id}` → `{message, model, usage, provider}`.

## Push
- `POST /ai-agents/push-subscriptions/ {p256dh, auth, user_agent, is_active}`.
  Ojo: el serializer marca `endpoint` como solo lectura, así que el backend no guarda el endpoint (hay que corregirlo en Yggdra).

## Pendiente (todo el código)
- `pubspec.yaml` nuevo: flutter_riverpod 3, go_router, dio, flutter_secure_storage, shared_preferences,
  fl_chart, maplibre_gl (sin flutter_map), archive, intl, web.
- `lib/core` (entorno, tema, cliente dio + interceptores, almacenamiento, caché, router) y `lib/features/*`
  (auth, points, map, analysis, compliance, alerts, support, profile, assistant).
- Portar `dga_compliance.dart`, `flow_bands.dart`, `compliance_store.dart` y sus tests (están en `dev`).
- iOS (`flutter create --platforms=ios --org cl.smarthydro .`), permiso INTERNET en el manifest de Android,
  `web/manifest.json`, workflows con `--wasm`, README.
