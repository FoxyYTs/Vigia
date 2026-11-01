"""
ClienteUngrd — incendios forestales del consolidado de emergencias de la
UNGRD en datos.gov.co (Socrata). Ver Vigia-Credenciales-APIs § UNGRD y
Vigia-Plan-I1c-Historicos (vault de Obsidian).
"""

import logging
from datetime import date

import requests
from django.conf import settings

from apps.historico.models import IncendioReportado
from apps.satelital.clientes import ClienteDatosExternos
from apps.usuarios.models import Municipio

logger = logging.getLogger(__name__)

# (dataset, campo con el código DIVIPOLA). Los demás datasets de la UNGRD están
# abandonados, duplicados o ya no son públicos (verificado el 09-sep-2026).
DATASETS = (
    ("wwkg-r6te", "divipola"),  # 2019–2022, "INCENDIO DE COBERTURA VEGETAL"
    ("rgre-6ak4", "codificaci_n_segun_divipola"),  # 2023–2024, "INCENDIO FORESTAL"
)
# Solo incendios de vegetación: se excluyen ESTRUCTURAL, VEHICULAR y el genérico INCENDIO.
EVENTOS = ("INCENDIO FORESTAL", "INCENDIO DE COBERTURA VEGETAL")


def parsear_fila_ungrd(fila: dict, campo_divipola: str) -> dict:
    """Normaliza una fila de Socrata. Función pura. `wwkg-r6te` trae el
    código sin el cero inicial ("5044" = 05044, Anzá)."""
    codigo = (fila.get(campo_divipola) or "").strip()
    hectareas = (fila.get("hectareas") or "").strip().replace(",", ".")
    return {
        "codigo": fila[":id"],
        "fecha": date.fromisoformat(fila["fecha"][:10]),
        "evento": fila["evento"].strip(),
        "codigo_dane": codigo.zfill(5) if codigo.isdigit() and codigo != "0" else None,
        "municipio_reportado": f"{fila.get('municipio', '').strip()}, {fila.get('departamento', '').strip()}",
        "hectareas": float(hectareas) if hectareas else None,
    }


class ClienteUngrd(ClienteDatosExternos):
    URL = "https://www.datos.gov.co/resource/{dataset}.json"
    TAMANO_PAGINA = 50000

    def __init__(self, session=None):
        self.session = session or requests.Session()

    def _descargar(self, dataset: str, campo: str) -> list[dict]:
        filas, offset = [], 0
        eventos = ", ".join(f"'{e}'" for e in EVENTOS)
        while True:
            r = self.session.get(
                self.URL.format(dataset=dataset),
                params={
                    "$select": f":id, fecha, departamento, municipio, evento, {campo}, hectareas",
                    "$where": f"evento in ({eventos})",
                    "$order": ":id",  # orden estable para paginar
                    "$limit": self.TAMANO_PAGINA,
                    "$offset": offset,
                },
                headers={"X-App-Token": settings.UNGRD_SOCRATA_APP_TOKEN} if settings.UNGRD_SOCRATA_APP_TOKEN else {},
                timeout=120,
            )
            r.raise_for_status()
            pagina = r.json()
            filas.extend(pagina)
            if len(pagina) < self.TAMANO_PAGINA:
                return filas
            offset += self.TAMANO_PAGINA

    def sincronizar(self) -> int:
        """Descarga los dos datasets y guarda los incendios nuevos. Retorna
        cuántos se crearon. Los que no tienen un municipio válido se guardan
        igual, sin municipio, y se cuentan en el log."""
        municipios = dict(Municipio.objects.exclude(codigo_dane=None).values_list("codigo_dane", "id"))
        antes = IncendioReportado.objects.count()
        for dataset, campo in DATASETS:
            datos = [parsear_fila_ungrd(f, campo) for f in self._descargar(dataset, campo)]
            sin_municipio = [d for d in datos if d["codigo_dane"] not in municipios]
            if sin_municipio:
                logger.warning(
                    "ClienteUngrd %s: %s de %s incendios sin municipio válido (p. ej. %s)",
                    dataset, len(sin_municipio), len(datos), sin_municipio[0]["municipio_reportado"],
                )
            IncendioReportado.objects.bulk_create(
                [
                    IncendioReportado(
                        dataset=dataset,
                        codigo=d["codigo"],
                        fecha=d["fecha"],
                        evento=d["evento"],
                        municipio_id=municipios.get(d["codigo_dane"]),
                        municipio_reportado=d["municipio_reportado"],
                        hectareas=d["hectareas"],
                    )
                    for d in datos
                ],
                batch_size=5000,
                ignore_conflicts=True,
            )
        return IncendioReportado.objects.count() - antes
