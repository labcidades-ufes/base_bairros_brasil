#!/usr/bin/env Rscript
# ==============================================================================
# PROCESSAMENTO — BASE BAIRROS (Gold)
# Lê silver, aplica limpeza de texto e produz schema final.
# Entrada:  silver/base_bairros/silver_bairros_YYYYMMDD.parquet
# Saída:    gold/base_bairros/gold_bairros_YYYYMMDD.parquet
# Schema:   cd_bairro | nome_bairro | nome_bairro_original | cd_municipio |
#           nome_municipio | cd_distrito | nome_distrito | sigla_uf | ano_censo
# Nota:     geometry_wkt é removido no gold — use silver se precisar da geometria.
# ==============================================================================
library(dplyr)
library(stringi)
library(stringr)
library(glue)
source("utils.R")
Sys.setlocale("LC_ALL", "C.UTF-8")

limpar_texto <- function(x) {
  x |> stri_trans_general("Latin-ASCII") |> str_to_upper() |> str_squish()
}

read_silver <- function() {
  cat("[GOLD] Lendo silver...\n")
  tryCatch({
    arquivos <- list_parquet_files_in_minio("silver/base_bairros/")
    if (length(arquivos) == 0) stop("Nenhum arquivo silver encontrado.")
    caminho <- sub(sprintf("^s3://%s/", Sys.getenv("MINIO_BUCKET", "airflow")), "",
                   sort(arquivos, decreasing = TRUE)[1])
    cat(glue("[GOLD] Lendo: {caminho}\n"))
    read_parquet_from_minio(caminho)
  }, error = function(e) {
    cat("[GOLD] Erro ao ler silver:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

generate_products <- function(silver) {
  tryCatch({
    cat(glue("[GOLD] Gerando gold com {nrow(silver)} bairros...\n"))

    silver |>
      transmute(
        cd_bairro            = cd_bairro,
        nome_bairro          = limpar_texto(nm_bairro_raw),
        nome_bairro_original = nm_bairro_raw,
        cd_municipio         = cd_municipio,
        nome_municipio       = limpar_texto(nm_municipio_raw),
        cd_distrito          = cd_distrito,
        nome_distrito        = limpar_texto(nm_distrito_raw),
        sigla_uf             = sigla_uf,
        ano_censo            = ano_censo
        # geometry_wkt omitido no gold — disponível no silver
      ) |>
      arrange(sigla_uf, nome_municipio, nome_bairro)
  }, error = function(e) {
    cat("[GOLD] Erro na transformação:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

save_gold <- function(data) {
  tryCatch({
    filepath <- sprintf("gold/base_bairros/gold_bairros_%s.parquet", format(Sys.time(), "%Y%m%d"))
    write_parquet_to_minio(data, filepath)
    cat("[GOLD] Salvo em:", filepath, "\n")
    filepath
  }, error = function(e) {
    cat("[GOLD] Erro ao salvar:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

silver <- read_silver()
gold   <- generate_products(silver)
saida  <- save_gold(gold)
cat(glue("[GOLD] Finalizado: {nrow(gold)} bairros | {n_distinct(gold$sigla_uf)} UFs\n"))
