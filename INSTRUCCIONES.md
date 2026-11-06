# Gymnós · app instalable

Esta carpeta es la app completa. Para instalarla en el celular primero hay que publicarla en una dirección web segura (https). Es gratis y toma unos 5 minutos.

## 1. Publicarla (una sola vez)

**Opción fácil: Netlify**
1. Descomprime el archivo `.zip` en tu computador.
2. Entra a https://app.netlify.com/drop y crea una cuenta gratuita.
3. Arrastra la carpeta `coach-pwa` a la página.
4. Netlify te da un enlace del tipo `https://nombre.netlify.app`. Puedes cambiar el nombre en la configuración del sitio.

**Alternativa: GitHub Pages**
Sube el contenido de la carpeta a un repositorio y activa Pages en *Settings › Pages*.

Para actualizar la app más adelante, sube la carpeta nueva al mismo sitio. La app avisa cuando hay una versión nueva.

## 2. Instalarla en el celular

- **Android (Chrome):** abre el enlace y toca *Instalar app* (o el menú ⋮ › *Instalar app*).
- **iPhone (Safari):** abre el enlace, toca *Compartir* › *Agregar a pantalla de inicio*.

## 3. Primer uso

- Ve a **Plan › App en tu celular** y activa el aviso de fin de descanso.
- Si ya usaste la versión dentro de Claude: allí ve a **Plan › Tus datos › Copia de seguridad (JSON)**, pasa el archivo al celular y en la app instalada usa **Restaurar una copia**.

## Qué funciona distinto en la app instalada

- **Funciona sin conexión** en el gimnasio: plan, rutina guiada, animaciones, registro, progreso y recetas.
- **Tus datos viven en el celular.** No se sincronizan con otros dispositivos: haz una copia de seguridad cada mes desde *Tus datos*.
- **Aviso de descanso:** suena y vibra cuando termina el descanso, aunque cambies de app. Si el celular suspende la app mucho tiempo, el aviso puede retrasarse.
- **Recordatorios de entrenamiento:** usa los botones de Google Calendar en *Plan*. Los recordatorios diarios desde la propia app requieren un servidor (fase siguiente).
- **Ideas de recetas con IA:** solo están en la versión dentro de Claude. Las recetas calculadas con tus ingredientes sí funcionan aquí.

## Archivos

- `index.html`: la app.
- `manifest.webmanifest`: nombre, ícono y colores para instalarla.
- `sw.js`: guarda la app en el celular para usarla sin conexión.
- `icons/`: íconos de la app.
