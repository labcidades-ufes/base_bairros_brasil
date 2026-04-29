# 1. Usa a base que você acabou de buildar com sucesso
FROM utils-r_duckdb:latest

# 2. Instala dependências de sistema necessárias para o pacote sf (leitura de shapefiles)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libudunits2-dev libgdal-dev libgeos-dev libproj-dev libsqlite3-dev \
        gdal-bin libgeotiff-dev libprotobuf-dev protobuf-compiler libjq-dev \
        build-essential gfortran r-cran-sf && \
    rm -rf /var/lib/apt/lists/*

# 3. Instala os pacotes R necessários para a coleta
# O httr2 detecta o Censo mais recente; sf lê os shapefiles de bairros por UF
RUN R -e "install.packages(c('httr2','sf','dplyr','readr','glue','stringi'), repos='https://cloud.r-project.org/')"

# 4. Define onde o trabalho acontece
WORKDIR /app

# 5. Copia os arquivos necessários
# Atenção: O build deve ser rodado da RAIZ do projeto
COPY dags/utils/utils.R .
COPY dags/base_bairros_brasil/coleta/coleta_bairros.R .

# 6. Execução
CMD ["Rscript", "coleta_bairros.R"]
