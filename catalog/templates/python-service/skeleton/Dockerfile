# Etapa 1: dependencias en un venv SIN pip
# Hardening pendiente: fijar la imagen base por digest (python:3.13-slim@sha256:...)
FROM python:3.13-slim AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
COPY requirements.txt .
# El venv se crea sin pip (así no arrastra sus librerías vendorizadas) y las dependencias
# se instalan con el pip de esta etapa apuntando al venv mediante --python.
RUN python -m venv --without-pip /opt/venv \
 && pip --python /opt/venv/bin/python install -r requirements.txt

# Etapa 2: imagen final mínima, sin gestor de paquetes y con usuario no-root
FROM python:3.13-slim
ARG APP_VERSION=dev

# Quitar pip de la imagen final: la app no lo usa en ejecución y trae librerías vendorizadas
# (msgpack, urllib3, setuptools) que Trivy marca con CVEs. Menos superficie de ataque.
# Ruta absoluta: aún no se ha cambiado el PATH. Si setuptools/wheel no existen, pip solo avisa.
RUN /usr/local/bin/python -m pip uninstall -y pip setuptools wheel

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    APP_VERSION=${APP_VERSION}

RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

COPY --from=builder /opt/venv /opt/venv
WORKDIR /app
COPY app/ ./app/

# UID numérico: el PodSecurity "runAsNonRoot" de Kubernetes lo necesita para verificarlo
USER 10001:10001
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
