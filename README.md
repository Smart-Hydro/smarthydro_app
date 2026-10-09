<div align="center">

# SmartHydro App

### Gestión inteligente de aguas subterráneas

**Monitoreo avanzado · Cumplimiento normativo · Tiempo real**

App Flutter multiplataforma (Android + Web/PWA) para operación hídrica, telemetría de captaciones y cumplimiento DGA/SMA.

[![Flutter](https://img.shields.io/badge/Flutter-3.8+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.8+-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Web-0B171B)](#ejecutar)
[![SmartHydro](https://img.shields.io/badge/SmartHydro-smarthydro.cl-66E0C2)](https://smarthydro.cl)

[Sitio web](https://smarthydro.cl) · [Core API](https://github.com/felipebarraza6/core_api_sh) · [Paridad Ikolu](docs/IKOLU_PARITY.md)

</div>

---

## Visión

SmartHydro acerca la plataforma de monitoreo a móviles y PWA: datos de pozos y captaciones, alertas operativas y reportes de cumplimiento, con la misma identidad acuática de [smarthydro.cl](https://smarthydro.cl) — océano oscuro, acentos menta y movimiento líquido.

| | |
|---|---|
| **Sensores + telemetría** | Lecturas autorizadas por punto, KPIs de cartera y estado de conectividad |
| **Monitoreo 24/7** | Dashboard en vivo, GEO Smart y sondeo en primer plano cada 30 s |
| **Cumplimiento DGA / MEE** | Bandas de caudal, excedencias y vistas orientadas a normativa 1.238 |

---

## Módulos

```text
┌─────────────────────────────────────────────────────────────┐
│  Login Core API  →  Sesión  →  Dashboard de cartera          │
├─────────────┬─────────────┬─────────────┬───────────────────┤
│  GEO Smart  │  Análisis   │ Cumplimiento│  Reportes CSV     │
│  (mapa)     │  7 / 30 d   │  DGA / SMA  │  + Replay 4D      │
├─────────────┴─────────────┴─────────────┴───────────────────┤
│  Soporte (tickets)  ·  Perfil  ·  Notificaciones operativas │
└─────────────────────────────────────────────────────────────┘
```

| Módulo | Qué entrega hoy |
|--------|-----------------|
| **Auth** | Login real contra Core API y puntos autorizados (owner/viewer) |
| **Dashboard** | KPIs de cartera, red de puntos y escena acuática 2.5D |
| **GEO Smart** | Mapa de captaciones con GPS y estado |
| **Análisis** | Consumo diario y ventanas 7/30 días |
| **Cumplimiento** | Activos, bandas de flujo y mediciones cerca del límite |
| **Reportes** | Registros por rango y exportación CSV compartible |
| **Replay 4D** | Reproducción histórica desde registros reales |
| **Soporte** | Tickets, comentarios y avisos |
| **Perfil** | Preferencias de sesión y cierre |

> Documentos de punto quedan fuera por ahora (endpoint cliente acotado pendiente). Panel predictivo, GLB 3D, agente Yggdra y push en segundo plano están en roadmap.

---

## Stack

- **Flutter / Dart** — Android + Web/PWA
- **Riverpod** — estado y sesión
- **Dio** — cliente HTTP hacia Core API (`/api/ik/...`)
- **flutter_map** — GEO Smart
- **fl_chart** — series de análisis
- **share_plus** — compartir CSV

Paleta de producto (alineada a la app):

| Token | Hex | Uso |
|-------|-----|-----|
| Ocean | `#0B171B` | Fondo |
| Surface | `#12252A` | Tarjetas / paneles |
| Mint | `#66E0C2` | Acento primario |
| Fog | `#E8F2F1` | Texto |

---

## Requisitos

- Flutter SDK estable con soporte Android y web
- Android Studio o Android SDK para builds Android
- Acceso a Core API (CORS local permite `http://localhost:3001` para web)

---

## Ejecutar

```bash
flutter pub get

# Web / PWA (Brave u otro navegador)
flutter run -d web-server --web-hostname localhost --web-port 3001
# → http://localhost:3001

# Android
flutter emulators --launch medium_phone
flutter run -d emulator-5554
```

---

## Validar

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build appbundle
```

---

## Roadmap

1. Completar paridad de cliente con Ikolu (telemetría operativa, DGA/SMA, alertas, soporte)
2. Visor GLB 3D y reproducción con registros exactos
3. Agente Yggdra con identidad autenticada entre APIs
4. Pronóstico determinístico validado contra históricos
5. Push web/Android desde backend y export de Replay 4D a video

Detalle de paridad: [`docs/IKOLU_PARITY.md`](docs/IKOLU_PARITY.md)

---

<div align="center">

**SmartHydro** — startup de innovación socio-ambiental  
Monitoreo · Cumplimiento · Agua sostenible

[smarthydro.cl](https://smarthydro.cl)

</div>
