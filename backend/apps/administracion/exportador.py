"""
ExportadorDatos (UC8, bloque "Gestionar Informes") — ver Vigia-UML-Clases.
Genera los informes al vuelo, sin persistir nada:

- CSV: el detalle de un conjunto (focos, alertas o reportes).
- Excel: una hoja de resumen y una hoja por conjunto.
- PDF: el informe de apoyo a la decisión (resumen y tablas, sin detalle:
  un año de focos son ~100 mil filas).
"""

import csv
import io
from datetime import date

from django.db.models import Count, F, FloatField, Func, Subquery
from django.utils import timezone
from openpyxl import Workbook
from openpyxl.cell.cell import ILLEGAL_CHARACTERS_RE
from reportlab.lib import colors
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle

from apps.administracion import estadisticas
from apps.alertas.models import Alerta
from apps.satelital.models import FocoIncendio
from apps.usuarios.models import Municipio

CONJUNTOS = ("focos", "alertas", "reportes")

# Etiquetas legibles de los modelos (mismo texto que el admin de Django).
TIPOS_ALERTA = dict(Alerta.TipoDisparador.choices)
FUENTES = dict(FocoIncendio.Fuente.choices)


def _texto_seguro(valor):
    """La descripción de un reporte la escribe el ciudadano: se quitan los
    caracteres de control (openpyxl los rechaza y el Excel entero fallaba) y
    se neutraliza la inyección de fórmulas si empieza por "=", "+", etc."""
    if not isinstance(valor, str):
        return valor
    valor = ILLEGAL_CHARACTERS_RE.sub("", valor)
    return "'" + valor if valor[:1] in ("=", "+", "-", "@", "\t", "\r") else valor


def _coordenada(funcion):
    """ST_X/ST_Y sobre el `punto` (geometry) que anota `estadisticas.consultas`."""
    return Func(F("punto"), function=funcion, output_field=FloatField())


def _miles(valor):
    """89844 → "89.844" (separador colombiano); el texto queda igual."""
    return f"{valor:,}".replace(",", ".") if isinstance(valor, int) else valor


def _hora_local(d):
    return timezone.localtime(d).strftime("%Y-%m-%d %H:%M") if d else ""


class ExportadorDatos:
    def __init__(self, desde: date, hasta: date, municipios=None):
        self.desde, self.hasta, self.municipios = desde, hasta, municipios
        self._focos, self._alertas, self._reportes = estadisticas.consultas(desde, hasta, municipios)

    # ------------------------------------------------------------ detalle --

    def filas(self, conjunto: str):
        """(encabezados, iterador de filas) del conjunto."""
        return getattr(self, f"_filas_{conjunto}")()

    def _filas_focos(self):
        # values_list y un solo subquery espacial (el id del municipio): con
        # objetos y dos subqueries, un año de focos tardaba 11 s en vez de 3.
        nombres = {m.id: (m.nombre, m.departamento) for m in Municipio.objects.only("nombre", "departamento")}
        qs = self._focos.annotate(
            lat=_coordenada("ST_Y"),
            lon=_coordenada("ST_X"),
            municipio_id=Subquery(estadisticas.municipio_del_punto().values("id")[:1]),
        ).order_by("fecha_hora", "id").values_list(
            "fecha_hora", "fuente", "satelite", "lat", "lon", "confianza", "brillo_frp", "municipio_id"
        )
        encabezados = ["fecha_hora", "fuente", "satelite", "latitud", "longitud", "confianza", "brillo_frp",
                       "municipio", "departamento"]
        filas = (
            [_hora_local(fecha), FUENTES.get(fuente, fuente), satelite, lat, lon, confianza, frp,
             *nombres.get(municipio_id, ("", ""))]
            for fecha, fuente, satelite, lat, lon, confianza, frp, municipio_id in qs.iterator(chunk_size=5000)
        )
        return encabezados, filas

    def _filas_alertas(self):
        # Sin el polígono del municipio: solo se leen el nombre y el departamento.
        qs = (
            self._alertas.select_related("municipio").defer("municipio__geom")
            .annotate(reportes_n=Count("reportes")).order_by("fecha_creacion")
        )
        encabezados = ["id", "fecha_creacion", "disparador", "latitud", "longitud", "municipio", "departamento",
                       "foco_id", "reportes"]
        filas = (
            [a.id, _hora_local(a.fecha_creacion), TIPOS_ALERTA.get(a.tipo_disparador, a.tipo_disparador),
             a.ubicacion.y, a.ubicacion.x, a.municipio.nombre if a.municipio else "",
             a.municipio.departamento if a.municipio else "", a.foco_id, a.reportes_n]
            for a in qs
        )
        return encabezados, filas

    def _filas_reportes(self):
        # Sin el usuario que reportó: el informe circula fuera de Vigía y no
        # necesita datos personales (minimización, Ley 1581).
        qs = self._reportes.order_by("fecha_creacion")
        encabezados = ["id", "fecha_creacion", "estado", "latitud_incendio", "longitud_incendio",
                       "fecha_validacion", "descripcion"]
        filas = (
            [r.id, _hora_local(r.fecha_creacion), r.get_estado_display(), r.ubicacion_incendio.y,
             r.ubicacion_incendio.x, _hora_local(r.fecha_validacion), r.descripcion]
            for r in qs
        )
        return encabezados, filas

    # ---------------------------------------------------------- formatos --

    def exportar_csv(self, conjunto: str) -> bytes:
        encabezados, filas = self.filas(conjunto)
        salida = io.StringIO()
        escritor = csv.writer(salida)
        escritor.writerow(encabezados)
        for fila in filas:
            escritor.writerow([_texto_seguro(v) for v in fila])
        # BOM para que Excel abra las tildes bien al hacer doble clic.
        return salida.getvalue().encode("utf-8-sig")

    def exportar_excel(self) -> bytes:
        libro = Workbook(write_only=True)
        resumen = libro.create_sheet("Resumen")
        for fila in self._tablas_resumen(estadisticas.calcular(self.desde, self.hasta, self.municipios)):
            resumen.append(fila)
        for conjunto in CONJUNTOS:
            hoja = libro.create_sheet(conjunto.capitalize())
            encabezados, filas = self.filas(conjunto)
            hoja.append(encabezados)
            for fila in filas:
                hoja.append([_texto_seguro(v) for v in fila])
        salida = io.BytesIO()
        libro.save(salida)
        return salida.getvalue()

    def exportar_pdf(self) -> bytes:
        datos = estadisticas.calcular(self.desde, self.hasta, self.municipios)
        estilos = getSampleStyleSheet()
        salida = io.BytesIO()
        doc = SimpleDocTemplate(
            salida, pagesize=letter, title="Informe Vigía", author="Vigía",
            leftMargin=2 * cm, rightMargin=2 * cm, topMargin=2 * cm, bottomMargin=2 * cm,
        )
        partes = [
            Paragraph("Vigía · Informe de incidentes", estilos["Title"]),
            Paragraph(self._subtitulo(datos), estilos["Normal"]),
            Spacer(1, 0.4 * cm),
            Paragraph(
                "Las detecciones son puntos de calor vistos por satélite: varios satélites pueden ver el mismo "
                "incendio, así que no equivalen a incendios distintos.",
                estilos["Italic"],
            ),
        ]
        for titulo, filas in self._secciones(datos):
            partes += [Spacer(1, 0.5 * cm), Paragraph(titulo, estilos["Heading2"])]
            if len(filas) == 1:
                partes.append(Paragraph("Sin datos en el periodo.", estilos["Normal"]))
                continue
            filas = [[_miles(v) for v in fila] for fila in filas]
            tabla = Table(filas, colWidths=[11 * cm, 4 * cm], repeatRows=1)
            tabla.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#1B5E3A")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("ALIGN", (1, 0), (1, -1), "RIGHT"),
                ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#D5DBD3")),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F4F6F3")]),
            ]))
            partes.append(tabla)
        doc.build(partes)
        return salida.getvalue()

    # ----------------------------------------------------------- resumen --

    def _subtitulo(self, datos):
        alcance = "todo el país" if datos["nacional"] else "jurisdicción de la entidad"
        return (
            f"Del {self.desde:%d/%m/%Y} al {self.hasta:%d/%m/%Y} · {alcance} · "
            f"generado el {timezone.localtime():%d/%m/%Y %H:%M}"
        )

    def _secciones(self, datos):
        def tabla(encabezado, filas, nombre=lambda c: c):
            return [[encabezado, "Cantidad"]] + [[nombre(f["clave"]), f["cantidad"]] for f in filas]

        focos, alertas, reportes = datos["focos"], datos["alertas"], datos["reportes"]
        return [
            ("Totales", [["Indicador", "Cantidad"], ["Detecciones satelitales", focos["total"]],
                         ["Alertas", alertas["total"]], ["Reportes ciudadanos", reportes["total"]]]),
            ("Detecciones por departamento", tabla(
                "Departamento", focos["por_departamento"], lambda c: c or "Fuera de los municipios cargados")),
            ("Detecciones por fuente", tabla("Fuente", focos["por_fuente"], lambda c: FUENTES.get(c, c))),
            ("Alertas por disparador", tabla("Disparador", alertas["por_tipo"], lambda c: TIPOS_ALERTA.get(c, c))),
            ("Alertas por departamento", tabla(
                "Departamento", alertas["por_departamento"], lambda c: c or "Sin municipio")),
            ("Reportes por estado", tabla("Estado", reportes["por_estado"], lambda c: c.capitalize())),
        ]

    def _tablas_resumen(self, datos):
        yield ["Vigía · Informe de incidentes"]
        yield [self._subtitulo(datos)]
        for titulo, filas in self._secciones(datos):
            yield []
            yield [titulo]
            yield from filas
