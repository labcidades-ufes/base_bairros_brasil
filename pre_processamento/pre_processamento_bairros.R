#!/usr/bin/env Rscript
# ==============================================================================
# PRÉ-PROCESSAMENTO — BASE BAIRROS (Silver)
# Lê bronze, corrige encoding latin1→UTF-8, valida cd_bairro e geometry_wkt.
# Entrada:  bronze/base_bairros/raw_bairros_YYYYMMDD.parquet
# Saída:    silver/base_bairros/silver_bairros_YYYYMMDD.parquet
# ==============================================================================
library(dplyr)
library(stringr)
library(glue)
source("utils.R")
Sys.setlocale("LC_ALL", "C.UTF-8")

# ------------------------------------------------------------------------------
# 1. LEITURA DO BRONZE
# ------------------------------------------------------------------------------
read_from_minio_duckdb <- function() {
  cat("[PRE_PROCESSAMENTO] Lendo bronze...\n")
  tryCatch({
    arquivos <- list_parquet_files_in_minio("bronze/base_bairros/")
    if (length(arquivos) == 0) stop("Nenhum arquivo bronze encontrado.")
    caminho <- sub(sprintf("^s3://%s/", Sys.getenv("MINIO_BUCKET", "airflow")), "",
                   sort(arquivos, decreasing = TRUE)[1])
    cat(glue("[PRE_PROCESSAMENTO] Lendo: {caminho}\n"))
    read_parquet_from_minio(caminho)
  }, error = function(e) {
    cat("[PRE_PROCESSAMENTO] Erro ao ler bronze:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

# ------------------------------------------------------------------------------
# 2. PRÉ-PROCESSAMENTO + VALIDAÇÕES
# ------------------------------------------------------------------------------
process_data <- function(data) {
  tryCatch({
    cat(glue("[PRE_PROCESSAMENTO] {nrow(data)} bairros recebidos do bronze.\n"))

    registros <- as_tibble(data) |>
      transmute(
        cd_bairro        = as.character(CD_BAIRRO),
        nm_bairro_raw    = as.character(NM_BAIRRO),
        cd_municipio     = as.character(CD_MUN),
        nm_municipio_raw = as.character(NM_MUN),
        cd_distrito      = as.character(CD_DIST),
        nm_distrito_raw  = as.character(NM_DIST),
        sigla_uf         = as.character(sigla_uf),
        ano_censo        = as.integer(ano_censo),
        geometry_wkt     = as.character(geometry_wkt),
        data_coleta      = as.character(data_coleta)
      )

    # --- Validação 1: cd_bairro duplicado dentro da mesma UF ---
    duplicatas_uf <- registros |>
      group_by(sigla_uf, cd_bairro) |>
      filter(n() > 1) |>
      ungroup()

    if (nrow(duplicatas_uf) > 0) {
      n_dup <- n_distinct(paste(duplicatas_uf$sigla_uf, duplicatas_uf$cd_bairro))
      cat(glue("[PRE_PROCESSAMENTO] AVISO: {n_dup} pares (UF + cd_bairro) duplicados:\n"))
      duplicatas_uf |>
        count(sigla_uf, name = "n_duplicatas") |>
        arrange(desc(n_duplicatas)) |>
        print()
    } else {
      cat("[PRE_PROCESSAMENTO] Validação de duplicatas cd_bairro por UF: OK\n")
    }

    # --- Validação 2: geometry_wkt vazia ---
    sem_geometry <- registros |> filter(is.na(geometry_wkt) | str_trim(geometry_wkt) == "")
    if (nrow(sem_geometry) > 0) {
      cat(glue("[PRE_PROCESSAMENTO] AVISO: {nrow(sem_geometry)} bairros sem geometry_wkt:\n"))
      sem_geometry |> count(sigla_uf, name = "n_sem_geom") |> print()
    } else {
      cat("[PRE_PROCESSAMENTO] Validação geometry_wkt: OK\n")
    }

    # --- Validação 3: UFs presentes ---
    n_ufs <- n_distinct(registros$sigla_uf)
    # DF e TO não têm shapefile no Censo 2022 — esperado 25/27
    cat(glue("[PRE_PROCESSAMENTO] UFs com dados: {n_ufs}/27 (DF e TO sem shapefile no Censo 2022 é esperado)\n"))

    # --- Validação 4: nomes com encoding suspeito (caracteres de substituição) ---
    encoding_suspeito <- registros |>
      filter(str_detect(nm_bairro_raw, "\ufffd") | str_detect(nm_municipio_raw, "\ufffd"))
    if (nrow(encoding_suspeito) > 0) {
      cat(glue("[PRE_PROCESSAMENTO] AVISO: {nrow(encoding_suspeito)} registros com caracteres de encoding inválido.\n"))
      encoding_suspeito |> count(sigla_uf, name = "n") |> print()
    } else {
      cat("[PRE_PROCESSAMENTO] Validação de encoding: OK\n")
    }

    cat(glue("[PRE_PROCESSAMENTO] {nrow(registros)} bairros após pré-processamento.\n"))
    registros
  }, error = function(e) {
    cat("[PRE_PROCESSAMENTO] Erro:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

# ------------------------------------------------------------------------------
# 3. SALVAR SILVER
# ------------------------------------------------------------------------------
save_to_minio_duckdb <- function(data) {
  tryCatch({
    filepath <- sprintf("silver/base_bairros/silver_bairros_%s.parquet", format(Sys.time(), "%Y%m%d"))
    cat(glue("[PRE_PROCESSAMENTO] Salvando em: {filepath}\n"))
    write_parquet_to_minio(data, filepath)
    filepath
  }, error = function(e) {
    cat("[PRE_PROCESSAMENTO] Erro ao salvar:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

bronze <- read_from_minio_duckdb()
silver <- process_data(bronze)
saida  <- save_to_minio_duckdb(silver)
cat("[PRE_PROCESSAMENTO] Finalizado:", saida, "\n")
