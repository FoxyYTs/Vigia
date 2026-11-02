// Consentimiento para Google Analytics (Ley 1581 de 2012). Analytics no se
// carga hasta que la persona acepta; la decisión se guarda en este navegador.
// Va en un archivo y no inline para que la CSP no necesite 'unsafe-inline'.
(function () {
  var ID = 'G-CBJ3ENMN4D';
  var CLAVE = 'vigia_consentimiento_analitica';

  function cargarAnalitica() {
    var s = document.createElement('script');
    s.async = true;
    s.src = 'https://www.googletagmanager.com/gtag/js?id=' + ID;
    document.head.appendChild(s);
    window.dataLayer = window.dataLayer || [];
    window.gtag = function () { window.dataLayer.push(arguments); };
    window.gtag('js', new Date());
    window.gtag('config', ID, { anonymize_ip: true });
  }

  function decidir(valor, aviso) {
    try { localStorage.setItem(CLAVE, valor); } catch (e) { /* sin almacenamiento: se pregunta de nuevo */ }
    aviso.remove();
    if (valor === 'si') cargarAnalitica();
  }

  function boton(texto, primario) {
    var b = document.createElement('button');
    b.type = 'button';
    b.textContent = texto;
    var s = b.style;
    s.font = '600 14px system-ui, sans-serif';
    s.padding = '10px 16px';
    s.minHeight = '44px';
    s.borderRadius = '8px';
    s.cursor = 'pointer';
    s.border = '1px solid #1B5E3A';
    s.background = primario ? '#1B5E3A' : '#FFFFFF';
    s.color = primario ? '#FFFFFF' : '#1B5E3A';
    return b;
  }

  var guardado = null;
  try { guardado = localStorage.getItem(CLAVE); } catch (e) { /* ignorar */ }
  if (guardado === 'si') { cargarAnalitica(); return; }
  if (guardado === 'no') return;

  document.addEventListener('DOMContentLoaded', function () {
    var aviso = document.createElement('div');
    aviso.setAttribute('role', 'dialog');
    aviso.setAttribute('aria-label', 'Consentimiento de analítica');
    var s = aviso.style;
    s.position = 'fixed'; s.left = '16px'; s.right = '16px'; s.bottom = '16px'; s.zIndex = '2147483647';
    s.maxWidth = '640px'; s.margin = '0 auto'; s.padding = '16px'; s.borderRadius = '12px';
    s.background = '#FFFFFF'; s.color = '#1A1F1C'; s.boxShadow = '0 4px 24px rgba(0,0,0,.25)';
    s.font = '14px/1.5 system-ui, sans-serif';

    var texto = document.createElement('p');
    texto.style.margin = '0 0 12px';
    texto.append('Vigía usa Google Analytics para saber cuántas personas usan el mapa. ' +
      'Solo se activa si lo aceptas. ');
    var enlace = document.createElement('a');
    enlace.href = 'privacidad.html';
    enlace.textContent = 'Política de tratamiento de datos';
    enlace.style.color = '#1B5E3A';
    texto.append(enlace, '.');

    var acciones = document.createElement('div');
    acciones.style.display = 'flex'; acciones.style.gap = '8px'; acciones.style.justifyContent = 'flex-end';
    var rechazar = boton('Rechazar', false);
    var aceptar = boton('Aceptar', true);
    rechazar.addEventListener('click', function () { decidir('no', aviso); });
    aceptar.addEventListener('click', function () { decidir('si', aviso); });
    acciones.append(rechazar, aceptar);

    aviso.append(texto, acciones);
    document.body.appendChild(aviso);
  });
})();
