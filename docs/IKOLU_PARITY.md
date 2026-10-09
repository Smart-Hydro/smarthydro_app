# Paridad funcional con Ikolu

Auditoría de solo lectura de `ui_ikolu`, contrastada con el primer corte Flutter y la API SmartHydro existente.

## Referencias revisadas

- Navegación y rutas: `ui_ikolu/src/containers/Home.js`, `HomeResponsive.js` y `AppRouter.js`.
- Autenticación y sesión actual: `ui_ikolu/src/containers/Login.js`, `src/App.js` y `src/reducers/appReducer.js`.
- Contratos consumidos: `ui_ikolu/src/api/sh/endpoints.js` y `optimizedEndpoints.js`.
- Centro de control, mapa, telemetría, DGA, análisis, alertas, soporte, documentos, reportes y perfil bajo `ui_ikolu/src/components/`.
- Ikolu publicado: `https://ikolu.smarthydro.app` entrega los hashes `main.0bafcc22.js` y `main.7b7cfafc.css`, que coinciden con `ui_ikolu/IKOLU_CLIENTES/asset-manifest.json`.
- El HTML publicado es una SPA sin contenido prerenderizado; la paridad se contrastó con el bundle publicado y el código fuente, no con una sesión autenticada de cliente.

## Inventario de capacidades de Ikolu

| Capacidad | Ejemplos de Ikolu | Estado en Flutter |
|---|---|---|
| Inicio de sesión y selección de punto | Login, perfil y selector `ListWells` | **Implementado:** login `/api/ik/login/` y puntos autorizados. |
| Centro de control | Resumen de cartera, conectividad, consumo, alertas y refresco | **Implementado parcialmente:** KPIs reales de `dashboard_stats` y lista de `points_summary`. |
| Mapa y ubicación | GEO Smart, GPS, selección de punto y estado | **Implementado:** mapa de puntos con GPS, estado, atribución OpenStreetMap y apertura del detalle del punto. |
| Telemetría de pozo/superficial | `MyWell`, `Sma`, registros, variables, configuración y carga manual según permisos | **Implementado parcialmente:** resumen, calendario 7/30 días y Replay 4D con registros reales por rango (31 días/500 registros). Falta el renderizador GLB 3D final, vistas operativas completas, edición y carga manual. |
| Análisis histórico | Smart Análisis, gráficos diarios y mensuales | **Implementado parcialmente:** gráfico de consumo diario y período de 7/30 días desde Calendar API. Falta la paridad de tablas, filtros y gráficos de variables de Ikolu. |
| Cumplimiento DGA/MEE y SMA | Registros, QR/certificados, análisis y exportación | **Implementado parcialmente:** lista de cumplimiento, filtro de activos y detalle de excedencias/mediciones cercanas al límite. Faltan vistas MEE/QR y exportaciones específicas. |
| Alertas | Listado, activas, crear/editar/eliminar y respuestas | **Implementado parcialmente:** avisos de tickets y eventos de sistema. Falta paridad con CRUD/respuestas de alertas legacy, sujeta a una ruta de cliente con alcance por usuario. |
| Soporte | Nuevo ticket, activos, historial, respuestas | **Implementado parcialmente:** listar/crear tickets, ver comentarios, responder y recibir avisos. Faltan adjuntos y algunas acciones de seguimiento de Ikolu. |
| Documentos | Listar, subir y eliminar archivos del punto | **Diferido por ahora** a petición del producto. `FileCatchmentViewSet` legado usa `IsAuthenticated` y queryset sin filtro owner/viewer; requiere endpoint cliente acotado al punto antes de integrarlo. |
| Descargas y reportes | Registros por rango y exportaciones Excel | **Implementado parcialmente:** registros por rango, tabla y CSV compartible vía punto autorizado; exportación XLSX Ikolu pendiente de endpoint seguro. |
| Perfil y preferencias | Edición de datos personales y preferencias de aviso | **Implementado parcialmente:** preferencia de email y cierre de sesión; falta editar los datos del perfil. |
| Administración/staff | Panel de sistema, colas DGA, gestión global de clientes/proyectos/puntos | **Fuera del alcance cliente.** No se replica en la app final de clientes. |
| Pantallas especiales | PTI, formularios múltiples y herramientas asociadas a cuentas concretas | **Fuera del alcance general de clientes.** Solo se reconsideran si se confirma un uso de cliente final. |
| Asistente Yggdra/OpenRouter | Consultas conversacionales sobre SmartHydro | Pendiente de integrar identidad y agente autorizado. |

La meta de paridad es **lo que usa un cliente final en Ikolu**. La disponibilidad puede depender del tipo de captación, variables, configuración DGA/SMA y flags de módulo del punto. La app respeta esos permisos; no muestra las acciones administrativas de staff.

## Límites de seguridad de la API existente

La copia de Ikolu consume algunas rutas legacy de alertas, archivos y reportes. En el backend revisado, algunos de esos ViewSets declaran `IsAuthenticated` sin filtrar el queryset por `owner_user`/`users_viewers`. Flutter no reutilizará esas rutas para clientes hasta tener endpoints seguros y pruebas negativas entre dos usuarios. El CSV actual se genera desde `/api/ik/point/{id}/records/`, que sí valida owner/viewer. El token de la app se mantiene en memoria; al recargar, el usuario vuelve a iniciar sesión.

## Notificaciones y tiempo real

Ikolu refresca el contador de alertas activas del punto seleccionado cada 60 segundos desde `HeaderNav.js`. Flutter obtiene las notificaciones de tickets y eventos de Core API, actualiza el contador cada 30 segundos mientras está en primer plano y detiene el sondeo al pasar a segundo plano. El usuario puede actualizar manualmente y marcar notificaciones de tickets como leídas.

Este sondeo entrega avisos casi en tiempo real mientras la app está abierta; no es push instantáneo en segundo plano. Yggdra tiene infraestructura Web Push, pero aún falta conectarla a los eventos SmartHydro. Android push y web push de producción requieren ese cableado backend.

## Movimiento visual

De SmartAPR se toma únicamente la inspiración de movimiento. Su CSS publicado usa un fondo radial `fondo-agua`, textura de puntos, una cinta en movimiento y una línea vertical animada de scroll. **No se copian sus colores ni su paleta.** Flutter mantiene la identidad SmartHydro y adapta el movimiento con capas fluidas, ondas, reflejos, partículas y transiciones; respeta la preferencia del sistema por reducir animaciones.

## Siguiente orden de trabajo

1. Terminar telemetría operativa: gráficos por variable, períodos intradía y edición/ingreso de registros únicamente donde Core API autorice al cliente.
2. Completar DGA/MEE, SMA, certificados, diagnósticos y exportaciones con rutas de cliente seguras.
3. Completar CRUD de alertas y adjuntos de soporte cuando exista el contrato de cliente seguro; documentos permanecen diferidos.
4. Agregar edición del perfil y probar flujos según tipo de captación y flags de módulo.
5. Agregar el panel predictivo calculado a partir de históricos medidos y validarlo retrospectivamente.
6. Conectar el agente cliente de Yggdra con identidad autenticada; mantener OpenRouter y credenciales en servidor.
7. Implementar Web Push/Android push con el backend y validar avisos en segundo plano.
8. Mantener fuera de la app cliente las funciones staff, administración y prototipos internos.

La exportación CSV comparte solamente datos de puntos autorizados. Documentos no se implementan en este corte, según lo acordado.
