# 1. Usa a base que você acabou de buildar com sucesso
FROM utils-r_duckdb:latest

# 2. Instala os pacotes R necessários para o pré-processamento
# O dplyr e stringr corrigem encoding e validam cd_bairro e geometry_wkt
RUN R -e "install.packages(c('dplyr','stringr','glue'), repos='https://cloud.r-project.org/')"

# 3. Define onde o trabalho acontece
WORKDIR /app

# 4. Copia os arquivos necessários
# Atenção: O build deve ser rodado da RAIZ do projeto
COPY dags/utils/utils.R .
COPY dags/base_bairros_brasil/pre_processamento/pre_processamento_bairros.R .

# 5. Execução
CMD ["Rscript", "--vanilla", "pre_processamento_bairros.R"]
