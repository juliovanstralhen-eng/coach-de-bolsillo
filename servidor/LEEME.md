# Servidor de retos de Gymnós

Los retos del gimnasio necesitan un servidor compartido: así la tabla de posiciones y las asistencias se ven desde todos los celulares. Gymnós usa **Supabase** (plan gratuito). Mientras no esté configurado, la app y el panel funcionan en **modo demostración**: todo queda guardado en el navegador del equipo donde se prueba.

## Archivos

- `retos.sql`: tablas y funciones del servidor. Se puede volver a ejecutar sin perder datos.
- `retos-net.js`: conexión de la app y del panel con el servidor. Va incluido dentro de `index.html` y de `gimnasio.html`.
- `../gimnasio.html`: panel del gimnasio. Ahí se crean los retos, se abre la pantalla de recepción con el QR, se revisan las asistencias y se anulan las dudosas.

## Cómo evita la trampa

1. La recepción muestra un QR y un número de 6 dígitos que cambian cada 30 segundos. Están firmados con un secreto del gimnasio que nunca sale del servidor ni del panel.
2. El servidor solo acepta el código vigente o el anterior (máximo 60 segundos). Una foto del QR enviada por WhatsApp deja de servir en menos de un minuto.
3. Cuenta una asistencia por persona y por día. Permite como máximo 5 intentos fallidos cada 10 minutos.
4. Opcional, por reto: exigir que el celular esté a menos de 100 a 500 metros del gimnasio.
5. El gimnasio ve cada asistencia con su hora y su distancia, y puede anular las dudosas comparándolas con su control de acceso.

## Puesta en marcha (una sola vez)

1. Crea una cuenta en supabase.com y un proyecto nuevo. Escoge la región más cercana; para Colombia, São Paulo.
2. En **Authentication → Providers** (o **Sign In / Providers**), activa **Allow anonymous sign-ins**. Cada celular recibe una sesión sin correo ni contraseña.
3. En **Authentication → Rate limits**, sube el límite de inicios de sesión anónimos. Viene en 30 por hora por IP, y en el wifi de un gimnasio muchos celulares comparten la misma IP.
4. En **SQL Editor → New query**, pega todo `retos.sql` y ejecútalo.
5. Crea una licencia por cada gimnasio cliente. El cupo es el máximo de afiliados en sus retos:

   ```sql
   insert into public.licencias (codigo, cupo, nota) values ('TUGYM-2026', 300, 'Tu Gimnasio · plan 300');
   ```

6. En **Project Settings → API**, copia la **Project URL** y la **anon public key**. Ponlas en `GYMNOS_SERVIDOR` dentro de `retos-net.js` y vuelve a construir la app. Esas dos son públicas por diseño. La clave **service_role** nunca va en la app.

## Uso en el gimnasio

1. El dueño abre `gimnasio.html` y activa el gimnasio con su licencia. Guarda la clave del panel que aparece.
2. Crea un reto, por ejemplo «12 asistencias en diciembre» con premio «una semana gratis». Comparte el código o el cartel con QR.
3. En la recepción deja un celular, una tableta o un televisor con **Abrir pantalla de recepción**.
4. Cada afiliado entra a Gymnós › Hoy › Retos, se une con el código y, al llegar, toca **Registrar asistencia** y escanea.

Los premios se entregan por cumplir la meta, no por sorteo. Un sorteo con premios necesita autorización de Coljuegos. Los concursos por mérito pueden necesitar permiso de la alcaldía. Revisa las bases con un asesor legal.
