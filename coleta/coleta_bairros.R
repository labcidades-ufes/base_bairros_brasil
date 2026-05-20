#!/usr/bin/env Rscript
# ==============================================================================
# COLETA — BASE BAIRROS
# Detecta o Censo mais recente, baixa shapefiles de todas as UFs disponíveis,
# converte geometria para WKT e salva bronze Parquet no MinIO.
# Saída: bronze/base_bairros/raw_bairros_YYYYMMDD.parquet
# ==============================================================================
library(httr2)
library(sf)
library(dplyr)
library(glue)
library(stringi)
source("utils.R")
Sys.setlocale("LC_ALL", "C.UTF-8")

UFS <- c("AC","AL","AM","AP","BA","CE","DF","ES","GO","MA","MG","MS","MT",
         "PA","PB","PE","PI","PR","RJ","RN","RO","RR","RS","SC","SE","SP","TO")

BASE_BAIRROS <- paste0(
  "https://geoftp.ibge.gov.br/organizacao_do_territorio/malhas_territoriais/",
  "malhas_de_setores_censitarios__divisoes_intramunicipais/"
)
ANOS_CANDIDATOS <- c(2022, 2010)

# ------------------------------------------------------------------------------
# 1. DESCOBERTA DO ANO DE CENSO
# ------------------------------------------------------------------------------
descobrir_ano_censo <- function() {
  cat("[COLETA] Verificando Censo disponível...\n")
  for (ano in ANOS_CANDIDATOS) {
    url_teste <- glue("{BASE_BAIRROS}censo_{ano}/bairros/shp/UF/AC_bairros_CD{ano}.zip")
    ok <- tryCatch({
      resp <- req_perform(request(url_teste) |> req_method("HEAD") |> req_error(is_error = \(r) FALSE))
      resp_status(resp) == 200
    }, error = function(e) FALSE)
    if (ok) {
      cat(glue("[COLETA] Censo {ano} encontrado.\n"))
      return(ano)
    }
  }
  stop("Nenhum Censo encontrado.")
}

# ------------------------------------------------------------------------------
# 2. COLETA
# ------------------------------------------------------------------------------
collect_data <- function() {
  tryCatch({
    ano_censo <- descobrir_ano_censo()
    lista     <- list()

    for (uf in UFS) {
      url_zip <- glue("{BASE_BAIRROS}censo_{ano_censo}/bairros/shp/UF/{uf}_bairros_CD{ano_censo}.zip")
      zip_tmp <- tempfile(fileext = ".zip")
      shp_dir <- tempfile()
      dir.create(shp_dir)

      ok <- tryCatch({
        download.file(url_zip, zip_tmp, mode = "wb", quiet = TRUE)
        TRUE
      }, error = function(e) FALSE)

      if (!ok) {
        cat(glue("[COLETA] {uf}: não disponível (404).\n"))
        next
      }

      unzip(zip_tmp, exdir = shp_dir)
      shp_files <- list.files(shp_dir, pattern = "\\.shp$", full.names = TRUE, recursive = TRUE)

      if (length(shp_files) == 0) {
        cat(glue("[COLETA] {uf}: shapefile não encontrado.\n"))
        next
      }

      bairros_uf <- tryCatch(
        st_read(shp_files[1], quiet = TRUE),
        error = function(e) {
          cat(glue("[COLETA] {uf}: falha na leitura do shapefile.\n"))
          NULL
        }
      )

      if (is.null(bairros_uf) || nrow(bairros_uf) == 0) {
        cat(glue("[COLETA] {uf}: falha na leitura.\n"))
        next
      }

      # Converte geometry para WKT antes de salvar como Parquet
      df <- bairros_uf |>
        mutate(geometry_wkt = st_as_text(geometry)) |>
        st_set_geometry(NULL) |>
        mutate(
          sigla_uf  = uf,
          ano_censo = as.integer(ano_censo),
          data_coleta = format(Sys.time(), "%Y%m%d")
        )

      lista[[uf]] <- df
      cat(glue("[COLETA] {uf}: {nrow(df)} bairros\n"))
      unlink(c(zip_tmp, shp_dir), recursive = TRUE)
    }

    if (length(lista) == 0) stop("Nenhuma UF coletada com sucesso.")
    bind_rows(lista)
  }, error = function(e) {
    cat("[COLETA] Erro:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

# ------------------------------------------------------------------------------
# 3. SALVAR BRONZE
# ------------------------------------------------------------------------------
save_to_minio_duckdb <- function(data) {
  tryCatch({
    timestamp <- format(Sys.time(), "%Y%m%d")
    filepath  <- sprintf("bronze/base_bairros/raw_bairros_%s.parquet", timestamp)
    write_parquet_to_minio(data, filepath)
    filepath
  }, error = function(e) {
    cat("[COLETA] Erro ao salvar:", conditionMessage(e), "\n")
    quit(status = 1)
  })
}

dados   <- collect_data()
arquivo <- save_to_minio_duckdb(dados)
cat("[COLETA] Finalizado:", arquivo, "\n")
cat(glue("[COLETA] {nrow(dados)} bairros | {n_distinct(dados$sigla_uf)} UFs\n"))
